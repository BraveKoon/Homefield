import XCTest
@testable import HomefieldCore

final class PlayerProfileTests: XCTestCase {
    func testDecodeProfilesFile() throws {
        let json = """
        {"players": [
          {"team": "삼성", "name": "구자욱",
           "moves": ["박수 두 번", "오른손 앞으로"],
           "chant": "구자욱 안타!",
           "cheerHistory": [{"period": "2015", "text": "첫 응원가"}],
           "teamHistory": [{"period": "2012–", "text": "삼성 라이온즈"}]},
          {"team": "LG", "name": "홍창기"}
        ]}
        """
        let file = try PlayerProfilesFile.decode(Data(json.utf8))
        XCTAssertEqual(file.players.count, 2)
        XCTAssertEqual(file.players[0].teamCode, "SS")
        // 예전 형식의 응원 동작·변천사 항목은 무시하고 팀 이력만 읽는다
        XCTAssertEqual(file.players[0].profile.teamHistory.first?.text, "삼성 라이온즈")
        XCTAssertTrue(file.players[1].profile.isEmpty)
    }

    func testUnknownTeamFails() {
        let json = #"{"players": [{"team": "없는팀", "name": "A"}]}"#
        XCTAssertThrowsError(try PlayerProfilesFile.decode(Data(json.utf8)))
    }

    func testMergeKeepsExistingWhenEmpty() {
        var profile = PlayerProfile(memo: "메모")
        profile.merge(PlayerProfile(teamHistory: [TimelineEntry(period: "2020", text: "LG")]))
        XCTAssertEqual(profile.memo, "메모")
        XCTAssertEqual(profile.teamHistory.first?.text, "LG")
    }

    func testRoundTrip() throws {
        let profile = PlayerProfile(teamHistory: [TimelineEntry(period: "2019", text: "b")], memo: "m")
        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.teamHistory.map(\.text), ["b"])
        XCTAssertEqual(decoded.memo, "m")
    }
}

final class BattingLineTests: XCTestCase {
    func testRecord() {
        var line = BattingLine()
        [.single, .homeRun, .strikeout, .walk, .flyOut, .sacrificeFly].forEach { line.record($0) }
        XCTAssertEqual(line.plateAppearances, 6)
        XCTAssertEqual(line.atBats, 4)
        XCTAssertEqual(line.hits, 2)
        XCTAssertEqual(line.homeRuns, 1)
        XCTAssertEqual(line.averageText, ".500")
        XCTAssertEqual(line.summary, "4타수 2안타 1홈런 1볼넷 1삼진")
    }

    func testEmptyAverage() {
        var line = BattingLine()
        XCTAssertEqual(line.averageText, "-")
        line.record(.walk)
        XCTAssertNil(line.average)
    }
}

final class PlateAppearanceTrackerTests: XCTestCase {
    private let batter = Player(id: "1", name: "강두원", teamCode: "DRM")

    private func play(_ kind: PlayKind, _ subject: String) -> DetectedEvent {
        DetectedEvent(id: UUID().uuidString, kind: .play(kind), text: "", subject: subject)
    }

    func testHomeRunCountsOnceAndIgnoresRunners() {
        let tracker = PlateAppearanceTracker()
        let results = tracker.process([
            DetectedEvent(id: "b", kind: .batterUp(batter), text: ""),
            play(.stolenBase, "한결"),
            play(.homeRun, "강두원"),
            play(.run, "한결"),
            play(.run, "강두원"),
        ])
        XCTAssertEqual(results, [.init(player: batter, kind: .homeRun)])
    }

    func testReachedOnError() {
        let tracker = PlateAppearanceTracker()
        let results = tracker.process([
            DetectedEvent(id: "b", kind: .batterUp(batter), text: ""),
            play(.error, "강두원"),
        ])
        XCTAssertEqual(results.map(\.kind), [.error])
    }

    func testAcrossBatches() {
        let tracker = PlateAppearanceTracker()
        XCTAssertTrue(tracker.process([DetectedEvent(id: "b", kind: .batterUp(batter), text: "")]).isEmpty)
        XCTAssertEqual(tracker.process([play(.strikeout, "강두원")]).map(\.kind), [.strikeout])
    }
}
