import CoreLocation
import Foundation
import HomefieldCore
import Observation

/// 직관 인증 한 번
struct CheckIn: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var stadiumId: String
    var gameId: String?
    /// "LG vs 삼성"
    var gameTitle: String?

    var stadium: Stadium? { Stadiums.stadium(id: stadiumId) }
}

enum CheckInError: LocalizedError {
    case locationDenied
    case locationUnavailable
    case inaccurate(Double)
    case notAtStadium(nearest: String, distance: Double)
    case alreadyCheckedIn(String)
    case noGameToday(String)
    case scheduleUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .locationDenied:
            "위치 권한이 필요합니다. 설정 앱 → 홈구장 → 위치에서 '앱을 사용하는 동안'을 허용해 주세요."
        case .locationUnavailable:
            "현재 위치를 가져오지 못했습니다. 잠시 후 다시 시도해 주세요."
        case .inaccurate(let accuracy):
            "위치 정확도가 낮습니다 (오차 약 \(Int(accuracy))m). 탁 트인 곳에서 다시 시도해 주세요."
        case .notAtStadium(let nearest, let distance):
            "야구장 안이 아닌 것 같아요. 가장 가까운 \(nearest)까지 \(Self.format(distance))."
        case .alreadyCheckedIn(let stadium):
            "오늘 \(stadium) 직관은 이미 인증했어요."
        case .noGameToday(let stadium):
            "오늘 \(stadium)에서 열리는 경기가 없어요."
        case .scheduleUnavailable(let reason):
            "경기 일정을 확인하지 못했습니다: \(reason)"
        }
    }

    private static func format(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1fkm", meters / 1000) : "\(Int(meters))m"
    }
}

/// 직관 인증 기록과 등급. 기기 안에만 저장된다 (좌표는 저장하지 않고 구장만 남긴다).
@MainActor
@Observable
final class AttendanceStore {
    private(set) var checkIns: [CheckIn] = []

    @ObservationIgnored private let storeURL: URL
    @ObservationIgnored private let locator = LocationVerifier()

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("attendance.json")
        load()
    }

    var count: Int { checkIns.count }
    var tier: FanTier { FanTier.tier(forCheckIns: count) }
    var progress: Double { FanTier.progress(forCheckIns: count) }

    /// 다음 등급까지 남은 횟수
    var remainingToNext: Int? {
        tier.next.map { $0.threshold - count }
    }

    func visits(to stadium: Stadium) -> Int {
        checkIns.filter { $0.stadiumId == stadium.id }.count
    }

    /// 위치 확인 → 가장 가까운 구장 반경 안인지 → 오늘 그 구장 경기가 있는지 → 기록
    func checkIn(schedule: any GameDataProvider) async throws -> CheckIn {
        let location = try await locator.currentLocation()
        guard location.timestamp.timeIntervalSinceNow > -120 else {
            throw CheckInError.locationUnavailable
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 200 else {
            throw CheckInError.inaccurate(location.horizontalAccuracy)
        }
        guard let nearest = Stadiums.nearest(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else { throw CheckInError.locationUnavailable }
        guard nearest.distance <= Stadiums.checkInRadius else {
            throw CheckInError.notAtStadium(nearest: nearest.stadium.name, distance: nearest.distance)
        }

        let stadium = nearest.stadium
        let today = Date()
        if checkIns.contains(where: { $0.stadiumId == stadium.id && Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            throw CheckInError.alreadyCheckedIn(stadium.name)
        }

        let games: [GameSummary]
        do {
            games = try await schedule.games(on: today)
        } catch {
            throw CheckInError.scheduleUnavailable(error.localizedDescription)
        }
        guard let game = games.first(where: { stadium.matches(scheduleName: $0.stadium) && $0.status != .cancelled }) else {
            throw CheckInError.noGameToday(stadium.name)
        }

        let checkIn = CheckIn(
            date: today,
            stadiumId: stadium.id,
            gameId: game.id,
            gameTitle: "\(game.away.name) vs \(game.home.name)"
        )
        checkIns.insert(checkIn, at: 0)
        save()
        return checkIn
    }

    func remove(_ checkIn: CheckIn) {
        checkIns.removeAll { $0.id == checkIn.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let stored = try? JSONDecoder().decode([CheckIn].self, from: data) else { return }
        checkIns = stored.sorted { $0.date > $1.date }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(checkIns) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

/// 한 번만 현재 위치를 가져온다
@MainActor
final class LocationVerifier: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            throw CheckInError.locationDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation?.resume(throwing: CheckInError.locationUnavailable)
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            self.authorizationContinuation?.resume()
            self.authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: CheckInError.locationUnavailable)
            self.locationContinuation = nil
        }
    }
}
