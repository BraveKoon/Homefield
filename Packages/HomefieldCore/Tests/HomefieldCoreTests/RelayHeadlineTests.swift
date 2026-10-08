import XCTest
@testable import HomefieldCore

final class RelayHeadlineTests: XCTestCase {
    private let headline = RelayHeadline()

    func testBatterResults() {
        XCTAssertEqual(headline.headline(for: "구자욱 : 좌익수 희생플라이 아웃"), "구자욱 희생플라이 (좌익수)")
        XCTAssertEqual(headline.headline(for: "김영웅 : 우익수 뒤 홈런"), "김영웅 홈런 (우익수)")
        XCTAssertEqual(headline.headline(for: "박정우 : 헛스윙 삼진 아웃"), "박정우 삼진")
        XCTAssertEqual(headline.headline(for: "강민호 : 볼넷"), "강민호 볼넷")
        XCTAssertEqual(headline.headline(for: "김영웅 : 유격수 실책으로 출루"), "김영웅 유격수 실책으로 출루")
    }

    func testRunners() {
        XCTAssertEqual(headline.headline(for: "1루주자 김지찬 : 도루로 2루까지 진루"), "김지찬 도루(1루 → 2루)")
        XCTAssertEqual(headline.headline(for: "2루주자 김지찬 : 도루실패 아웃"), "김지찬 도루 실패")
        XCTAssertEqual(headline.headline(for: "3루주자 김지찬 : 홈인"), "김지찬 홈인")
        XCTAssertEqual(headline.headline(for: "1루주자 구자욱 : 3루까지 진루"), "구자욱 진루(1루 → 3루)")
        XCTAssertEqual(headline.headline(for: "1루주자 구자욱 : 포스아웃"), "구자욱 아웃 (1루)")
    }

    func testIntroPitchAndChange() {
        XCTAssertEqual(headline.headline(for: "3번타자 구자욱"), "3번타자 구자욱 타석")
        XCTAssertNil(headline.headline(for: "1구 볼"))
        XCTAssertNil(headline.headline(for: "3구 헛스윙"))
        XCTAssertEqual(headline.headline(for: "투수 원태인 : 투수 김재윤 (으)로 교체"), "투수 원태인 → 투수 김재윤 (으)로 교체")
        XCTAssertNil(headline.headline(for: "   "))
    }

    func testSeparatorLines() {
        XCTAssertNil(headline.headline(for: "=================================="))
        XCTAssertNil(headline.headline(for: " ------ "))
    }
}
