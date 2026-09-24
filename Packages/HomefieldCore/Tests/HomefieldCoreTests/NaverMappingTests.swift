import XCTest
@testable import HomefieldCore

final class NaverMappingTests: XCTestCase {
    func testParseGames() throws {
        let json = """
        {"code":200,"success":true,"result":{"games":[
          {"gameId":"20260924LGSS02026","gameDateTime":"2026-09-24T18:30:00","stadium":"대구",
           "homeTeamCode":"SS","homeTeamName":"삼성","awayTeamCode":"LG","awayTeamName":"LG",
           "homeTeamScore":"3","awayTeamScore":2,"statusCode":"STARTED","statusInfo":"5회말","cancel":false}
        ]}}
        """
        let games = try NaverMapping.parseGames(Data(json.utf8))
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games[0].id, "20260924LGSS02026")
        XCTAssertEqual(games[0].home.code, "SS")
        XCTAssertEqual(games[0].homeScore, 3)
        XCTAssertEqual(games[0].awayScore, 2)
        XCTAssertEqual(games[0].status, .live)
        XCTAssertNotNil(games[0].startTime)
    }

    func testParseRelay() throws {
        let json = """
        {"code":200,"success":true,"result":{"textRelayData":{
          "textRelays":[
            {"no":12,"inn":5,"homeOrAway":"1","title":"구자욱","textOptions":[
              {"seqno":301,"type":8,"text":"3번타자 구자욱","batterRecord":{"pcode":"62234","name":"구자욱"}},
              {"seqno":302,"type":1,"text":"1구 볼"},
              {"seqno":303,"type":13,"text":"구자욱 : 좌익수 플라이 아웃"}
            ]}
          ],
          "homeLineup":{"batter":[{"pcode":"62234","name":"구자욱","batOrder":3,"backnum":"5","posName":"좌익수"}]},
          "awayLineup":{"batter":[]}
        }}}
        """
        let game = GameSummary(id: "g", home: Team(code: "SS", name: "삼성"), away: Team(code: "LG", name: "LG"), status: .live)
        let snapshot = try NaverMapping.parseRelay(Data(json.utf8), game: game)

        XCTAssertEqual(snapshot.currentInning, 5)
        XCTAssertEqual(snapshot.entries.map(\.text), ["3번타자 구자욱", "1구 볼", "구자욱 : 좌익수 플라이 아웃"])
        XCTAssertEqual(snapshot.entries.first?.battingSide, .home)
        XCTAssertEqual(snapshot.entries.first?.batterId, "62234")
        XCTAssertEqual(snapshot.lineups[.home]?.first?.teamCode, "SS")
        XCTAssertEqual(snapshot.lineups[.home]?.first?.backNumber, "5")
    }

    func testMissingFieldsDoNotThrow() throws {
        let snapshot = try NaverMapping.parseRelay(Data(#"{"code":200,"result":{}}"#.utf8), game: nil)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }
}
