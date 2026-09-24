import AVFoundation
import HomefieldCore
import Observation

/// 등장곡 → 응원가 → 나레이션 흐름을 조율한다.
@MainActor
@Observable
final class AudioDirector {
    private(set) var nowPlaying: String?
    private(set) var lastError: String?
    var isMuted = false {
        didSet { if isMuted { stopAll() } }
    }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let library: SongLibrary
    @ObservationIgnored private let deck: MusicDeck
    @ObservationIgnored private let narrator = Narrator()
    @ObservationIgnored private var batterTask: Task<Void, Never>?

    init(settings: AppSettings, library: SongLibrary) {
        self.settings = settings
        self.library = library
        self.deck = MusicDeck(library: library)
    }

    static func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    func perform(_ cue: AudioCue) async {
        guard !isMuted else { return }
        switch cue {
        case .batterUp(let player):
            startBatter(player)
        case .announce(let text, let kinds):
            await announce(text, endsPlateAppearance: kinds.contains(where: \.endsPlateAppearance))
        }
    }

    func stopAll() {
        batterTask?.cancel()
        batterTask = nil
        narrator.stop()
        deck.stop()
        nowPlaying = nil
    }

    func stopMusic() {
        batterTask?.cancel()
        deck.stop(fade: true)
        nowPlaying = nil
    }

    /// 선수 노래 설정 화면의 미리듣기
    func preview(_ source: SongSource) {
        stopAll()
        Self.activateSession()
        Task { await play(source, loop: false) }
    }

    // MARK: -

    private func startBatter(_ player: Player) {
        batterTask?.cancel()
        deck.stop(fade: true)
        nowPlaying = nil

        batterTask = Task { [weak self] in
            guard let self else { return }
            if settings.announceBatter {
                await speak(batterAnnouncement(player))
            }
            guard !Task.isCancelled, settings.shouldPlaySongs(for: player) else { return }

            let walkUp = library.assignment(for: player).walkUp
            let cheer = library.cheer(for: player)

            if let walkUp {
                await play(walkUp, loop: cheer == nil)
                guard cheer != nil else { return }
                try? await Task.sleep(for: .seconds(settings.walkUpDuration))
                guard !Task.isCancelled else { return }
            }
            if let cheer {
                await play(cheer, loop: true)
            }
        }
    }

    private func announce(_ text: String, endsPlateAppearance: Bool) async {
        if endsPlateAppearance {
            stopMusic()
        } else {
            deck.duck()
        }
        await speak(text)
        if !endsPlateAppearance {
            deck.unduck()
        }
    }

    private func speak(_ text: String) async {
        narrator.rate = settings.speechRate
        await narrator.speak(text)
    }

    private func play(_ source: SongSource, loop: Bool) async {
        do {
            try await deck.play(source, loop: loop)
            nowPlaying = "\(source.title) · \(source.subtitle)"
            lastError = nil
        } catch {
            lastError = "\(source.title): \(error.localizedDescription)"
        }
    }

    private func batterAnnouncement(_ player: Player) -> String {
        var parts: [String] = []
        if let order = player.battingOrder { parts.append("\(order)번 타자") }
        if let number = player.backNumber { parts.append("등번호 \(number)번") }
        parts.append(player.name)
        return parts.joined(separator: ", ") + "!"
    }
}
