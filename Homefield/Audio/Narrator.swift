import AVFoundation

/// 한국어 TTS 나레이션
@MainActor
final class Narrator: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private lazy var voice: AVSpeechSynthesisVoice? = Self.bestKoreanVoice()

    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    /// 다 읽을 때까지 기다린다
    func speak(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.1

        let key = ObjectIdentifier(utterance)
        // iOS 가 끝났다는 알림(didFinish)을 주지 않는 경우가 있어서, 넉넉한 시간이 지나면 기다리기를 그만둔다.
        // (그대로 두면 다음 나레이션·중계 처리가 계속 밀린다)
        let limit = Duration.seconds(3 + Double(text.count) * 0.3)
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            self?.finish(key)
        }
        await withCheckedContinuation { continuation in
            pending[key] = continuation
            synthesizer.speak(utterance)
        }
        timeout.cancel()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finish(_ key: ObjectIdentifier) {
        pending.removeValue(forKey: key)?.resume()
    }

    private static func bestKoreanVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "ko-KR" }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "ko-KR")
    }
}

extension Narrator: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(key) }
    }
}
