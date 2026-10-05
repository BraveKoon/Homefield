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
        // 2026-09-30 실제 응답으로 확인: /schedule/games/{id}/relay (inning 생략 시 현재 이닝). /game/{id}/relay 는 404.
        let url = makeURL("schedule/games/\(gameId)/relay", query: query)

        async let relay: NaverEnvelope<NaverRelayResult> = get(url)
        let game = try? await gameSummary(id: gameId)
        let data = try await relay.result?.textRelayData
        return NaverMapping.snapshot(from: data, game: game)
    }

    public func gameSummary(id: String) async throws -> GameSummary? {
        let envelope: NaverEnvelope<NaverGameResult> = try await get(makeURL("schedule/games/\(id)", query: [:]))
        return envelope.result?.game.map(NaverMapping.summary(from:))
    }

    /// 팀 선수들의 시즌 기록 (타자·투수). 2026-10-05 실제 응답으로 확인한 경로·필드.
    public func teamSeasonStats(teamCode: String, season: Int) async throws -> [SeasonStats] {
        var stats: [SeasonStats] = []
        for type in ["HITTER", "PITCHER"] {
            let url = makeURL("statistics/categories/kbo/seasons/\(season)/players", query: [
                "playerType": type,
                "teamCode": teamCode,
                "pageSize": "100",
            ])
            let envelope: NaverEnvelope<NaverSeasonStatsResult> = try await get(url)
            stats += NaverMapping.seasonStats(from: envelope.result, kind: type == "HITTER" ? .batter : .pitcher)
        }
        return stats
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

    public static func parseTeamSeasonStats(_ data: Data, kind: SeasonStats.Kind) throws -> [SeasonStats] {
        let envelope = try JSONDecoder().decode(NaverEnvelope<NaverSeasonStatsResult>.self, from: data)
        return seasonStats(from: envelope.result, kind: kind)
    }

    static func seasonStats(from result: NaverSeasonStatsResult?, kind: SeasonStats.Kind) -> [SeasonStats] {
        (result?.seasonPlayerStats ?? []).compactMap { row in
            guard let id = row.playerId?.value, !id.isEmpty else { return nil }
            var stats = SeasonStats(playerId: id, kind: kind)
            switch kind {
            case .batter:
                stats.games = row.hitterGameCount?.value
                stats.average = row.hitterHra?.value
                stats.atBats = row.hitterAb?.value
                stats.hits = row.hitterHit?.value
                stats.homeRuns = row.hitterHr?.value
                stats.rbi = row.hitterRbi?.value
                stats.onBase = row.hitterObp?.value
                stats.strikeouts = row.hitterKk?.value
                stats.walks = row.hitterBb?.value
            case .pitcher:
                stats.games = row.pitcherGameCount?.value
                stats.era = row.pitcherEra?.value
                stats.wins = row.pitcherWin?.value
                stats.losses = row.pitcherLose?.value
                stats.saves = row.pitcherSave?.value
                stats.innings = row.pitcherInning?.value
                stats.strikeouts = row.pitcherKk?.value
                stats.walks = row.pitcherBb?.value
            }
            return stats
        }
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
            stadium: game.stadium,
            lineScore: lineScore(from: game)
        )
    }

    /// 2026-10-05 실제 응답으로 확인: homeTeamScoreByInning ["4","0",...], homeTeamRheb [R, H, E, B]
    static func lineScore(from game: NaverGame) -> LineScore? {
        func line(_ innings: [LenientString]?, _ rheb: [LenientInt]?) -> LineScore.Line {
            let scores = (innings ?? []).map { item -> Int? in
                item.value.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            }
            let totals = (rheb ?? []).map(\.value)
            func total(_ index: Int) -> Int? { index < totals.count ? totals[index] : nil }
            return LineScore.Line(innings: scores, runs: total(0), hits: total(1), errors: total(2), walks: total(3))
        }
        let away = line(game.awayTeamScoreByInning, game.awayTeamRheb)
        let home = line(game.homeTeamScoreByInning, game.homeTeamRheb)
        if away.innings.isEmpty && home.innings.isEmpty && away.runs == nil && home.runs == nil { return nil }
        return LineScore(away: away, home: home)
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
                    batterId: option.batterRecord?.pcode?.value,
                    state: option.currentGameState?.countState,
                    seasonStats: seasonStats(of: option)
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

        var pitchers: [TeamSide: [Player]] = [:]
        if let home = data.homeLineup?.pitcher {
            pitchers[.home] = home.compactMap { player(from: $0, teamCode: game?.home.code ?? "", fallbackPosition: "투수") }
        }
        if let away = data.awayLineup?.pitcher {
            pitchers[.away] = away.compactMap { player(from: $0, teamCode: game?.away.code ?? "", fallbackPosition: "투수") }
        }

        var benches: [TeamSide: [Player]] = [:]
        for (side, entry) in [(TeamSide.home, data.homeEntry), (.away, data.awayEntry)] {
            guard let entry else { continue }
            let code = game?.team(for: side).code ?? ""
            let players = (entry.pitcher ?? []).compactMap { player(from: $0, teamCode: code, fallbackPosition: "투수") }
                + (entry.batter ?? []).compactMap { player(from: $0, teamCode: code) }
            if !players.isEmpty { benches[side] = players }
        }

        return RelaySnapshot(
            game: game,
            currentInning: data.textRelays?.compactMap { $0.inn?.value }.max(),
            entries: entries,
            lineups: lineups,
            pitchers: pitchers,
            benches: benches
        )
    }

    /// currentPlayersInfo 의 타자·투수 시즌 기록. 선수 코드는 currentGameState 의 batter/pitcher.
    static func seasonStats(of option: NaverTextOption) -> [SeasonStats] {
        guard let info = option.currentPlayersInfo else { return [] }
        return [info.away, info.home].compactMap { player -> SeasonStats? in
            guard let player, let stats = player.currentSeasonStats else { return nil }
            switch player.playerType?.lowercased() {
            case "batter":
                guard let id = validId(option.currentGameState?.batter?.value) else { return nil }
                var result = SeasonStats(playerId: id, kind: .batter)
                result.average = stats.hra?.value
                result.atBats = stats.ab?.value
                result.hits = stats.hit?.value
                result.homeRuns = stats.hr?.value
                result.rbi = stats.rbi?.value
                result.onBase = stats.obp?.value
                guard (result.atBats ?? 0) > 0 else { return nil }
                return result
            case "pitcher":
                guard let id = validId(option.currentGameState?.pitcher?.value) else { return nil }
                var result = SeasonStats(playerId: id, kind: .pitcher)
                result.games = stats.gameCount?.value
                result.era = stats.era?.value
                result.wins = stats.w?.value
                result.losses = stats.l?.value
                result.saves = stats.s?.value
                result.innings = stats.inn2?.value ?? stats.inn?.value
                result.strikeouts = stats.kk?.value
                result.walks = stats.bb?.value
                guard (result.games ?? 0) > 0 else { return nil }
                return result
            default:
                return nil
            }
        }
    }

    private static func validId(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty, value != "0" else { return nil }
        return value
    }

    static func player(from batter: NaverLineupBatter, teamCode: String, fallbackPosition: String? = nil) -> Player? {
        guard let name = batter.name, !name.isEmpty else { return nil }
        // 라인업의 pos 는 숫자(9), 엔트리의 pos 는 "유격수" 같은 글자
        let textPosition = batter.pos?.value.flatMap { Int($0) == nil && !$0.isEmpty ? $0 : nil }
        return Player(
            id: batter.pcode?.value ?? "\(teamCode)-\(name)",
            name: name,
            teamCode: teamCode,
            backNumber: batter.backnum?.value,
            battingOrder: batter.batOrder?.value,
            position: batter.posName ?? textPosition ?? fallbackPosition
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
    let homeTeamScoreByInning: [LenientString]?
    let awayTeamScoreByInning: [LenientString]?
    let homeTeamRheb: [LenientInt]?
    let awayTeamRheb: [LenientInt]?
}

struct NaverSeasonStatsResult: Decodable {
    let seasonPlayerStats: [NaverSeasonPlayerStats]?
}

struct NaverSeasonPlayerStats: Decodable {
    let playerId: LenientString?
    let playerName: String?
    let backNumber: LenientString?
    let hitterGameCount: LenientInt?
    let hitterHra: LenientDouble?
    let hitterAb: LenientInt?
    let hitterHit: LenientInt?
    let hitterHr: LenientInt?
    let hitterRbi: LenientInt?
    let hitterObp: LenientDouble?
    let hitterKk: LenientInt?
    let hitterBb: LenientInt?
    let pitcherGameCount: LenientInt?
    let pitcherEra: LenientDouble?
    let pitcherWin: LenientInt?
    let pitcherLose: LenientInt?
    let pitcherSave: LenientInt?
    let pitcherInning: LenientString?
    let pitcherKk: LenientInt?
    let pitcherBb: LenientInt?
}

struct NaverRelayResult: Decodable {
    let textRelayData: NaverTextRelayData?
}

struct NaverTextRelayData: Decodable {
    let textRelays: [NaverTextRelay]?
    let homeLineup: NaverLineup?
    let awayLineup: NaverLineup?
    /// 그날 엔트리 (2026-09-30 실제 응답: batter 목록에 name, pcode, pos("유격수"), hittype)
    let homeEntry: NaverLineup?
    let awayEntry: NaverLineup?
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
    let currentGameState: NaverGameState?
    let currentPlayersInfo: NaverPlayersInfo?
}

/// 2026-09-30 실제 응답으로 확인. 지금 타자·투수의 기록이 홈/원정으로 나뉘어 온다.
struct NaverPlayersInfo: Decodable {
    let away: NaverPlayerInfo?
    let home: NaverPlayerInfo?
}

struct NaverPlayerInfo: Decodable {
    let playerType: String?
    let currentSeasonStats: NaverPlayerStats?
}

struct NaverPlayerStats: Decodable {
    // 타자
    let ab: LenientInt?
    let hit: LenientInt?
    let hra: LenientDouble?
    let hr: LenientInt?
    let rbi: LenientInt?
    let obp: LenientDouble?
    // 투수
    let gameCount: LenientInt?
    let era: LenientDouble?
    let w: LenientInt?
    let l: LenientInt?
    let s: LenientInt?
    let inn: LenientString?
    let inn2: LenientString?
    let kk: LenientInt?
    let bb: LenientInt?
}

/// 2026-09-30 실제 응답으로 필드 이름 확인. 주자가 없으면 base 값이 "0", 있으면 선수 코드.
struct NaverGameState: Decodable {
    let ball: LenientInt?
    let strike: LenientInt?
    let out: LenientInt?
    let base1: LenientString?
    let base2: LenientString?
    let base3: LenientString?
    let pitcher: LenientString?
    let batter: LenientString?

    var countState: CountState? {
        guard ball?.value != nil || strike?.value != nil || out?.value != nil else { return nil }
        let bases = [base1, base2, base3].map { base -> Bool in
            guard let value = base?.value?.trimmingCharacters(in: .whitespaces) else { return false }
            return !value.isEmpty && value != "0"
        }
        let pitcherId = pitcher?.value.flatMap { $0.isEmpty || $0 == "0" ? nil : $0 }
        return CountState(balls: ball?.value, strikes: strike?.value, outs: out?.value, basesOccupied: bases, pitcherId: pitcherId)
    }
}

struct NaverBatterRecord: Decodable {
    let pcode: LenientString?
    let name: String?
}

struct NaverLineup: Decodable {
    let batter: [NaverLineupBatter]?
    let pitcher: [NaverLineupBatter]?
}

struct NaverLineupBatter: Decodable {
    let pcode: LenientString?
    let name: String?
    let batOrder: LenientInt?
    let backnum: LenientString?
    let posName: String?
    let pos: LenientString?
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

struct LenientDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = Double(string.trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
    }
}
