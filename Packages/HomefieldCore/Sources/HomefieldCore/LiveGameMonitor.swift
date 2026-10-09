import Foundation

public protocol GameDataProvider: Sendable {
    func games(on date: Date) async throws -> [GameSummary]
    /// inning 이 nil 이면 현재 이닝
    func relay(gameId: String, inning: Int?) async throws -> RelaySnapshot
}

public enum GameDataError: LocalizedError {
    case badStatus(Int)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code): "서버 응답 오류 (\(code))"
        case .emptyResponse: "데이터가 없습니다"
        }
    }
}

public enum MonitorUpdate: Sendable {
    case state(GameSummary?, lineups: [TeamSide: [Player]], pitchers: [TeamSide: [Player]])
    /// 새로 들어온 중계 줄 (투구 포함). 볼카운트·주자 계산용이며 같은 폴링의 .events 보다 먼저 온다.
    case entries([RelayEntry])
    case events([DetectedEvent])
    case failure(String)
}

/// 주기적으로 중계를 가져와 새 이벤트를 흘려보낸다.
public struct LiveGameMonitor: Sendable {
    public var provider: any GameDataProvider
    public var gameId: String
    public var pollInterval: Duration

    public init(provider: any GameDataProvider, gameId: String, pollInterval: Duration = .seconds(5)) {
        self.provider = provider
        self.gameId = gameId
        self.pollInterval = pollInterval
    }

    public func updates() -> AsyncStream<MonitorUpdate> {
        let provider = provider
        let gameId = gameId
        let pollInterval = pollInterval

        return AsyncStream { continuation in
            let task = Task {
                let detector = GameEventDetector()
                var lastInning: Int?

                while !Task.isCancelled {
                    do {
                        var snapshot = try await provider.relay(gameId: gameId, inning: nil)
                        // 경기 중간에 들어오면 1회부터 지난 이닝 중계도 받아서 앞에 붙인다 (재생은 하지 않는다)
                        if lastInning == nil, let current = snapshot.currentInning, current > 1 {
                            snapshot.entries = await Self.earlierEntries(provider: provider, gameId: gameId, before: current)
                                + snapshot.entries
                        }
                        // 이닝이 바뀌었으면 지난 이닝의 마지막 상황을 놓치지 않도록 같이 가져온다
                        if let last = lastInning, let current = snapshot.currentInning, current != last,
                           let previous = try? await provider.relay(gameId: gameId, inning: last) {
                            snapshot.entries = previous.entries + snapshot.entries
                        }
                        lastInning = snapshot.currentInning ?? lastInning

                        continuation.yield(.state(snapshot.game, lineups: snapshot.lineups, pitchers: snapshot.pitchers))
                        let events = detector.process(snapshot)
                        if !detector.lastEntries.isEmpty {
                            continuation.yield(.entries(detector.lastEntries))
                        }
                        if !events.isEmpty {
                            continuation.yield(.events(events))
                        }
                        if snapshot.game?.status == .finished || snapshot.game?.status == .cancelled {
                            break
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.yield(.failure(error.localizedDescription))
                    }
                    try? await Task.sleep(for: pollInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 1회부터 before-1 회까지 중계 줄 (한꺼번에 요청, 실패한 이닝은 건너뛴다)
    static func earlierEntries(provider: any GameDataProvider, gameId: String, before current: Int) async -> [RelayEntry] {
        await withTaskGroup(of: [RelayEntry].self) { group in
            for inning in 1..<current {
                group.addTask {
                    ((try? await provider.relay(gameId: gameId, inning: inning))?.entries ?? [])
                        .filter { $0.inning == nil || $0.inning == inning }
                }
            }
            var all: [RelayEntry] = []
            for await entries in group { all += entries }
            return all.sorted { $0.sequence < $1.sequence }
        }
    }
}
