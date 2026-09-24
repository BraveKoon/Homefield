import XCTest
@testable import HomefieldCore

final class RelayTextClassifierTests: XCTestCase {
    let classifier = RelayTextClassifier()

    func testBatterIntro() {
        XCTAssertEqual(classifier.batterIntro(in: "3번타자 구자욱"), .init(order: 3, name: "구자욱"))
        XCTAssertEqual(classifier.batterIntro(in: " 9번 타자 김지찬 "), .init(order: 9, name: "김지찬"))
        XCTAssertNil(classifier.batterIntro(in: "구자욱 : 좌익수 플라이 아웃"))
        XCTAssertNil(classifier.batterIntro(in: "3구 볼"))
    }

    func testSubject() {
        XCTAssertEqual(classifier.subject(of: "1루주자 김지찬 : 도루로 2루까지 진루"), "김지찬")
        XCTAssertEqual(classifier.subject(of: "구자욱 : 중견수 뒤 홈런"), "구자욱")
        XCTAssertNil(classifier.subject(of: "2구 스트라이크"))
    }

    func testRequestedSituations() {
        XCTAssertEqual(classifier.classify("구자욱 : 좌익수 플라이 아웃"), [.flyOut])
        XCTAssertEqual(classifier.classify("1루주자 김지찬 : 도루로 2루까지 진루"), [.stolenBase])
        XCTAssertEqual(classifier.classify("구자욱 : 좌중간 담장 넘어가는 홈런 (비거리: 125m)"), [.homeRun])
        XCTAssertEqual(classifier.classify("3루주자 김지찬 : 홈인"), [.run])
        XCTAssertEqual(classifier.classify("김영웅 : 유격수 실책으로 출루"), [.error])
    }

    func testOtherSituations() {
        XCTAssertEqual(classifier.classify("A : 중견수 희생플라이 아웃"), [.sacrificeFly])
        XCTAssertEqual(classifier.classify("A : 헛스윙 삼진 아웃"), [.strikeout])
        XCTAssertEqual(classifier.classify("A : 유격수 땅볼 아웃"), [.groundOut])
        XCTAssertEqual(classifier.classify("A : 3루수 앞 땅볼로 병살타"), [.doublePlay])
        XCTAssertEqual(classifier.classify("A : 좌익수 라인드라이브 아웃"), [.lineOut])
        XCTAssertEqual(classifier.classify("A : 볼넷"), [.walk])
        XCTAssertEqual(classifier.classify("A : 고의4구"), [.intentionalWalk])
        XCTAssertEqual(classifier.classify("A : 몸에 맞는 볼"), [.hitByPitch])
        XCTAssertEqual(classifier.classify("A : 우중간 2루타"), [.double])
        XCTAssertEqual(classifier.classify("A : 우익선상 3루타"), [.triple])
        XCTAssertEqual(classifier.classify("A : 중견수 앞 1루타"), [.single])
        XCTAssertEqual(classifier.classify("A : 내야안타"), [.single])
        XCTAssertEqual(classifier.classify("1루주자 A : 도루실패 아웃 (포수->유격수 태그아웃)"), [.caughtStealing])
        XCTAssertEqual(classifier.classify("투수 A : 투수 B (으)로 교체"), [.pitcherChange])
    }

    func testCombinedSituations() {
        XCTAssertEqual(classifier.classify("3루주자 A : 폭투로 홈인"), [.wildPitch, .run])
        XCTAssertEqual(classifier.classify("2루주자 A : 유격수 실책으로 홈인"), [.run, .error])
    }

    func testPitchesAndAdvancesAreIgnored() {
        XCTAssertEqual(classifier.classify("1구 볼"), [])
        XCTAssertEqual(classifier.classify("2구 스트라이크"), [])
        XCTAssertEqual(classifier.classify("4구 타격"), [])
        XCTAssertEqual(classifier.classify("1루주자 A : 2루까지 진루"), [])
        XCTAssertEqual(classifier.classify("5번타자 A"), [])
    }
}
