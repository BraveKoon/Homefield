import XCTest
@testable import HomefieldCore

final class PitchCountTests: XCTestCase {
    func testReadsPitchNumber() {
        XCTAssertEqual(PitchCount.number(in: "10구 볼"), 10)
        XCTAssertEqual(PitchCount.number(in: "3구 헛스윙"), 3)
        XCTAssertEqual(PitchCount.number(in: "1 구 스트라이크"), 1)
        XCTAssertEqual(PitchCount.number(in: "  7구 파울"), 7)
    }

    func testIgnoresOtherLines() {
        XCTAssertNil(PitchCount.number(in: "박성한 : 좌익수 앞 2루타"))
        XCTAssertNil(PitchCount.number(in: "9번타자 구본혁"))
        XCTAssertNil(PitchCount.number(in: "승리투수: 올러"))
        XCTAssertNil(PitchCount.number(in: ""))
    }

    func testCurrentAtBat() {
        // 최신이 앞: 지금 타석 3구째
        let lines: [(text: String, isBatterIntro: Bool)] = [
            ("3구 볼", false),
            ("2구 파울", false),
            ("1구 스트라이크", false),
            ("9번타자 구본혁", true),
            ("7구 헛스윙", false),
        ]
        XCTAssertEqual(PitchCount.current(in: lines), 3)
    }

    func testNewBatterHasNoPitchesYet() {
        // 방금 타자가 나왔으면 아직 던진 공이 없다 (앞 타자의 투구를 세지 않는다)
        let lines: [(text: String, isBatterIntro: Bool)] = [
            ("9번타자 구본혁", true),
            ("7구 헛스윙", false),
        ]
        XCTAssertNil(PitchCount.current(in: lines))
        XCTAssertNil(PitchCount.current(in: []))
    }

    func testResultLineAboveStillCountsPitches() {
        // 타석 결과 줄이 맨 위여도 그 아래 마지막 투구를 센다
        let lines: [(text: String, isBatterIntro: Bool)] = [
            ("구본혁 : 삼진 아웃", false),
            ("7구 헛스윙", false),
            ("9번타자 구본혁", true),
        ]
        XCTAssertEqual(PitchCount.current(in: lines), 7)
    }
}
