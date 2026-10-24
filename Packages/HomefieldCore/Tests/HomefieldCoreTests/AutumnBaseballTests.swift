import XCTest
@testable import HomefieldCore

final class AutumnBaseballTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))!
    }

    func testSeasonWindow() {
        XCTAssertFalse(AutumnBaseball.isSeason(date(9, 30), calendar: calendar))
        XCTAssertTrue(AutumnBaseball.isSeason(date(10, 1), calendar: calendar))
        XCTAssertTrue(AutumnBaseball.isSeason(date(10, 24), calendar: calendar))
        XCTAssertTrue(AutumnBaseball.isSeason(date(11, 15), calendar: calendar))
        XCTAssertFalse(AutumnBaseball.isSeason(date(11, 16), calendar: calendar))
        XCTAssertFalse(AutumnBaseball.isSeason(date(4, 1), calendar: calendar))
    }

    func testModes() {
        XCTAssertTrue(AutumnBaseball.isActive(mode: .auto, date: date(10, 24), calendar: calendar))
        XCTAssertFalse(AutumnBaseball.isActive(mode: .auto, date: date(7, 1), calendar: calendar))
        XCTAssertTrue(AutumnBaseball.isActive(mode: .on, date: date(7, 1), calendar: calendar))
        XCTAssertFalse(AutumnBaseball.isActive(mode: .off, date: date(10, 24), calendar: calendar))
    }
}
