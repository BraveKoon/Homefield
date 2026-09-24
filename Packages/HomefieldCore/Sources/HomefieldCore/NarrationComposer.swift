import Foundation

public enum AudioCue: Hashable, Sendable {
    /// 타자 등장: 등장곡 → 응원가
    case batterUp(Player)
    /// 나레이션. kinds 는 문구에 포함된 상황들.
    case announce(String, kinds: [PlayKind])
}

/// 한 번에 들어온 이벤트 묶음을 오디오 큐로 바꾼다.
///
/// - 홈런 직후의 득점(홈인)들은 "투런 홈런!" 처럼 하나로 합친다.
/// - 연속된 득점은 "2점 득점!" 으로 합친다.
/// - 연속된 나레이션은 한 문장으로 이어 붙인다.
public struct NarrationComposer: Sendable {
    public var enabled: Set<PlayKind>
    public var phrases: [PlayKind: String]

    public init(enabled: Set<PlayKind> = Set(PlayKind.allCases), phrases: [PlayKind: String] = [:]) {
        self.enabled = enabled
        self.phrases = phrases
    }

    public func phrase(for kind: PlayKind) -> String {
        phrases[kind] ?? kind.defaultNarration
    }

    public func compose(_ events: [DetectedEvent]) -> [AudioCue] {
        var cues: [AudioCue] = []
        var pendingText: [String] = []
        var pendingKinds: [PlayKind] = []

        func flush() {
            guard !pendingText.isEmpty else { return }
            cues.append(.announce(pendingText.joined(separator: " "), kinds: pendingKinds))
            pendingText = []
            pendingKinds = []
        }

        func say(_ text: String, _ kind: PlayKind) {
            pendingText.append(text)
            pendingKinds.append(kind)
        }

        var index = 0
        while index < events.count {
            let event = events[index]
            switch event.kind {
            case .batterUp(let player):
                flush()
                cues.append(.batterUp(player))
                index += 1

            case .play(.homeRun):
                var next = index + 1
                // 뒤따르는 홈인 중 타자 본인을 뺀 수 = 주자 수
                var otherRunners = 0
                while next < events.count, case .play(.run) = events[next].kind {
                    if events[next].subject == nil || events[next].subject != event.subject {
                        otherRunners += 1
                    }
                    next += 1
                }
                if enabled.contains(.homeRun) {
                    say(homeRunPhrase(runs: otherRunners + 1), .homeRun)
                } else if enabled.contains(.run) {
                    say(runPhrase(count: otherRunners + 1), .run)
                }
                index = next

            case .play(.run):
                var next = index + 1
                while next < events.count, case .play(.run) = events[next].kind {
                    next += 1
                }
                if enabled.contains(.run) {
                    say(runPhrase(count: next - index), .run)
                }
                index = next

            case .play(let kind):
                if enabled.contains(kind) {
                    say(phrase(for: kind), kind)
                }
                index += 1
            }
        }
        flush()
        return cues
    }

    private func homeRunPhrase(runs: Int) -> String {
        switch runs {
        case 2: "투런 홈런!"
        case 3: "쓰리런 홈런!"
        case 4...: "만루 홈런!"
        default: phrase(for: .homeRun)
        }
    }

    private func runPhrase(count: Int) -> String {
        count > 1 ? "\(count)점 득점!" : phrase(for: .run)
    }
}
