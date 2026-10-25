import XCTest
@testable import HomefieldCore

final class LiveGameMonitorTests: XCTestCase {
    /// 6회에 들어오면 1~5회 중계도 첫 .entries 에 같이 온다 (재생할 이벤트는 지금 타자뿐)
    func testJoiningMidGameLoadsEarlierInnings() async {
        let provider = InningProvider(current: 6)
        let monitor = LiveGameMonitor(provider: provider, gameId: "g", pollInterval: .milliseconds(1))

        var firstEntries: [RelayEntry]?
        var firstEvents: [DetectedEvent]?
        for await update in monitor.updates() {
            switch update {
            case .entries(let entries) where firstEntries == nil: firstEntries = entries
            case .events(let events) where firstEvents == nil: firstEvents = events
            default: break
            }
            if firstEntries != nil && firstEvents != nil { break }
        }

        let innings = Set((firstEntries ?? []).compactMap(\.inning))
        XCTAssertEqual(innings, Set(1...6))
        XCTAssertEqual(firstEntries?.first?.inning, 1)
        XCTAssertEqual(firstEntries?.last?.inning, 6)
        // 지난 이닝을 다시 나레이션하지 않는다
        XCTAssertEqual(firstEvents?.count, 1)
        if case .batterUp(let player) = firstEvents?.first?.kind {
            XCTAssertEqual(player.name, "타자6")
        } else {
            XCTFail("현재 타자만 알려야 한다")
        }
    }

    func testEarlierEntriesSkipsFailedInnings() async {
        let provider = InningProvider(current: 4, failing: [2])
        let entries = await LiveGameMonitor.earlierEntries(provider: provider, gameId: "g", before: 4)
        XCTAssertEqual(Set(entries.compactMap(\.inning)), [1, 3])
    }
}

/// 이닝마다 "N번타자 타자N" + "타자N : 좌익수 플라이 아웃" 두 줄
private struct InningProvider: GameDataProvider {
    let current: Int
    var failing: Set<Int> = []

    func games(on date: Date) async throws -> [GameSummary] { [] }

    func relay(gameId: String, inning: Int?) async throws -> RelaySnapshot {
        let target = inning ?? current
        if failing.contains(target) { throw GameDataError.emptyResponse }
        var entries = [
            RelayEntry(id: "\(target)-intro", sequence: target * 100_000 + 1, inning: target, battingSide: .away, text: "1번타자 타자\(target)"),
        ]
        if target < current {
            entries.append(RelayEntry(id: "\(target)-out", sequence: target * 100_000 + 2, inning: target, battingSide: .away, text: "타자\(target) : 좌익수 플라이 아웃"))
        }
        let game = GameSummary(id: gameId, home: Team(code: "HT", name: "KIA"), away: Team(code: "NC", name: "NC"), status: .live)
        return RelaySnapshot(game: game, currentInning: target, entries: entries)
    }
}

final class PregameLockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func game(_ status: GameStatus, startTime: Date?) -> GameSummary {
        GameSummary(
            id: "20261025LGHT0",
            home: Team(code: "HT", name: "KIA"),
            away: Team(code: "LG", name: "LG"),
            status: status,
            startTime: startTime
        )
    }

    func testScheduledGameOpensThirtyMinutesBeforeStart() {
        let scheduled = game(.scheduled, startTime: start)
        XCTAssertTrue(scheduled.isPregameLocked(now: start.addingTimeInterval(-31 * 60)))
        XCTAssertFalse(scheduled.isPregameLocked(now: start.addingTimeInterval(-30 * 60)), "30분 전부터 열린다")
        XCTAssertFalse(scheduled.isPregameLocked(now: start.addingTimeInterval(-29 * 60)))
        XCTAssertFalse(scheduled.isPregameLocked(now: start))
        XCTAssertFalse(scheduled.isPregameLocked(now: start.addingTimeInterval(3600)))
        XCTAssertEqual(scheduled.pregameOpensAt, start.addingTimeInterval(-30 * 60))
    }

    func testOtherStatusesAreNeverLocked() {
        for status in [GameStatus.live, .finished, .cancelled, .unknown] {
            XCTAssertFalse(
                game(status, startTime: start).isPregameLocked(now: start.addingTimeInterval(-3600)),
                "\(status) 는 가리지 않는다"
            )
        }
        // 시작 시각을 모르면 가리지 않는다
        XCTAssertFalse(game(.scheduled, startTime: nil).isPregameLocked(now: start))
        XCTAssertNil(game(.scheduled, startTime: nil).pregameOpensAt)
    }
}
