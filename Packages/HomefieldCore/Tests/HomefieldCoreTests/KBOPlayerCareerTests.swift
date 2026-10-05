import XCTest
@testable import HomefieldCore

final class KBOPlayerCareerTests: XCTestCase {
    /// KBO 선수 기록 페이지(Total.aspx) 구조를 줄인 것. 2026-10-05 로그: 머리글 ['연도', '팀명', 'AVG', ...], 경력 "가동초-청원중-휘문고-LG-경찰"
    private let html = """
    <div class="player_info">
      <span id="cphContents_cphContents_cphContents_playerProfile_lblName">임찬규</span>
      <span id="cphContents_cphContents_cphContents_playerProfile_lblCareer">가동초-청원중-휘문고-LG-경찰</span>
    </div>
    <table class="tbl tt"><thead><tr><th>팀명</th><th>ERA</th></tr></thead><tbody><tr><td>LG</td><td>4.30</td></tr></tbody></table>
    <table class="tbl tt mb5">
      <thead><tr><th>연도</th><th>팀명</th><th>ERA</th><th>G</th></tr></thead>
      <tbody>
        <tr><td>2011</td><td>LG</td><td>4.46</td><td>65</td></tr>
        <tr><td>2012</td><td>LG</td><td>5.02</td><td>10</td></tr>
        <tr><td>2016</td><td>LG</td><td>4.69</td><td>21</td></tr>
        <tr class="sum"><td>통산</td><td></td><td>4.60</td><td>300</td></tr>
      </tbody>
    </table>
    """

    func testParsePage() {
        let career = KBOPlayerPageParser.parse(html: html, playerId: "61101")
        XCTAssertEqual(career.name, "임찬규")
        XCTAssertEqual(career.career, "가동초-청원중-휘문고-LG-경찰")
        XCTAssertEqual(career.seasons.map(\.year), [2011, 2012, 2016])
        XCTAssertEqual(career.teamHistory.map(\.period), ["2011–2016"])
        XCTAssertEqual(career.teamHistory.map(\.text), ["LG 트윈스"])
    }

    func testTeamHistoryKeepsOldClubNames() {
        let career = KBOPlayerCareer(playerId: "1", seasons: [
            .init(year: 2014, team: "SK"),
            .init(year: 2015, team: "SK"),
            .init(year: 2016, team: "넥센"),
            .init(year: 2021, team: "SSG"),
            .init(year: 2022, team: "KIA"),
            .init(year: 2023, team: "KIA"),
        ])
        XCTAssertEqual(career.teamHistory.map(\.period), ["2014–2015", "2016", "2021", "2022–2023"])
        XCTAssertEqual(career.teamHistory.map(\.text), ["SK", "넥센", "SSG 랜더스", "KIA 타이거즈"])
    }

    func testPageWithoutRecords() {
        let career = KBOPlayerPageParser.parse(html: "<html><table><tr><th>팀명</th></tr></table></html>", playerId: "1")
        XCTAssertNil(career.name)
        XCTAssertTrue(career.seasons.isEmpty)
        XCTAssertTrue(career.teamHistory.isEmpty)
    }
}
