import XCTest
@testable import HomefieldCore

final class NarrationComposerTests: XCTestCase {
    private func play(_ kind: PlayKind, _ subject: String? = nil) -> DetectedEvent {
        DetectedEvent(id: UUID().uuidString, kind: .play(kind), text: "", subject: subject)
    }

    func testSingleNarration() {
        let cues = NarrationComposer().compose([play(.flyOut)])
        XCTAssertEqual(cues, [.announce("플라이아웃!", kinds: [.flyOut])])
    }

    func testHomeRunAbsorbsRuns() {
        let cues = NarrationComposer().compose([
            play(.homeRun, "강두원"),
            play(.run, "한결"),
            play(.run, "서지후"),
            play(.run, "강두원"),
        ])
        XCTAssertEqual(cues, [.announce("쓰리런 홈런!", kinds: [.homeRun])])
    }

    func testSoloHomeRun() {
        let cues = NarrationComposer().compose([play(.homeRun, "A"), play(.run, "A")])
        XCTAssertEqual(cues, [.announce("홈런!", kinds: [.homeRun])])
    }

    func testConsecutiveRunsMerge() {
        let cues = NarrationComposer().compose([play(.double), play(.run), play(.run)])
        XCTAssertEqual(cues, [.announce("2루타! 2점 득점!", kinds: [.double, .run])])
    }

    func testDisabledKindsAreSkipped() {
        let composer = NarrationComposer(enabled: [.stolenBase])
        XCTAssertEqual(composer.compose([play(.single), play(.stolenBase)]), [.announce("도루 성공!", kinds: [.stolenBase])])
    }

    func testBatterUpSplitsAnnouncements() {
        let batter = Player(id: "1", name: "B", teamCode: "X")
        let cues = NarrationComposer().compose([
            play(.strikeout),
            DetectedEvent(id: "b", kind: .batterUp(batter), text: ""),
            play(.stolenBase),
        ])
        XCTAssertEqual(cues, [
            .announce("삼진 아웃!", kinds: [.strikeout]),
            .batterUp(batter),
            .announce("도루 성공!", kinds: [.stolenBase]),
        ])
    }

    func testCustomPhrase() {
        let composer = NarrationComposer(phrases: [.error: "에러!"])
        XCTAssertEqual(composer.compose([play(.error)]), [.announce("에러!", kinds: [.error])])
    }
}
