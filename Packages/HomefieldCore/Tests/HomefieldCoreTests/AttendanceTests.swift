import XCTest
@testable import HomefieldCore

final class AttendanceTests: XCTestCase {
    func testNearestStadium() throws {
        // 잠실야구장 1루 관중석 근처
        let result = try XCTUnwrap(Stadiums.nearest(latitude: 37.5125, longitude: 127.0725))
        XCTAssertEqual(result.stadium.id, "jamsil")
        XCTAssertLessThan(result.distance, Stadiums.checkInRadius)
    }

    func testFarFromStadium() throws {
        // 서울역
        let result = try XCTUnwrap(Stadiums.nearest(latitude: 37.5547, longitude: 126.9707))
        XCTAssertGreaterThan(result.distance, Stadiums.checkInRadius)
    }

    func testDistance() {
        // 위도 0.01도 ≈ 1.11km
        XCTAssertEqual(Stadiums.distance(37.0, 127.0, 37.01, 127.0), 1112, accuracy: 5)
    }

    func testScheduleNameMatching() throws {
        let munhak = try XCTUnwrap(Stadiums.stadium(id: "munhak"))
        XCTAssertTrue(munhak.matches(scheduleName: "문학"))
        XCTAssertTrue(munhak.matches(scheduleName: "인천"))
        XCTAssertFalse(munhak.matches(scheduleName: "잠실"))
        XCTAssertFalse(munhak.matches(scheduleName: nil))
    }

    func testTiers() {
        XCTAssertEqual(FanTier.tier(forCheckIns: 0), .rookie)
        XCTAssertEqual(FanTier.tier(forCheckIns: 3), .lover)
        XCTAssertEqual(FanTier.tier(forCheckIns: 12), .mania)
        XCTAssertEqual(FanTier.tier(forCheckIns: 20), .player)
        XCTAssertEqual(FanTier.tier(forCheckIns: 49), .coach)
        XCTAssertEqual(FanTier.tier(forCheckIns: 100), .manager)
        XCTAssertEqual(FanTier.progress(forCheckIns: 6), 3.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(FanTier.progress(forCheckIns: 60), 1)
        XCTAssertNil(FanTier.manager.next)
    }
}
