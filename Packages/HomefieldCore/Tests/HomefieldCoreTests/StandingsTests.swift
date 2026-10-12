import XCTest
@testable import HomefieldCore

final class StandingsTests: XCTestCase {
    /// 2026-10-12 실제 응답(statistics/categories/kbo/seasons/2026/teams)에서 필요한 필드만
    func testParseStandings() throws {
        let json = """
        {"code":200,"success":true,"result":{
          "gameType":"REGULAR_SEASON",
          "postSeason":{"pcImageUrl":null,"teamColors":[]},
          "seasonTeamStats":[
            {"teamId":"LG","teamName":"LG","gameType":"REGULAR_SEASON","ranking":2,"gameCount":144,
             "winGameCount":85,"drawnGameCount":3,"loseGameCount":56,"wra":0.603,"gameBehind":5.5,
             "continuousGameResult":"1패","lastFiveGames":"WLWWL"},
            {"teamId":"KT","teamName":"KT","teamShortName":"KT","gameType":"REGULAR_SEASON","ranking":1,"wcRanking":null,
             "gameCount":144,"winGameCount":90,"drawnGameCount":5,"loseGameCount":49,"wra":0.647,"gameBehind":0.0,
             "continuousGameResult":"10승","lastFiveGames":"WWWWW","offenseHra":0.28552}
          ]
        }}
        """
        let standings = try NaverMapping.parseStandings(Data(json.utf8))
        XCTAssertEqual(standings.map(\.teamCode), ["KT", "LG"])
        let kt = standings[0]
        XCTAssertEqual(kt.rank, 1)
        XCTAssertEqual(kt.wins, 90)
        XCTAssertEqual(kt.losses, 49)
        XCTAssertEqual(kt.draws, 5)
        XCTAssertEqual(kt.winRateText, ".647")
        XCTAssertEqual(kt.gamesBehindText, "-")
        XCTAssertEqual(kt.streak, "10승")
        XCTAssertEqual(kt.lastFive, "WWWWW")
        XCTAssertEqual(standings[1].gamesBehindText, "5.5")
    }

    func testEmptyOrUnknownShape() throws {
        XCTAssertTrue(try NaverMapping.parseStandings(Data(#"{"code":200,"result":{"gameType":"REGULAR_SEASON"}}"#.utf8)).isEmpty)
        XCTAssertTrue(try NaverMapping.parseStandings(Data(#"{"code":200,"result":null}"#.utf8)).isEmpty)
    }

    func testGamesBehindWholeNumber() {
        let standing = TeamStanding(teamCode: "SS", teamName: "삼성", rank: 3, games: 144, wins: 80, losses: 60, draws: 4, winRate: 0.571, gamesBehind: 10)
        XCTAssertEqual(standing.gamesBehindText, "10")
    }
}
