import XCTest
@testable import HomefieldCore

final class DemoLeagueTests: XCTestCase {
    /// 실제 구단 코드와 겹치지 않는다
    func testTeamsAreNotRealClubs() {
        XCTAssertEqual(DemoLeague.teams.count, 2)
        for team in DemoLeague.teams {
            XCTAssertNil(KBOTeams.name(for: team.code), "\(team.code) 는 실제 구단 코드")
            XCTAssertFalse(KBOTeams.all.contains { $0.name == team.name })
        }
    }

    func testPlayersBelongToDemoTeams() {
        let players = DemoLeague.players()
        XCTAssertEqual(players.count, 28)
        XCTAssertEqual(Set(players.map(\.id)).count, players.count)
        XCTAssertTrue(players.allSatisfy { DemoLeague.contains($0.teamCode) })
    }

    /// 경기 중계에 나오는 선수는 모두 가상 선수 목록에 있다 (카드로도 뽑을 수 있다)
    func testRelayPlayersAreInLeague() async throws {
        let ids = Set(DemoLeague.players().map(\.id))
        let relay = try await DemoGameProvider().relay(gameId: DemoGameProvider.gameId, inning: nil)
        for side in [TeamSide.home, .away] {
            for player in (relay.lineups[side] ?? []) + (relay.pitchers[side] ?? []) {
                XCTAssertTrue(ids.contains(player.id), "\(player.id) 가 가상 리그에 없음")
            }
        }
    }

    /// 카드 등급이 1성부터 5성까지 모두 나온다
    func testCardPoolCoversEveryGrade() {
        let pool = DemoLeague.cardPool()
        XCTAssertEqual(pool.cards.count, 28)
        for grade in CardGrade.allCases {
            XCTAssertFalse(pool.cards(grade: grade).isEmpty, "\(grade.displayName) 카드가 없음")
        }
        XCTAssertTrue(pool.cards.allSatisfy { $0.stats != nil })
    }

    func testRostersCoverBothTeams() {
        let rosters = DemoLeague.rosters()
        XCTAssertEqual(Set(rosters.keys), Set(DemoLeague.teams.map(\.code)))
        XCTAssertTrue(rosters.values.allSatisfy { $0.players.count == 14 })
    }

    /// 위젯용: 1회말 끝 (홈 3 - 원정 0) 모습으로 시작한다
    func testMidGameProvider() async throws {
        let provider = DemoGameProvider(revealed: DemoGameProvider.midGameRevealed)
        let game = try XCTUnwrap(try await provider.games(on: Date()).first)
        XCTAssertEqual(game.status, .live)
        XCTAssertEqual(game.statusText, "1회말")
        XCTAssertEqual(game.homeScore, 3)
        XCTAssertEqual(game.awayScore, 0)
    }
}
