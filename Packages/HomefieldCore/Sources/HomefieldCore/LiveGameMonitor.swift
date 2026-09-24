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
    case state(GameSummary?, lineups: [TeamSide: [Player]])
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
                        // 이닝이 바뀌었으면 지난 이닝의 마지막 상황을 놓치지 않도록 같이 가져온다
                        if let last = lastInning, let current = snapshot.currentInning, current != last,
                           let previous = try? await provider.relay(gameId: gameId, inning: last) {
                            snapshot.entries = previous.entries + snapshot.entries
                        }
                        lastInning = snapshot.currentInning ?? lastInning

                        continuation.yield(.state(snapshot.game, lineups: snapshot.lineups))
                        let events = detector.process(snapshot)
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
}
