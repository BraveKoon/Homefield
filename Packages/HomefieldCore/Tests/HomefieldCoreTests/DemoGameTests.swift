import XCTest
@testable import HomefieldCore

final class DemoGameTests: XCTestCase {
    /// 데모 경기를 끝까지 돌려서 요청된 상황들이 모두 나레이션되는지 확인
    func testDemoGameProducesRequestedNarrations() async throws {
        let provider = DemoGameProvider()
        let monitor = LiveGameMonitor(provider: provider, gameId: DemoGameProvider.gameId, pollInterval: .milliseconds(1))
        let composer = NarrationComposer()

        var cues: [AudioCue] = []
        var lastGame: GameSummary?
        for await update in monitor.updates() {
            switch update {
            case .events(let events): cues += composer.compose(events)
            case .state(let game, _): lastGame = game
            case .failure(let message): XCTFail(message)
            }
        }

        let spoken = cues.compactMap { cue -> String? in
            if case .announce(let text, _) = cue { return text }
            return nil
        }.joined(separator: " ")
        for phrase in ["플라이아웃!", "도루 성공!", "쓰리런 홈런!", "득점!", "실책!"] {
            XCTAssertTrue(spoken.contains(phrase), "\(phrase) 누락: \(spoken)")
        }

        let batters = cues.compactMap { cue -> String? in
            if case .batterUp(let player) = cue { return player.name }
            return nil
        }
        XCTAssertEqual(batters.first, "강한별")
        XCTAssertTrue(batters.contains("강두원"))

        XCTAssertEqual(lastGame?.status, .finished)
        XCTAssertEqual(lastGame?.homeScore, 3)
        XCTAssertEqual(lastGame?.awayScore, 1)
    }
}
