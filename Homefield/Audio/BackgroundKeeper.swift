import AVFoundation

/// 경기를 따라가는 동안 앱이 백그라운드에서도 중계를 계속 받도록 소리 없는 오디오를 반복 재생한다.
/// (UIBackgroundModes audio. 등장곡·응원가·나레이션과 같은 오디오 세션을 쓴다)
@MainActor
final class BackgroundKeeper {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        guard let player = try? AVAudioPlayer(data: Self.silentWAV()) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.play()
        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
    }

    /// 1초짜리 무음 WAV (8kHz, 16bit, mono)
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let samples = Data(count: Int(sampleRate) * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples.count))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples.count))
        data.append(samples)
        return data
    }
}
