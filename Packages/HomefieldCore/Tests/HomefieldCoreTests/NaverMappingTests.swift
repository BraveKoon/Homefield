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

    /// 2026-09-30 KT vs KIA 실제 응답에서 필요한 부분만 줄인 것 (Naver API check 워크플로 로그)
    func testRealRelayResponseShape() throws {
        let json = """
        {"code":200,"success":true,"result":{"textRelayData":{
          "category":"kbo","gameId":"20260930KTHT02026","no":75,"inn":7,"homeOrAway":"1",
          "textRelays":[
            {"title":"1번타자 박정우","titleStyle":"8","no":75,"inn":7,"homeOrAway":"1","statusCode":0,"ptsOptions":[],
             "textOptions":[
               {"currentGameState":{"homeScore":"2","awayScore":"2","pitcher":"56011","batter":"67609",
                                    "strike":"0","ball":"0","out":"2","base1":"0","base2":"0","base3":"0"},
                "seqno":419,"text":"1번타자 박정우","type":8,
                "currentPlayersInfo":{"away":{"playerType":"pitcher"},"home":{"playerType":"batter"}}},
               {"currentGameState":{"strike":"1","ball":"0","out":"2","base1":"0","base2":"67609","base3":"0"},
                "seqno":420,"text":"1구 스트라이크","type":1}
             ]}
          ],
          "homeLineup":{
            "batter":[{"posName":"우익수","seqno":1,"batOrder":1,"backnum":"1","pos":9,"name":"박정우","pcode":"67609"}],
            "pitcher":[{"seqno":1,"backnum":"10","name":"김태형","pcode":"55610","inn":"5.0"}]
          },
          "awayLineup":{
            "batter":[{"posName":"우익수","seqno":1,"batOrder":1,"backnum":"3","pos":9,"name":"최원준","pcode":"66606"}],
            "pitcher":[{"seqno":1,"backnum":"36","name":"대니엘","pcode":"56002"},
                       {"seqno":2,"backnum":"99","name":"구원투수","pcode":"56011"}]
          },
          "currentGameState":{"strike":"0","ball":"0","out":"2","base1":"0","base2":"0","base3":"0"}
        }}}
        """
        let game = GameSummary(id: "20260930KTHT02026", home: Team(code: "HT", name: "KIA"), away: Team(code: "KT", name: "KT"), status: .live)
        let snapshot = try NaverMapping.parseRelay(Data(json.utf8), game: game)

        XCTAssertEqual(snapshot.currentInning, 7)
        XCTAssertEqual(snapshot.entries.map(\.text), ["1번타자 박정우", "1구 스트라이크"])
        XCTAssertEqual(snapshot.entries.first?.battingSide, .home)
        XCTAssertEqual(snapshot.entries[0].state, CountState(balls: 0, strikes: 0, outs: 2, basesOccupied: [false, false, false], pitcherId: "56011"))
        XCTAssertEqual(snapshot.entries[1].state?.basesOccupied, [false, true, false])
        XCTAssertEqual(snapshot.lineups[.home]?.first?.position, "우익수")
        XCTAssertEqual(snapshot.lineups[.home]?.first?.teamCode, "HT")
        XCTAssertEqual(snapshot.pitchers[.home]?.first?.name, "김태형")
        XCTAssertEqual(snapshot.pitchers[.away]?.first?.id, "56002")

        let tracker = GameStateTracker()
        tracker.setLineups(snapshot.lineups, pitchers: snapshot.pitchers)
        tracker.apply(snapshot.entries)
        XCTAssertEqual(tracker.state.halfInningTitle, "7회말")
        XCTAssertEqual(tracker.state.outs, 2)
        XCTAssertEqual(tracker.state.strikes, 1)
        // 선발은 대니엘이지만 currentGameState 의 투수 코드(56011)가 지금 투수다
        XCTAssertEqual(tracker.state.pitcherName, "구원투수")
        XCTAssertEqual(snapshot.entries[0].state?.pitcherId, "56011")
    }

    /// 2026-09-30 실제 응답의 currentPlayersInfo (월간·통산 등 다른 묶음은 생략)
    func testSeasonStatsFromCurrentPlayersInfo() throws {
        let json = """
        {"code":200,"success":true,"result":{"textRelayData":{
          "textRelays":[{"no":75,"inn":7,"homeOrAway":"1","textOptions":[
            {"seqno":419,"text":"1번타자 박정우","type":8,
             "currentGameState":{"pitcher":"56011","batter":"67609","strike":"0","ball":"0","out":"2"},
             "currentPlayersInfo":{
               "away":{"playerType":"pitcher",
                 "monthlyStats":{"gameCount":11,"era":12.27,"inn":"7.1"},
                 "currentSeasonStats":{"bb":26,"kk":67,"gameCount":70,"s":0,"era":6.04,"w":1,"inn":"69.1","inn2":"69 1/3",
                                       "l":2,"er":47,"ab":0,"hit":0,"hra":0.0,"rbi":0,"hr":0,"whip":0.0,"obp":0.0}},
               "home":{"playerType":"batter",
                 "currentSeasonStats":{"bb":0,"kk":0,"gameCount":0,"s":0,"era":0.0,"w":0,"inn":null,"inn2":null,
                                       "l":0,"er":0,"ab":100,"hit":30,"hra":0.3,"rbi":15,"hr":0,"whip":0.0,"obp":0.421}}}},
            {"seqno":420,"text":"1구 스트라이크","type":1}
          ]}]
        }}}
        """
        let snapshot = try NaverMapping.parseRelay(Data(json.utf8), game: nil)
        let stats = snapshot.entries[0].seasonStats
        XCTAssertEqual(stats.count, 2)
        XCTAssertTrue(snapshot.entries[1].seasonStats.isEmpty)

        let pitcher = try XCTUnwrap(stats.first { $0.kind == .pitcher })
        XCTAssertEqual(pitcher.playerId, "56011")
        XCTAssertEqual(pitcher.era, 6.04)
        XCTAssertEqual(pitcher.games, 70)
        XCTAssertEqual(pitcher.wins, 1)
        XCTAssertEqual(pitcher.losses, 2)
        XCTAssertEqual(pitcher.innings, "69 1/3")
        XCTAssertEqual(pitcher.strikeouts, 67)

        let batter = try XCTUnwrap(stats.first { $0.kind == .batter })
        XCTAssertEqual(batter.playerId, "67609")
        XCTAssertEqual(batter.atBats, 100)
        XCTAssertEqual(batter.hits, 30)
        XCTAssertEqual(batter.rbi, 15)
        XCTAssertEqual(batter.displayItems.first?.value, ".300")
        XCTAssertEqual(batter.displayItems.last?.value, ".421")
        XCTAssertTrue(batter.sameNumbers(as: { var copy = batter; copy.updatedAt = .distantPast; return copy }()))
    }

    /// 2026-10-05 KIA vs LG 실제 경기 요약에서 이닝별 점수 부분
    func testLineScore() throws {
        let json = """
        {"code":200,"success":true,"result":{"games":[
          {"gameId":"20261005HTLG02026","homeTeamCode":"LG","awayTeamCode":"HT","homeTeamScore":4,"awayTeamScore":6,
           "statusCode":"RESULT","currentInning":"9회말",
           "homeTeamScoreByInning":["4","0","0","0","0","0","0","0","0"],
           "awayTeamScoreByInning":["0","0","0","2","0","1","0","0","3"],
           "homeTeamRheb":[4,7,1,4],"awayTeamRheb":[6,10,0,3]}
        ]}}
        """
        let game = try XCTUnwrap(NaverMapping.parseGames(Data(json.utf8)).first)
        let score = try XCTUnwrap(game.lineScore)
        XCTAssertEqual(score.inningCount, 9)
        XCTAssertEqual(score.away.innings, [0, 0, 0, 2, 0, 1, 0, 0, 3])
        XCTAssertEqual(score.home.innings.first, 4)
        XCTAssertEqual(score.away.runs, 6)
        XCTAssertEqual(score.away.hits, 10)
        XCTAssertEqual(score.home.errors, 1)
        XCTAssertEqual(score.home.walks, 4)
    }

    func testLineScoreInProgressAndMissing() throws {
        let json = """
        {"result":{"games":[
          {"gameId":"a","homeTeamScoreByInning":["1","-",""],"awayTeamScoreByInning":["0","2"]},
          {"gameId":"b"}
        ]}}
        """
        let games = try NaverMapping.parseGames(Data(json.utf8))
        XCTAssertEqual(games[0].lineScore?.home.innings, [1, nil, nil])
        XCTAssertEqual(games[0].lineScore?.inningCount, 9)
        XCTAssertNil(games[0].lineScore?.away.runs)
        XCTAssertNil(games[1].lineScore)
    }

    func testEndedStatus() {
        XCTAssertEqual(NaverMapping.status(code: "ENDED", cancelled: false), .finished)
        XCTAssertEqual(NaverMapping.status(code: "STARTED", cancelled: false), .live)
    }
}
