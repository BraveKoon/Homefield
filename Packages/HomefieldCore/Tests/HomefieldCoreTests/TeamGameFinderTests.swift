import XCTest
@testable import HomefieldCore

final class TeamGameFinderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func game(_ id: String, home: String, away: String, status: GameStatus, startOffset: TimeInterval = 0) -> GameSummary {
        GameSummary(
            id: id,
            home: Team(code: home, name: home),
            away: Team(code: away, name: away),
            status: status,
            startTime: now.addingTimeInterval(startOffset)
        )
    }

    func testFindsTodayGameForTeam() async throws {
        let provider = DayProvider(calendar: calendar, today: now, gamesByDay: [
            0: [game("a", home: "LG", away: "KT", status: .live), game("b", home: "HT", away: "SS", status: .live)],
        ])
        let result = try await TeamGameFinder(provider: provider).find(teamCode: "HT", now: now, calendar: calendar)
        XCTAssertEqual(result?.game.id, "b")
        XCTAssertEqual(result?.isToday, true)
    }

    func testFallsBackToNextGame() async throws {
        let provider = DayProvider(calendar: calendar, today: now, gamesByDay: [
            0: [game("a", home: "LG", away: "KT", status: .scheduled)],
            2: [game("c", home: "SS", away: "HT", status: .scheduled, startOffset: 2 * 86_400)],
        ])
        let result = try await TeamGameFinder(provider: provider).find(teamCode: "HT", now: now, calendar: calendar)
        XCTAssertEqual(result?.game.id, "c")
        XCTAssertEqual(result?.isToday, false)

        let none = try await TeamGameFinder(provider: provider, lookaheadDays: 1).find(teamCode: "HT", now: now, calendar: calendar)
        XCTAssertNil(none)
    }

    func testDoubleheaderPick() {
        let first = game("1", home: "HT", away: "LG", status: .finished, startOffset: -4 * 3600)
        let soon = game("2", home: "HT", away: "LG", status: .scheduled, startOffset: 30 * 60)
        let later = game("2", home: "HT", away: "LG", status: .scheduled, startOffset: 2 * 3600)
        let live = game("2", home: "HT", away: "LG", status: .live, startOffset: -600)
        XCTAssertEqual(TeamGameFinder.pick([first, soon], now: now)?.status, .scheduled)
        XCTAssertEqual(TeamGameFinder.pick([first, later], now: now)?.status, .finished)
        XCTAssertEqual(TeamGameFinder.pick([first, live], now: now)?.status, .live)
        XCTAssertNil(TeamGameFinder.pick([], now: now))
    }

    func testNextRefresh() {
        let live = TeamGameFinder.Result(game: game("a", home: "HT", away: "LG", status: .live), isToday: true)
        XCTAssertEqual(TeamGameFinder.nextRefresh(for: live, now: now), now.addingTimeInterval(300))

        let soon = TeamGameFinder.Result(game: game("a", home: "HT", away: "LG", status: .scheduled, startOffset: 1800), isToday: true)
        XCTAssertEqual(TeamGameFinder.nextRefresh(for: soon, now: now), now.addingTimeInterval(1800))

        let far = TeamGameFinder.Result(game: game("a", home: "HT", away: "LG", status: .scheduled, startOffset: 86_400), isToday: false)
        XCTAssertEqual(TeamGameFinder.nextRefresh(for: far, now: now), now.addingTimeInterval(3 * 3600))

        XCTAssertEqual(TeamGameFinder.nextRefresh(for: nil, now: now), now.addingTimeInterval(3 * 3600))
    }
}

private struct DayProvider: GameDataProvider {
    let calendar: Calendar
    let today: Date
    let gamesByDay: [Int: [GameSummary]]

    func games(on date: Date) async throws -> [GameSummary] {
        let ahead = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: date)).day ?? 0
        return gamesByDay[ahead] ?? []
    }

    func relay(gameId: String, inning: Int?) async throws -> RelaySnapshot {
        throw GameDataError.emptyResponse
    }
}
