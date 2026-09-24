import AVFoundation
import MusicKit

enum MusicDeckError: LocalizedError {
    case appleMusicNotAuthorized
    case songNotFound

    var errorDescription: String? {
        switch self {
        case .appleMusicNotAuthorized: "Apple Music 접근 권한이 없습니다"
        case .songNotFound: "곡을 찾을 수 없습니다"
        }
    }
}

/// 등장곡/응원가를 재생한다. 내 파일(AVAudioPlayer)과 Apple Music(MusicKit)을 모두 지원.
@MainActor
final class MusicDeck {
    private let library: SongLibrary
    private var audioPlayer: AVAudioPlayer?
    private var usingAppleMusic = false
    /// 늦게 끝난 이전 play 요청이 새 곡을 덮어쓰지 않도록
    private var generation = 0

    init(library: SongLibrary) {
        self.library = library
    }

    func play(_ source: SongSource, loop: Bool) async throws {
        stop()
        generation += 1
        let current = generation

        switch source {
        case .localFile(let fileName, _):
            let player = try AVAudioPlayer(contentsOf: library.fileURL(for: fileName))
            player.numberOfLoops = loop ? -1 : 0
            player.volume = 0
            player.play()
            player.setVolume(1, fadeDuration: 0.4)
            audioPlayer = player

        case .appleMusic(let id, _, _):
            guard await MusicAuthorization.request() == .authorized else {
                throw MusicDeckError.appleMusicNotAuthorized
            }
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
            guard let song = try await request.response().items.first else {
                throw MusicDeckError.songNotFound
            }
            guard current == generation else { return }
            let player = ApplicationMusicPlayer.shared
            player.queue = [song]
            player.state.repeatMode = loop ? .one : MusicPlayer.RepeatMode.none
            try await player.play()
            guard current == generation else {
                player.stop()
                return
            }
            usingAppleMusic = true
        }
    }

    func stop(fade: Bool = false) {
        generation += 1
        if let player = audioPlayer {
            audioPlayer = nil
            if fade {
                player.setVolume(0, fadeDuration: 0.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { player.stop() }
            } else {
                player.stop()
            }
        }
        if usingAppleMusic {
            ApplicationMusicPlayer.shared.stop()
            usingAppleMusic = false
        }
    }

    /// 나레이션 동안 소리를 줄인다 (Apple Music 은 볼륨 조절이 안 되어 일시정지)
    func duck() {
        audioPlayer?.setVolume(0.15, fadeDuration: 0.2)
        if usingAppleMusic { ApplicationMusicPlayer.shared.pause() }
    }

    func unduck() {
        audioPlayer?.setVolume(1, fadeDuration: 0.5)
        if usingAppleMusic { Task { try? await ApplicationMusicPlayer.shared.play() } }
    }
}
