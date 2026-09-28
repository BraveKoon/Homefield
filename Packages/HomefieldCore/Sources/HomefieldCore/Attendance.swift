import Foundation

/// KBO 구장
public struct Stadium: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// 경기 일정의 구장 표기 ("잠실", "문학" 등)
    public var aliases: [String]
    /// 홈 팀 코드
    public var teamCodes: [String]

    public init(id: String, name: String, latitude: Double, longitude: Double, aliases: [String], teamCodes: [String]) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.aliases = aliases
        self.teamCodes = teamCodes
    }

    /// 경기 일정의 구장 이름이 이 구장을 가리키는지
    public func matches(scheduleName: String?) -> Bool {
        guard let scheduleName, !scheduleName.isEmpty else { return false }
        return aliases.contains { scheduleName.contains($0) || $0.contains(scheduleName) }
    }
}

public enum Stadiums {
    /// 인증 반경 (구장 중심에서, 미터)
    public static let checkInRadius: Double = 500

    public static let all: [Stadium] = [
        Stadium(id: "jamsil", name: "잠실야구장", latitude: 37.5122, longitude: 127.0719, aliases: ["잠실"], teamCodes: ["LG", "OB"]),
        Stadium(id: "gocheok", name: "고척스카이돔", latitude: 37.4982, longitude: 126.8671, aliases: ["고척"], teamCodes: ["WO"]),
        Stadium(id: "munhak", name: "인천SSG랜더스필드", latitude: 37.4370, longitude: 126.6933, aliases: ["문학", "인천"], teamCodes: ["SK"]),
        Stadium(id: "suwon", name: "수원KT위즈파크", latitude: 37.2997, longitude: 127.0097, aliases: ["수원"], teamCodes: ["KT"]),
        Stadium(id: "daejeon", name: "대전한화생명볼파크", latitude: 36.3165, longitude: 127.4290, aliases: ["대전"], teamCodes: ["HH"]),
        Stadium(id: "daegu", name: "대구삼성라이온즈파크", latitude: 35.8411, longitude: 128.6815, aliases: ["대구"], teamCodes: ["SS"]),
        Stadium(id: "gwangju", name: "광주기아챔피언스필드", latitude: 35.1682, longitude: 126.8889, aliases: ["광주"], teamCodes: ["HT"]),
        Stadium(id: "sajik", name: "사직야구장", latitude: 35.1940, longitude: 129.0616, aliases: ["사직", "부산"], teamCodes: ["LT"]),
        Stadium(id: "changwon", name: "창원NC파크", latitude: 35.2225, longitude: 128.5823, aliases: ["창원"], teamCodes: ["NC"]),
        Stadium(id: "pohang", name: "포항야구장", latitude: 36.0082, longitude: 129.3593, aliases: ["포항"], teamCodes: ["SS"]),
        Stadium(id: "ulsan", name: "울산문수야구장", latitude: 35.5322, longitude: 129.2657, aliases: ["울산"], teamCodes: ["LT"]),
        Stadium(id: "cheongju", name: "청주야구장", latitude: 36.6389, longitude: 127.4700, aliases: ["청주"], teamCodes: ["HH"]),
    ]

    public static func stadium(id: String) -> Stadium? {
        all.first { $0.id == id }
    }

    /// 가장 가까운 구장과 거리(미터)
    public static func nearest(latitude: Double, longitude: Double) -> (stadium: Stadium, distance: Double)? {
        all.map { ($0, distance(latitude, longitude, $0.latitude, $0.longitude)) }
            .min { $0.1 < $1.1 }
            .map { (stadium: $0.0, distance: $0.1) }
    }

    /// 두 좌표 사이 거리 (하버사인, 미터)
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// 직관 인증 횟수에 따른 등급
public enum FanTier: Int, CaseIterable, Comparable, Sendable {
    case rookie
    case lover
    case mania
    case player
    case coach
    case manager

    public var title: String {
        switch self {
        case .rookie: "야린이"
        case .lover: "야구러버"
        case .mania: "야구 매니아"
        case .player: "선수"
        case .coach: "코치"
        case .manager: "감독"
        }
    }

    public var emoji: String {
        switch self {
        case .rookie: "🐣"
        case .lover: "❤️"
        case .mania: "🔥"
        case .player: "⚾️"
        case .coach: "📋"
        case .manager: "🏆"
        }
    }

    /// 이 등급이 되는 최소 직관 횟수
    public var threshold: Int {
        switch self {
        case .rookie: 0
        case .lover: 3
        case .mania: 10
        case .player: 20
        case .coach: 35
        case .manager: 50
        }
    }

    public static func tier(forCheckIns count: Int) -> FanTier {
        allCases.last { count >= $0.threshold } ?? .rookie
    }

    public var next: FanTier? {
        FanTier(rawValue: rawValue + 1)
    }

    /// 다음 등급까지 진행률 0...1 (최고 등급이면 1)
    public static func progress(forCheckIns count: Int) -> Double {
        let current = tier(forCheckIns: count)
        guard let next = current.next else { return 1 }
        let span = Double(next.threshold - current.threshold)
        return min(max(Double(count - current.threshold) / span, 0), 1)
    }

    public static func < (lhs: FanTier, rhs: FanTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
