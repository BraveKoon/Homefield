import XCTest
@testable import HomefieldCore

final class RosterTests: XCTestCase {
    private let game = GameSummary(
        id: "20260930KTHT02026",
        home: Team(code: "HT", name: "KIA"),
        away: Team(code: "KT", name: "KT"),
        status: .finished
    )

    /// 2026-09-30 실제 응답 형태 (homeEntry 는 이름·코드·글자 포지션만 있다)
    private let relayJSON = """
    {"code":200,"success":true,"result":{"textRelayData":{
      "textRelays":[],
      "homeLineup":{
        "batter":[{"posName":"우익수","batOrder":1,"backnum":"1","pos":9,"name":"박정우","pcode":"67609"}],
        "pitcher":[{"seqno":1,"backnum":"10","name":"김태형","pcode":"55610"}]
      },
      "homeEntry":{"batter":[
        {"hittype":"우투우타","pos":"유격수","pitchingStyle":null,"name":"박민","pcode":"50657"},
        {"hittype":"우투좌타","pos":"포수","name":"한준수","pcode":"50001"},
        {"pos":"우익수","name":"박정우","pcode":"67609"}
      ],"pitcher":[{"name":"정해영","pcode":"50002"}]},
      "awayLineup":{"batter":[{"posName":"우익수","batOrder":1,"backnum":"3","name":"최원준","pcode":"66606"}]}
    }}}
    """

    func testRosterFromRelayEntries() throws {
        let snapshot = try NaverMapping.parseRelay(Data(relayJSON.utf8), game: game)
        XCTAssertEqual(snapshot.benches[.home]?.map(\.name), ["정해영", "박민", "한준수", "박정우"])

        let rosters = TeamRoster.rosters(from: snapshot)
        // 원정은 엔트리가 없어 1군 전체로 볼 수 없다
        XCTAssertEqual(rosters.map(\.teamCode), ["HT"])
        let kia = try XCTUnwrap(rosters.first)
        XCTAssertEqual(Set(kia.players.map(\.name)), ["박정우", "김태형", "박민", "한준수", "정해영"])
        XCTAssertEqual(kia.players.filter { $0.name == "박정우" }.count, 1)
        XCTAssertEqual(kia.players.first { $0.name == "박정우" }?.backNumber, "1")
        XCTAssertTrue(kia.contains(name: "정해영"))

        let groups = kia.grouped
        XCTAssertEqual(groups.map(\.group), [.pitcher, .catcher, .infielder, .outfielder])
        XCTAssertEqual(groups.first?.players.map(\.name), ["김태형", "정해영"])
    }

    func testPositionGroups() {
        XCTAssertEqual(TeamRoster.Group(position: "선발투수"), .pitcher)
        XCTAssertEqual(TeamRoster.Group(position: "포수"), .catcher)
        XCTAssertEqual(TeamRoster.Group(position: "1루수"), .infielder)
        XCTAssertEqual(TeamRoster.Group(position: "유격수"), .infielder)
        XCTAssertEqual(TeamRoster.Group(position: "중견수"), .outfielder)
        XCTAssertEqual(TeamRoster.Group(position: "지명타자"), .other)
        XCTAssertEqual(TeamRoster.Group(position: nil), .other)
    }

    func testCollectorUsesMostRecentGamePerTeam() async throws {
        let snapshot = try NaverMapping.parseRelay(Data(relayJSON.utf8), game: game)
        let provider = FakeProvider(gamesByDay: [1: [game]], snapshot: snapshot)
        let rosters = await RosterCollector(provider: provider, lookbackDays: 3, teamCodes: ["HT", "KT"])
            .collect(today: provider.today, calendar: provider.calendar)
        XCTAssertEqual(rosters["HT"]?.players.count, 5)
        XCTAssertEqual(rosters["HT"]?.gameId, game.id)
        XCTAssertNil(rosters["KT"])
    }

    /// 2026-10-05 실제 응답 (statistics/categories/kbo/seasons/2026/players?playerType=HITTER&teamCode=LG)
    func testTeamSeasonStats() throws {
        let hitters = """
        {"code":200,"success":true,"result":{"page":1,"pageSize":50,"seasonPlayerStats":[
          {"playerId":"53123","playerName":"오스틴","backNumber":23,"teamId":"LG","hitterHra":0.3384321223709369,
           "hitterRbi":124,"hitterRun":111,"hitterHr":40,"hitterHit":177,"hitterGameCount":139,"hitterAb":523,
           "hitterBb":79,"hitterKk":92,"hitterObp":0.434,"hitterCs":null}
        ]}}
        """
        let batter = try XCTUnwrap(NaverMapping.parseTeamSeasonStats(Data(hitters.utf8), kind: .batter).first)
        XCTAssertEqual(batter.playerId, "53123")
        XCTAssertEqual(batter.homeRuns, 40)
        XCTAssertEqual(batter.games, 139)
        XCTAssertEqual(batter.displayItems.first?.value, ".338")

        let pitchers = """
        {"result":{"seasonPlayerStats":[
          {"playerId":"61101","playerName":"임찬규","backNumber":1,"pitcherEra":4.295454545454545,"pitcherWin":14,
           "pitcherLose":7,"pitcherSave":0,"pitcherGameCount":29,"pitcherInning":"161 1/3","pitcherKk":96,"pitcherBb":40}
        ]}}
        """
        let pitcher = try XCTUnwrap(NaverMapping.parseTeamSeasonStats(Data(pitchers.utf8), kind: .pitcher).first)
        XCTAssertEqual(pitcher.wins, 14)
        XCTAssertEqual(pitcher.innings, "161 1/3")
        XCTAssertEqual(pitcher.displayItems.first?.value, "4.30")
    }
}

private struct FakeProvider: GameDataProvider {
    let gamesByDay: [Int: [GameSummary]]
    let snapshot: RelaySnapshot
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSince1970: 1_790_000_000)

    func games(on date: Date) async throws -> [GameSummary] {
        let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: today)).day ?? 0
        return gamesByDay[back] ?? []
    }

    func relay(gameId: String, inning: Int?) async throws -> RelaySnapshot {
        snapshot
    }
}
