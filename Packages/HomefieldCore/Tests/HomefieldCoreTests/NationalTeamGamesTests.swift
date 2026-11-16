import XCTest
@testable import HomefieldCore

final class NationalTeamGamesTests: XCTestCase {
    /// 2026-11-17 네이버 일정 응답(2026-11-12, 분류 지정 없음) 그대로:
    /// APBC 한국 대 호주, 팀이 없는 방송, APBC 일본 대 대만
    private let apbcDay = """
    {"code":200,"success":true,"result":{"games":[
      {"gameId":"88881112AUKR02026","categoryId":"apbc","gameDate":"2026-11-12","gameDateTime":"2026-11-12T12:00:00",
       "homeTeamCode":"KR","homeTeamName":"대한민국","homeTeamScore":7,"awayTeamCode":"AU","awayTeamName":"호주","awayTeamScore":8,
       "winner":"AWAY","statusCode":"RESULT","statusInfo":"9회말","cancel":false,"suspended":false,"reversedHomeAway":true,
       "neutralGround":false,"homeTeamEmblemUrl":"https://sports-phinf.pstatic.net/team/apbc/default/KR.png",
       "awayTeamEmblemUrl":"https://sports-phinf.pstatic.net/team/apbc/default/AU.png","widgetEnable":false},
      {"gameId":"20261109KBO1","categoryId":"kbaseballetc","gameDate":"2026-11-12","gameDateTime":"2026-11-12T17:00:00",
       "homeTeamCode":"","homeTeamName":"","homeTeamScore":0,"awayTeamCode":"","awayTeamName":"","awayTeamScore":0,
       "winner":"DRAW","statusCode":"RESULT","statusInfo":"","cancel":false,"suspended":false,"reversedHomeAway":true,
       "neutralGround":false,"homeTeamEmblemUrl":null,"awayTeamEmblemUrl":null,"widgetEnable":false},
      {"gameId":"88881112JPTW02026","categoryId":"apbc","gameDate":"2026-11-12","gameDateTime":"2026-11-12T19:00:00",
       "homeTeamCode":"TW","homeTeamName":"차이니스 타이베이","homeTeamScore":0,"awayTeamCode":"JP","awayTeamName":"일본","awayTeamScore":5,
       "winner":"AWAY","statusCode":"RESULT","statusInfo":"9회말","cancel":false,"suspended":false,"reversedHomeAway":true,
       "neutralGround":false,"homeTeamEmblemUrl":"https://sports-phinf.pstatic.net/team/apbc/default/TW.png",
       "awayTeamEmblemUrl":"https://sports-phinf.pstatic.net/team/apbc/default/JP.png","widgetEnable":false}
    ],"gameTotalCount":3}}
    """

    private let kboGameJSON = """
    {"code":200,"success":true,"result":{"games":[
      {"gameId":"20261112LGSS02026","categoryId":"kbo","gameDateTime":"2026-11-12T18:30:00","stadium":"대구",
       "homeTeamCode":"SS","homeTeamName":"삼성","awayTeamCode":"LG","awayTeamName":"LG",
       "homeTeamScore":"3","awayTeamScore":2,"statusCode":"STARTED","statusInfo":"5회말","cancel":false}
    ]}}
    """

    // MARK: 응답에서 고르기

    /// 한국 경기만 남는다: 팀이 없는 방송과 다른 나라끼리의 경기는 빠진다
    func testKeepsOnlyKoreaGames() throws {
        let games = try NaverMapping.parseKoreaNationalTeamGames(Data(apbcDay.utf8))
        XCTAssertEqual(games.map(\.id), ["88881112AUKR02026"])

        let game = try XCTUnwrap(games.first)
        XCTAssertEqual(game.home, Team(code: "KR", name: "대한민국"))
        XCTAssertEqual(game.away, Team(code: "AU", name: "호주"))
        XCTAssertEqual(game.homeScore, 7)
        XCTAssertEqual(game.awayScore, 8)
        XCTAssertEqual(game.status, .finished)
        XCTAssertEqual(game.statusText, "9회말")
        XCTAssertNotNil(game.startTime)
        XCTAssertEqual(game.competition, "apbc")
        XCTAssertEqual(game.competitionName, "APBC")
    }

    /// KBO 경기는 따로 받으므로 여기서는 나오지 않고, 기존 방식으로 읽은 KBO 경기에는 대회 표시가 없다
    func testKboGamesHaveNoCompetition() throws {
        XCTAssertTrue(try NaverMapping.parseKoreaNationalTeamGames(Data(kboGameJSON.utf8)).isEmpty)
        let kbo = try XCTUnwrap(NaverMapping.parseGames(Data(kboGameJSON.utf8)).first)
        XCTAssertNil(kbo.competition)
        XCTAssertNil(kbo.competitionName)
    }

    /// 코드가 달라도 이름이 "대한민국"이면 한국 경기로 본다 (대회마다 코드가 다를 수 있다)
    func testMatchesKoreaByName() throws {
        let json = """
        {"result":{"games":[
          {"gameId":"88880315KORJP02026","categoryId":"wbc","gameDateTime":"2026-03-15T19:00:00",
           "homeTeamCode":"KOR","homeTeamName":"대한민국","awayTeamCode":"JPN","awayTeamName":"일본","statusCode":"BEFORE"}
        ]}}
        """
        let game = try XCTUnwrap(NaverMapping.parseKoreaNationalTeamGames(Data(json.utf8)).first)
        XCTAssertEqual(game.status, .scheduled)
        XCTAssertEqual(game.competitionName, "WBC")
    }

    // MARK: 일정에 합치기

    private func makeProvider(includeNationalTeam: Bool, nationalStatus: Int = 200) -> (NaverSportsProvider, RequestLog) {
        let log = RequestLog()
        StubURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            log.queries.append(query)
            if query.contains("categoryId=kbo") { return (200, self.kboGameJSON) }
            return (nationalStatus, nationalStatus == 200 ? self.apbcDay : "{}")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let provider = NaverSportsProvider(
            session: URLSession(configuration: configuration),
            includeNationalTeam: includeNationalTeam
        )
        return (provider, log)
    }

    /// KBO 경기와 한국 경기가 시작 시각 순으로 섞인다
    func testGamesMergeKboAndNationalTeamByStartTime() async throws {
        let (provider, _) = makeProvider(includeNationalTeam: true)
        let games = try await provider.games(on: Date())
        XCTAssertEqual(games.map(\.id), ["88881112AUKR02026", "20261112LGSS02026"])
        XCTAssertEqual(games.map(\.competition), ["apbc", nil])
    }

    /// 켜지 않으면 일정을 한 번 더 부르지 않는다
    func testNationalTeamIsOffByDefault() async throws {
        let (provider, log) = makeProvider(includeNationalTeam: false)
        let games = try await provider.games(on: Date())
        XCTAssertEqual(games.map(\.id), ["20261112LGSS02026"])
        XCTAssertTrue(log.queries.allSatisfy { $0.contains("categoryId=kbo") })
    }

    /// 국가대표 경기를 못 받아도 KBO 일정은 그대로 보인다
    func testNationalTeamFailureKeepsKboGames() async throws {
        let (provider, _) = makeProvider(includeNationalTeam: true, nationalStatus: 500)
        let games = try await provider.games(on: Date())
        XCTAssertEqual(games.map(\.id), ["20261112LGSS02026"])
    }
}

/// 요청을 모아 두는 상자
final class RequestLog: @unchecked Sendable {
    var queries: [String] = []
}

/// 네트워크 없이 응답을 돌려주는 가짜
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (404, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
