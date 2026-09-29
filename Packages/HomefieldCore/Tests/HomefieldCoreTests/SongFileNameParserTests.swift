import XCTest
@testable import HomefieldCore

final class SongFileNameParserTests: XCTestCase {
    func testPlayerSongs() {
        XCTAssertEqual(SongFileNameParser.parse("SS_구자욱_등장곡.mp3"), SongFileName(teamCode: "SS", playerName: "구자욱", kind: .walkUp))
        XCTAssertEqual(SongFileNameParser.parse("SS_구자욱_응원가.m4a"), SongFileName(teamCode: "SS", playerName: "구자욱", kind: .cheer))
        XCTAssertEqual(SongFileNameParser.parse("lg_홍창기_walkup.mp3"), SongFileName(teamCode: "LG", playerName: "홍창기", kind: .walkUp))
        XCTAssertEqual(SongFileNameParser.parse("LG_홍창기_응원가2.mp3")?.kind, .cheer)
    }

    func testTeamCheer() {
        let expected = SongFileName(teamCode: "SS", playerName: nil, kind: .teamCheer)
        XCTAssertEqual(SongFileNameParser.parse("SS_팀응원가.mp3"), expected)
        XCTAssertEqual(SongFileNameParser.parse("SS_팀_응원가.mp3"), expected)
        XCTAssertEqual(SongFileNameParser.parse("SS_응원가.mp3"), expected)
    }

    func testTeamNamesAndAliases() {
        XCTAssertEqual(SongFileNameParser.parse("삼성_구자욱_등장곡.mp3")?.teamCode, "SS")
        XCTAssertEqual(SongFileNameParser.parse("삼성 라이온즈_구자욱_등장곡.mp3")?.teamCode, "SS")
        XCTAssertEqual(SongFileNameParser.parse("KIA_김도영_등장곡.mp3")?.teamCode, "HT")
        XCTAssertEqual(SongFileNameParser.parse("기아_김도영_등장곡.mp3")?.teamCode, "HT")
        XCTAssertEqual(SongFileNameParser.parse("키움_송성문_응원가.mp3")?.teamCode, "WO")
        XCTAssertEqual(SongFileNameParser.parse("SSG_최정_등장곡.mp3")?.teamCode, "SK")
    }

    func testDecomposedHangulFromMac() {
        let nfd = "SS_구자욱_등장곡.mp3".decomposedStringWithCanonicalMapping
        XCTAssertEqual(SongFileNameParser.parse(nfd)?.playerName, "구자욱")
    }

    func testInvalidNames() {
        XCTAssertNil(SongFileNameParser.parse("구자욱.mp3"))
        XCTAssertNil(SongFileNameParser.parse("SS_구자욱.mp3"))
        XCTAssertNil(SongFileNameParser.parse("SS_구자욱_하이라이트.mp3"))
        XCTAssertNil(SongFileNameParser.parse("없는팀_구자욱_등장곡.mp3"))
    }

    func testPhotos() {
        XCTAssertEqual(SongFileNameParser.parse("SS_구자욱.jpg"), SongFileName(teamCode: "SS", playerName: "구자욱", kind: .photo))
        XCTAssertEqual(SongFileNameParser.parse("SS_구자욱_사진.PNG"), SongFileName(teamCode: "SS", playerName: "구자욱", kind: .photo))
        XCTAssertNil(SongFileNameParser.parse("SS_구자욱_등장곡.jpg"))
        XCTAssertNil(SongFileNameParser.parse("SS_구자욱_사진.mp3"))
    }

    func testIsAudio() {
        XCTAssertTrue(SongFileNameParser.isAudio("a.MP3"))
        XCTAssertFalse(SongFileNameParser.isAudio("players.json"))
    }
}
