import XCTest
@testable import HomefieldCore

final class RotationTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: 일정의 선발 예고

    /// 일정 응답에 선발 예고가 있으면 읽는다
    func testScheduleStarterNames() throws {
        let json = """
        {"code":200,"success":true,"result":{"games":[
          {"gameId":"20261026LGHT0","gameDateTime":"2026-10-26T18:30:00","stadium":"광주",
           "homeTeamCode":"HT","homeTeamName":"KIA","awayTeamCode":"LG","awayTeamName":"LG",
           "statusCode":"BEFORE","homeStarterName":"올러","awayStarterName":"임찬규"}
        ]}}
        """
        let game = try XCTUnwrap(NaverMapping.parseGames(Data(json.utf8)).first)
        XCTAssertEqual(game.homeStarter, "올러")
        XCTAssertEqual(game.awayStarter, "임찬규")
        XCTAssertEqual(game.starter(for: .home), "올러")
        XCTAssertEqual(game.starter(for: .away), "임찬규")
    }

    /// 선발 예고가 없거나 비어 있으면 없는 것으로 본다
    func testMissingStarterNames() throws {
        let json = """
        {"result":{"games":[
          {"gameId":"g1","homeTeamCode":"HT","awayTeamCode":"LG","statusCode":"BEFORE","homeStarterName":"  "}
        ]}}
        """
        let game = try XCTUnwrap(NaverMapping.parseGames(Data(json.utf8)).first)
        XCTAssertNil(game.homeStarter)
        XCTAssertNil(game.awayStarter)
    }

    // MARK: 지난 선발 등판

    func testCollectsRecentStartersFromRelay() async {
        let provider = RotationProvider(today: today, calendar: calendar)
        let starters = await StarterCollector(provider: provider, lookbackDays: 6, maxStarts: 3)
            .collect(teamCode: "HT", today: today, calendar: calendar)

        XCTAssertEqual(starters.teamCode, "HT")
        // 최근 등판이 앞 (어제, 그제, 사흘 전)
        XCTAssertEqual(starters.starts.map(\.pitcher.name), ["양현종", "네일", "올러"])
        XCTAssertEqual(starters.starts.map(\.opponentCode), ["LG", "LG", "SS"])
        XCTAssertEqual(starters.starts.map(\.isHome), [true, true, false])
        XCTAssertEqual(starters.pitchers.count, 3)
        XCTAssertFalse(starters.isEmpty)
    }

    func testStopsAtMaxStarts() async {
        let provider = RotationProvider(today: today, calendar: calendar)
        let starters = await StarterCollector(provider: provider, lookbackDays: 6, maxStarts: 1)
            .collect(teamCode: "HT", today: today, calendar: calendar)
        XCTAssertEqual(starters.starts.map(\.pitcher.name), ["양현종"])
    }

    func testSkipsGamesThatHaveNotStarted() async {
        let provider = RotationProvider(today: today, calendar: calendar)
        let starters = await StarterCollector(provider: provider, lookbackDays: 6, maxStarts: 5)
            .collect(teamCode: "HT", today: today, calendar: calendar)
        // 오늘 경기는 아직 안 했으니 등판 기록이 아니라 선발 예고로 들어간다
        XCTAssertFalse(starters.starts.contains { $0.gameId == "today" })
        XCTAssertEqual(starters.upcoming?.pitcher, "황동하")
        XCTAssertEqual(starters.upcoming?.opponentCode, "LG")
        XCTAssertEqual(starters.upcoming?.isHome, true)
    }

    func testOtherTeamGetsItsOwnStarters() async {
        let provider = RotationProvider(today: today, calendar: calendar)
        let starters = await StarterCollector(provider: provider, lookbackDays: 6, maxStarts: 3)
            .collect(teamCode: "LG", today: today, calendar: calendar)
        XCTAssertEqual(starters.starts.map(\.pitcher.name), ["손주영", "치리노스"])
        XCTAssertEqual(starters.upcoming?.pitcher, "임찬규")
        XCTAssertEqual(starters.upcoming?.isHome, false)
    }

    func testNoGamesMeansEmpty() async {
        let provider = RotationProvider(today: today, calendar: calendar)
        let starters = await StarterCollector(provider: provider, lookbackDays: 6, maxStarts: 3)
            .collect(teamCode: "WO", today: today, calendar: calendar)
        XCTAssertTrue(starters.isEmpty)
        XCTAssertNil(starters.upcoming)
    }
}

/// 어제·그제·사흘 전 경기와 오늘 예고가 있는 가짜 제공자
private struct RotationProvider: GameDataProvider {
    let today: Date
    let calendar: Calendar

    private func team(_ code: String) -> Team {
        Team(code: code, name: KBOTeams.name(for: code) ?? code)
    }

    func games(on date: Date) async throws -> [GameSummary] {
        let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: today)).day ?? 0
        switch back {
        case 0:
            // 오늘 경기는 아직 안 했고 선발만 예고됐다
            return [GameSummary(
                id: "today",
                home: team("HT"),
                away: team("LG"),
                status: .scheduled,
                startTime: date,
                homeStarter: "황동하",
                awayStarter: "임찬규"
            )]
        case 1:
            return [GameSummary(id: "d1", home: team("HT"), away: team("LG"), status: .finished, startTime: date)]
        case 2:
            return [GameSummary(id: "d2", home: team("HT"), away: team("LG"), status: .finished, startTime: date)]
        case 3:
            return [GameSummary(id: "d3", home: team("SS"), away: team("HT"), status: .finished, startTime: date)]
        default:
            return []
        }
    }

    func relay(gameId: String, inning: Int?) async throws -> RelaySnapshot {
        // 투수 명단 첫 번째가 그날 선발
        let starters: [String: (home: [String], away: [String])] = [
            "d1": (home: ["양현종", "전상현"], away: ["손주영"]),
            "d2": (home: ["네일"], away: ["치리노스", "유영찬"]),
            "d3": (home: ["원태인"], away: ["올러"]),
        ]
        guard let entry = starters[gameId] else { throw GameDataError.emptyResponse }
        func players(_ names: [String], _ code: String) -> [Player] {
            names.map { Player(id: "\(code)-\($0)", name: $0, teamCode: code, position: "투수") }
        }
        let homeCode = gameId == "d3" ? "SS" : "HT"
        let awayCode = gameId == "d3" ? "HT" : "LG"
        return RelaySnapshot(
            entries: [],
            pitchers: [.home: players(entry.home, homeCode), .away: players(entry.away, awayCode)]
        )
    }
}
