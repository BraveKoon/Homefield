import XCTest
@testable import HomefieldCore

final class GameStateTrackerTests: XCTestCase {
    private var sequence = 0

    private func entries(_ lines: [String], inning: Int = 1, side: TeamSide = .away) -> [RelayEntry] {
        lines.map { text in
            sequence += 1
            return RelayEntry(id: "e\(sequence)", sequence: sequence, inning: inning, battingSide: side, text: text)
        }
    }

    func testFieldPositionLabels() {
        XCTAssertEqual(FieldPosition(label: "좌익수"), .left)
        XCTAssertEqual(FieldPosition(label: "선발투수"), .pitcher)
        XCTAssertEqual(FieldPosition(label: "1루수"), .first)
        XCTAssertEqual(FieldPosition(label: "유"), .shortstop)
        XCTAssertEqual(FieldPosition(label: "중"), .center)
        XCTAssertNil(FieldPosition(label: "지명타자"))
        XCTAssertNil(FieldPosition(label: "대타"))
    }

    func testCountResetsOnNewBatter() {
        let tracker = GameStateTracker()
        tracker.apply(entries(["1번타자 A", "1구 볼", "2구 스트라이크", "3구 파울", "4구 파울", "5구 볼"]))
        XCTAssertEqual(tracker.state.balls, 2)
        XCTAssertEqual(tracker.state.strikes, 2)
        XCTAssertEqual(tracker.state.batterName, "A")
        XCTAssertEqual(tracker.state.halfInningTitle, "1회초")

        tracker.apply(entries(["A : 좌익수 플라이 아웃", "2번타자 B"]))
        XCTAssertEqual(tracker.state.balls, 0)
        XCTAssertEqual(tracker.state.strikes, 0)
        XCTAssertEqual(tracker.state.outs, 1)
    }

    func testRunnersMoveAndScore() {
        let tracker = GameStateTracker()
        tracker.apply(entries([
            "1번타자 A", "A : 중견수 앞 1루타",
            "2번타자 B", "1루주자 A : 도루로 2루까지 진루",
        ]))
        XCTAssertEqual(tracker.state.bases, [nil, "A", nil])

        tracker.apply(entries(["B : 볼넷"]))
        XCTAssertEqual(tracker.state.bases, ["B", "A", nil])

        tracker.apply(entries(["3번타자 C", "C : 우중간 2루타", "2루주자 A : 홈인", "1루주자 B : 3루까지 진루"]))
        XCTAssertEqual(tracker.state.bases, [nil, "C", "B"])

        tracker.apply(entries(["4번타자 D", "D : 좌익수 뒤 홈런", "3루주자 B : 홈인", "2루주자 C : 홈인", "D : 홈인"]))
        XCTAssertEqual(tracker.state.bases, [nil, nil, nil])
    }

    func testForcedRunnerKeepsBatterOnFirst() {
        let tracker = GameStateTracker()
        tracker.apply(entries(["1번타자 A", "A : 유격수 실책으로 출루", "2번타자 B", "B : 볼넷", "1루주자 A : 2루까지 진루"]))
        XCTAssertEqual(tracker.state.bases, ["B", "A", nil])
    }

    func testDoublePlayCountsTwoOutsOnce() {
        let tracker = GameStateTracker()
        tracker.apply(entries(["1번타자 A", "A : 우익수 앞 1루타", "2번타자 B", "B : 3루수 앞 땅볼로 병살타", "1루주자 A : 2루에서 포스아웃"]))
        XCTAssertEqual(tracker.state.outs, 2)
        XCTAssertEqual(tracker.state.bases, [nil, nil, nil])
    }

    func testCaughtStealing() {
        let tracker = GameStateTracker()
        tracker.apply(entries(["1번타자 A", "A : 몸에 맞는 볼", "2번타자 B", "1루주자 A : 도루실패 아웃 (포수->유격수 태그아웃)"]))
        XCTAssertEqual(tracker.state.outs, 1)
        XCTAssertEqual(tracker.state.bases, [nil, nil, nil])
    }

    func testHalfInningResets() {
        let tracker = GameStateTracker()
        tracker.apply(entries(["1번타자 A", "A : 중견수 앞 1루타", "2번타자 B", "B : 헛스윙 삼진 아웃"]))
        XCTAssertEqual(tracker.state.outs, 1)
        tracker.apply(entries(["1번타자 X"], inning: 1, side: .home))
        XCTAssertEqual(tracker.state.outs, 0)
        XCTAssertEqual(tracker.state.bases, [nil, nil, nil])
        XCTAssertEqual(tracker.state.halfInningTitle, "1회말")
    }

    func testDefenseFromLineupsAndSubstitution() {
        let tracker = GameStateTracker()
        tracker.setLineups(
            [.home: [
                Player(id: "1", name: "좌익", teamCode: "H", position: "좌익수"),
                Player(id: "2", name: "지타", teamCode: "H", position: "지명타자"),
            ]],
            pitchers: [.home: [Player(id: "p", name: "선발", teamCode: "H")]]
        )
        tracker.apply(entries(["1번타자 A"], side: .away))
        XCTAssertEqual(tracker.state.fielders[.left], "좌익")
        XCTAssertEqual(tracker.state.pitcherName, "선발")
        XCTAssertEqual(tracker.state.fielders.count, 2)

        tracker.apply(entries(["투수 선발 : 투수 불펜 (으)로 교체", "좌익수 좌익 : 좌익수 대수비 (으)로 교체"], side: .away))
        XCTAssertEqual(tracker.state.pitcherName, "불펜")
        XCTAssertEqual(tracker.state.fielders[.left], "대수비")
    }

    func testProviderStateOverrides() {
        let tracker = GameStateTracker()
        var entry = entries(["1번타자 A"])[0]
        entry.state = CountState(balls: 3, strikes: 1, outs: 2, basesOccupied: [true, false, true])
        tracker.apply([entry])
        XCTAssertEqual(tracker.state.balls, 3)
        XCTAssertEqual(tracker.state.strikes, 1)
        XCTAssertEqual(tracker.state.outs, 2)
        XCTAssertEqual(tracker.state.bases, ["주자", nil, "주자"])
    }

    func testDemoGameStateAtEnd() async throws {
        let provider = DemoGameProvider()
        let monitor = LiveGameMonitor(provider: provider, gameId: DemoGameProvider.gameId, pollInterval: .milliseconds(1))
        let tracker = GameStateTracker()
        for await update in monitor.updates() {
            switch update {
            case .state(_, let lineups, let pitchers): tracker.setLineups(lineups, pitchers: pitchers)
            case .entries(let entries): tracker.apply(entries)
            default: break
            }
        }
        // 2회초: 희생플라이 아웃, 도루실패, 라인드라이브 아웃 → 3아웃, 투수는 교체된 이세준
        XCTAssertEqual(tracker.state.halfInningTitle, "2회초")
        XCTAssertEqual(tracker.state.outs, 3)
        XCTAssertEqual(tracker.state.pitcherName, "이세준")
        XCTAssertEqual(tracker.state.fielders[.center], "한결")
    }
}
