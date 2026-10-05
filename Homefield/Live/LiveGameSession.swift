import Foundation
import HomefieldCore
import Observation
import UIKit

/// 한 경기를 따라가며 이벤트를 받아 (방송 지연만큼 늦춰서) 오디오로 내보낸다.
@MainActor
@Observable
final class LiveGameSession {
    struct LogLine: Identifiable {
        let id: String
        let time: Date
        let text: String
        let badge: String
        let isBatter: Bool
        let isPitch: Bool
        let halfKey: String
    }

    /// 이닝 초/말 하나의 중계 묶음
    struct Half: Identifiable {
        let id: String
        let title: String
        let lines: [LogLine]
    }

    private(set) var game: GameSummary
    private(set) var currentBatter: Player?
    private(set) var log: [LogLine] = []
    /// 볼카운트, 아웃, 주자, 수비 위치, 투수
    private(set) var gameState = LiveGameState()
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
    @ObservationIgnored private let stateTracker = GameStateTracker()
    @ObservationIgnored private let classifier = RelayTextClassifier()

    private struct PendingBatch {
        enum Payload {
            case entries([RelayEntry])
            case events([DetectedEvent])
        }

        let receivedAt: Date
        let payload: Payload
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
                switch batch.payload {
                case .entries(let entries): self.apply(entries)
                case .events(let events): await self.dispatch(events)
                }
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
        case .state(let summary, let lineups, let pitchers):
            if let summary { game = summary }
            for players in lineups.values {
                library.register(players: players)
            }
            for players in pitchers.values {
                library.register(players: players)
            }
            stateTracker.setLineups(lineups, pitchers: pitchers)
            gameState = stateTracker.state
            lastError = nil
        case .entries(let entries):
            pendingBatches += 1
            queue?.yield(PendingBatch(receivedAt: Date(), payload: .entries(entries)))
        case .events(let events):
            pendingBatches += 1
            queue?.yield(PendingBatch(receivedAt: Date(), payload: .events(events)))
        case .failure(let message):
            lastError = message
        }
    }

    /// 중계 줄: 경기 상황 계산 + 이닝별 중계 목록
    private func apply(_ entries: [RelayEntry]) {
        stateTracker.apply(entries)
        gameState = stateTracker.state
        library.record(seasonStats: entries.flatMap(\.seasonStats))
        let now = Date()
        for entry in entries.sorted(by: { $0.sequence < $1.sequence }) where !log.contains(where: { $0.id == entry.id }) {
            append(logLine(for: entry, at: now))
        }
    }

    private func logLine(for entry: RelayEntry, at time: Date) -> LogLine {
        let text = entry.text
        let isBatter = classifier.batterIntro(in: text) != nil
        let isPitch = text.range(of: #"^\d+\s*구\s"#, options: .regularExpression) != nil
        let badge: String
        if isBatter {
            badge = "🧢"
        } else if isPitch {
            badge = "·"
        } else if text.contains("교체") {
            badge = "🔄"
        } else {
            badge = classifier.classify(text).first?.emoji ?? "▫️"
        }
        return LogLine(
            id: entry.id,
            time: time,
            text: text,
            badge: badge,
            isBatter: isBatter,
            isPitch: isPitch,
            halfKey: Self.halfKey(inning: entry.inning, side: entry.battingSide)
        )
    }

    static func halfKey(inning: Int?, side: TeamSide?) -> String {
        guard let inning, let side else { return "etc" }
        return "\(inning)-\(side == .away ? 0 : 1)"
    }

    /// 지금 진행 중인 이닝 초/말
    var currentHalfKey: String {
        Self.halfKey(inning: gameState.inning, side: gameState.battingSide)
    }

    /// 최근 이닝이 위로 오는 이닝별 중계
    var halves: [Half] {
        var order: [String] = []
        var grouped: [String: [LogLine]] = [:]
        for line in log {
            if grouped[line.halfKey] == nil { order.append(line.halfKey) }
            grouped[line.halfKey, default: []].append(line)
        }
        return order.map { key in
            Half(id: key, title: Self.halfTitle(key), lines: grouped[key] ?? [])
        }
    }

    private static func halfTitle(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let inning = Int(parts[0]) else { return "기타" }
        return "\(inning)회\(parts[1] == "0" ? "초" : "말")"
    }

    private func dispatch(_ events: [DetectedEvent]) async {
        for event in events {
            if case .batterUp(let player) = event.kind {
                currentBatter = player
                library.register(players: [player])
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
        if log.count > 800 { log.removeLast(log.count - 800) }
    }
}
