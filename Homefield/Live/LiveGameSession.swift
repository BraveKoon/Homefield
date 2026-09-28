import Foundation
import HomefieldCore
import Observation
import UIKit

/// 한 경기를 따라가며 이벤트를 받아 (방송 지연만큼 늦춰서) 오디오로 내보낸다.
@MainActor
@Observable
final class LiveGameSession {
    struct LogLine: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
        let badge: String
        let isBatter: Bool
    }

    private(set) var game: GameSummary
    private(set) var currentBatter: Player?
    private(set) var log: [LogLine] = []
    /// 이번 경기에서 선수별 타석 결과 (키: SongLibrary.key)
    private(set) var todayLines: [String: BattingLine] = [:]
    private(set) var lastError: String?
    private(set) var isRunning = false
    /// 방송 지연 때문에 대기 중인 이벤트 묶음 수
    private(set) var pendingBatches = 0

    @ObservationIgnored private let provider: any GameDataProvider
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let library: SongLibrary
    @ObservationIgnored private let director: AudioDirector
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var dispatchTask: Task<Void, Never>?
    @ObservationIgnored private var queue: AsyncStream<PendingBatch>.Continuation?
    @ObservationIgnored private let tracker = PlateAppearanceTracker()

    private struct PendingBatch {
        let receivedAt: Date
        let events: [DetectedEvent]
    }

    init(game: GameSummary, provider: any GameDataProvider, settings: AppSettings, library: SongLibrary, director: AudioDirector) {
        self.game = game
        self.provider = provider
        self.settings = settings
        self.library = library
        self.director = director
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        AudioDirector.activateSession()
        library.register(team: game.home)
        library.register(team: game.away)

        let (stream, continuation) = AsyncStream<PendingBatch>.makeStream()
        queue = continuation
        dispatchTask = Task { [weak self] in
            for await batch in stream {
                guard let self else { return }
                let wait = batch.receivedAt.addingTimeInterval(self.settings.broadcastDelay).timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                self.pendingBatches -= 1
                await self.dispatch(batch.events)
            }
        }

        let monitor = LiveGameMonitor(
            provider: provider,
            gameId: game.id,
            pollInterval: .seconds(settings.pollInterval)
        )
        monitorTask = Task { [weak self] in
            for await update in monitor.updates() {
                guard let self else { return }
                self.handle(update)
            }
            self?.queue?.finish()
        }
    }

    func stop() {
        monitorTask?.cancel()
        dispatchTask?.cancel()
        queue?.finish()
        monitorTask = nil
        dispatchTask = nil
        queue = nil
        isRunning = false
        pendingBatches = 0
        director.stopAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func handle(_ update: MonitorUpdate) {
        switch update {
        case .state(let summary, let lineups):
            if let summary { game = summary }
            for players in lineups.values {
                library.register(players: players)
            }
            lastError = nil
        case .events(let events):
            pendingBatches += 1
            queue?.yield(PendingBatch(receivedAt: Date(), events: events))
        case .failure(let message):
            lastError = message
        }
    }

    private func dispatch(_ events: [DetectedEvent]) async {
        for event in events {
            switch event.kind {
            case .batterUp(let player):
                currentBatter = player
                library.register(players: [player])
                append(LogLine(time: Date(), text: event.text, badge: "🧢", isBatter: true))
            case .play(let kind):
                // "폭투로 홈인" 처럼 한 줄에서 여러 상황이 나오면 로그는 한 번만
                if log.first?.text == event.text { continue }
                append(LogLine(time: Date(), text: event.text, badge: kind.emoji, isBatter: false))
            }
        }
        for result in tracker.process(events) {
            let key = SongLibrary.key(teamCode: result.player.teamCode, name: result.player.name)
            todayLines[key, default: BattingLine()].record(result.kind)
            library.recordPlateAppearance(result.kind, for: result.player)
        }
        for cue in settings.composer.compose(events) {
            await director.perform(cue)
        }
    }

    func todayLine(for player: Player) -> BattingLine? {
        todayLines[SongLibrary.key(teamCode: player.teamCode, name: player.name)]
    }

    private func append(_ line: LogLine) {
        log.insert(line, at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }
}
