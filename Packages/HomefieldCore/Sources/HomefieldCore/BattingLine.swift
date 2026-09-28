import Foundation

/// 타석 결과를 모은 간단한 타격 기록
public struct BattingLine: Codable, Hashable, Sendable {
    public var plateAppearances = 0
    public var atBats = 0
    public var hits = 0
    public var doubles = 0
    public var triples = 0
    public var homeRuns = 0
    public var walks = 0
    public var strikeouts = 0
    public var results: [PlayKind] = []

    public init() {}

    public mutating func record(_ kind: PlayKind) {
        plateAppearances += 1
        results.append(kind)
        switch kind {
        case .single:
            atBats += 1; hits += 1
        case .double:
            atBats += 1; hits += 1; doubles += 1
        case .triple:
            atBats += 1; hits += 1; triples += 1
        case .homeRun:
            atBats += 1; hits += 1; homeRuns += 1
        case .walk, .intentionalWalk, .hitByPitch:
            walks += 1
        case .strikeout:
            atBats += 1; strikeouts += 1
        case .sacrificeFly, .sacrificeBunt:
            break
        default:
            // 플라이·땅볼·라인드라이브 아웃, 병살, 실책 출루
            atBats += 1
        }
    }

    public var isEmpty: Bool { plateAppearances == 0 }

    /// 타율 (타수가 없으면 nil)
    public var average: Double? {
        atBats > 0 ? Double(hits) / Double(atBats) : nil
    }

    /// ".333" 형식
    public var averageText: String {
        guard let average else { return "-" }
        let thousandths = Int((average * 1000).rounded())
        if thousandths >= 1000 { return "1.000" }
        return "." + String(format: "%03d", thousandths)
    }

    /// "3타수 1안타 1홈런 1볼넷"
    public var summary: String {
        var parts = ["\(atBats)타수 \(hits)안타"]
        if homeRuns > 0 { parts.append("\(homeRuns)홈런") }
        if walks > 0 { parts.append("\(walks)볼넷") }
        if strikeouts > 0 { parts.append("\(strikeouts)삼진") }
        return parts.joined(separator: " ")
    }
}

/// 이벤트 흐름에서 타자별 타석 결과를 뽑는다.
public final class PlateAppearanceTracker {
    public struct Result: Equatable, Sendable {
        public var player: Player
        public var kind: PlayKind
    }

    private var current: Player?

    public init() {}

    public func process(_ events: [DetectedEvent]) -> [Result] {
        var results: [Result] = []
        for event in events {
            switch event.kind {
            case .batterUp(let player):
                current = player
            case .play(let kind):
                guard let batter = current, event.subject == batter.name else { continue }
                // 타자 본인의 타석 결과만 (주자 이벤트 제외). 실책 출루도 타석으로 센다.
                if kind.endsPlateAppearance || kind == .error {
                    results.append(Result(player: batter, kind: kind))
                    current = nil
                }
            }
        }
        return results
    }
}
