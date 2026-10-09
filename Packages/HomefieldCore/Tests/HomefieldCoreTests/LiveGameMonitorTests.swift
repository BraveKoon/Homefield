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
