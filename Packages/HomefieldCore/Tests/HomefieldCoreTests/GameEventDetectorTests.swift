import XCTest
@testable import HomefieldCore

final class GameEventDetectorTests: XCTestCase {
    private let game = GameSummary(
        id: "g1",
        home: Team(code: "SS", name: "삼성"),
        away: Team(code: "LG", name: "LG"),
        status: .live
    )

    private func snapshot(_ lines: [(TeamSide, String)], lineups: [TeamSide: [Player]] = [:]) -> RelaySnapshot {
        RelaySnapshot(
            game: game,
            currentInning: 1,
            entries: lines.enumerated().map { index, line in
                RelayEntry(id: "e\(index)", sequence: index, inning: 1, battingSide: line.0, text: line.1)
            },
            lineups: lineups
        )
    }

    func testFirstSnapshotOnlyReportsCurrentBatter() {
        let detector = GameEventDetector()
        let events = detector.process(snapshot([
            (.away, "1번타자 홍창기"),
            (.away, "홍창기 : 좌익수 플라이 아웃"),
            (.away, "2번타자 문성주"),
            (.away, "1구 볼"),
        ]))
        XCTAssertEqual(events.count, 1)
        guard case .batterUp(let player) = events.first?.kind else { return XCTFail() }
        XCTAssertEqual(player.name, "문성주")
        XCTAssertEqual(player.teamCode, "LG")
        XCTAssertEqual(player.battingOrder, 2)
    }

    func testFirstSnapshotSkipsFinishedBatter() {
        let detector = GameEventDetector()
        let events = detector.process(snapshot([
            (.away, "1번타자 홍창기"),
            (.away, "홍창기 : 좌익수 플라이 아웃"),
        ]))
        XCTAssertTrue(events.isEmpty)
    }

    func testOnlyNewEntriesAreReported() {
        let detector = GameEventDetector()
        var lines: [(TeamSide, String)] = [(.home, "1번타자 김지찬")]
        _ = detector.process(snapshot(lines))

        lines.append((.home, "김지찬 : 중견수 앞 1루타"))
        lines.append((.home, "2번타자 구자욱"))
        let events = detector.process(snapshot(lines))
        XCTAssertEqual(events.map(\.kind), [
            .play(.single),
            .batterUp(Player(id: "SS-구자욱", name: "구자욱", teamCode: "SS", battingOrder: 2)),
        ])

        XCTAssertTrue(detector.process(snapshot(lines)).isEmpty)
    }

    func testBatterResolvedFromLineup() {
        let detector = GameEventDetector()
        let lineup = [Player(id: "62234", name: "구자욱", teamCode: "SS", backNumber: "5", battingOrder: 3)]
        let events = detector.process(snapshot([(.home, "3번타자 구자욱")], lineups: [.home: lineup]))
        guard case .batterUp(let player) = events.first?.kind else { return XCTFail() }
        XCTAssertEqual(player.id, "62234")
        XCTAssertEqual(player.backNumber, "5")
    }
}
