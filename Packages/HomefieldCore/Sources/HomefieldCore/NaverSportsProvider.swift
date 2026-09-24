import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 네이버 스포츠 KBO 문자중계 데이터.
///
/// 공식 공개 API 가 아니므로 응답 형식이 예고 없이 바뀔 수 있다.
/// 모든 필드를 느슨하게(optional) 해석하고, 매핑은 `NaverMapping` 한 곳에 모아 두었다.
public struct NaverSportsProvider: GameDataProvider {
    public var baseURL: URL
    public var session: URLSession

    public init(
        baseURL: URL = URL(string: "https://api-gw.sports.naver.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func games(on date: Date) async throws -> [GameSummary] {
        let day = NaverMapping.dayFormatter.string(from: date)
        let url = makeURL("schedule/games", query: [
            "fields": "basic",
            "upperCategoryId": "kbaseball",
            "categoryId": "kbo",
            "fromDate": day,
            "toDate": day,
            "size": "100",
        ])
        let envelope: NaverEnvelope<NaverScheduleResult> = try await get(url)
        return (envelope.result?.games ?? []).map(NaverMapping.summary(from:))
    }

    public func relay(gameId: String, inning: Int?) async throws -> RelaySnapshot {
        var query: [String: String] = [:]
        if let inning { query["inning"] = String(inning) }
        let url = makeURL("game/\(gameId)/relay", query: query)

        async let relay: NaverEnvelope<NaverRelayResult> = get(url)
        let game = try? await gameSummary(id: gameId)
        let data = try await relay.result?.textRelayData
        return NaverMapping.snapshot(from: data, game: game)
    }

    public func gameSummary(id: String) async throws -> GameSummary? {
        let envelope: NaverEnvelope<NaverGameResult> = try await get(makeURL("schedule/games/\(id)", query: [:]))
        return envelope.result?.game.map(NaverMapping.summary(from:))
    }

    private func makeURL(_ path: String, query: [String: String]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("https://m.sports.naver.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GameDataError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - 매핑

public enum NaverMapping {
    static let seoul = TimeZone(identifier: "Asia/Seoul")!

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = seoul
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = seoul
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    public static func parseGames(_ data: Data) throws -> [GameSummary] {
        let envelope = try JSONDecoder().decode(NaverEnvelope<NaverScheduleResult>.self, from: data)
        return (envelope.result?.games ?? []).map(summary(from:))
    }

    public static func parseRelay(_ data: Data, game: GameSummary?) throws -> RelaySnapshot {
        let envelope = try JSONDecoder().decode(NaverEnvelope<NaverRelayResult>.self, from: data)
        return snapshot(from: envelope.result?.textRelayData, game: game)
    }

    static func summary(from game: NaverGame) -> GameSummary {
        let homeCode = game.homeTeamCode?.value ?? "HOME"
        let awayCode = game.awayTeamCode?.value ?? "AWAY"
        return GameSummary(
            id: game.gameId.value ?? "",
            home: Team(code: homeCode, name: game.homeTeamName ?? KBOTeams.name(for: homeCode) ?? homeCode),
            away: Team(code: awayCode, name: game.awayTeamName ?? KBOTeams.name(for: awayCode) ?? awayCode),
            homeScore: game.homeTeamScore?.value,
            awayScore: game.awayTeamScore?.value,
            status: status(code: game.statusCode, cancelled: game.cancel ?? false),
            statusText: game.statusInfo,
            startTime: game.gameDateTime.flatMap(dateTimeFormatter.date(from:)),
            stadium: game.stadium
        )
    }

    static func status(code: String?, cancelled: Bool) -> GameStatus {
        if cancelled { return .cancelled }
        switch code?.uppercased() {
        case "BEFORE", "READY": return .scheduled
        case "STARTED", "PLAYING", "LIVE": return .live
        case "RESULT", "ENDED", "END": return .finished
        case "CANCEL", "CANCELED", "CANCELLED": return .cancelled
        default: return .unknown
        }
    }

    static func snapshot(from data: NaverTextRelayData?, game: GameSummary?) -> RelaySnapshot {
        guard let data else { return RelaySnapshot(game: game, entries: []) }

        var entries: [RelayEntry] = []
        var usedIds = Set<String>()
        for relay in data.textRelays ?? [] {
            let inning = relay.inn?.value
            let side: TeamSide? = switch relay.homeOrAway?.value ?? "" {
            case "0": .away   // 초 공격
            case "1": .home   // 말 공격
            default: nil
            }
            let half = (inning ?? 0) * 2 + (side == .home ? 1 : 0)

            for (offset, option) in (relay.textOptions ?? []).enumerated() {
                let text = (option.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let seq = option.seqno?.value ?? ((relay.no?.value ?? 0) * 100 + offset)
                var id = "\(inning ?? 0)-\(side?.rawValue ?? "x")-\(seq)"
                if usedIds.contains(id) { id += "-\(offset)" }
                usedIds.insert(id)
                entries.append(RelayEntry(
                    id: id,
                    sequence: half * 100_000 + seq,
                    inning: inning,
                    battingSide: side,
                    text: text,
                    batterId: option.batterRecord?.pcode?.value
                ))
            }
        }

        var lineups: [TeamSide: [Player]] = [:]
        if let home = data.homeLineup?.batter {
            lineups[.home] = home.compactMap { player(from: $0, teamCode: game?.home.code ?? "") }
        }
        if let away = data.awayLineup?.batter {
            lineups[.away] = away.compactMap { player(from: $0, teamCode: game?.away.code ?? "") }
        }

        return RelaySnapshot(
            game: game,
            currentInning: data.textRelays?.compactMap { $0.inn?.value }.max(),
            entries: entries,
            lineups: lineups
        )
    }

    static func player(from batter: NaverLineupBatter, teamCode: String) -> Player? {
        guard let name = batter.name, !name.isEmpty else { return nil }
        return Player(
            id: batter.pcode?.value ?? "\(teamCode)-\(name)",
            name: name,
            teamCode: teamCode,
            backNumber: batter.backnum?.value,
            battingOrder: batter.batOrder?.value,
            position: batter.posName
        )
    }
}

// MARK: - 응답 형식

struct NaverEnvelope<T: Decodable>: Decodable {
    let code: LenientInt?
    let success: Bool?
    let result: T?
}

struct NaverScheduleResult: Decodable {
    let games: [NaverGame]?
}

struct NaverGameResult: Decodable {
    let game: NaverGame?
}

struct NaverGame: Decodable {
    let gameId: LenientString
    let gameDateTime: String?
    let stadium: String?
    let homeTeamCode: LenientString?
    let homeTeamName: String?
    let awayTeamCode: LenientString?
    let awayTeamName: String?
    let homeTeamScore: LenientInt?
    let awayTeamScore: LenientInt?
    let statusCode: String?
    let statusInfo: String?
    let cancel: Bool?
}

struct NaverRelayResult: Decodable {
    let textRelayData: NaverTextRelayData?
}

struct NaverTextRelayData: Decodable {
    let textRelays: [NaverTextRelay]?
    let homeLineup: NaverLineup?
    let awayLineup: NaverLineup?
}

struct NaverTextRelay: Decodable {
    let no: LenientInt?
    let inn: LenientInt?
    let homeOrAway: LenientString?
    let title: String?
    let textOptions: [NaverTextOption]?
}

struct NaverTextOption: Decodable {
    let seqno: LenientInt?
    let type: LenientInt?
    let text: String?
    let batterRecord: NaverBatterRecord?
}

struct NaverBatterRecord: Decodable {
    let pcode: LenientString?
    let name: String?
}

struct NaverLineup: Decodable {
    let batter: [NaverLineupBatter]?
}

struct NaverLineupBatter: Decodable {
    let pcode: LenientString?
    let name: String?
    let batOrder: LenientInt?
    let backnum: LenientString?
    let posName: String?
}

/// 숫자가 문자열로 오기도 하고 숫자로 오기도 하는 필드용
struct LenientInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = Int(string.trimmingCharacters(in: .whitespaces))
        } else if let double = try? container.decode(Double.self) {
            value = Int(double)
        } else {
            value = nil
        }
    }
}

struct LenientString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else {
            value = nil
        }
    }
}
