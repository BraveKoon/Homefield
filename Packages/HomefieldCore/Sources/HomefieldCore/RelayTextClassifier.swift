import Foundation

/// 한국어 문자 중계 문구를 해석한다.
///
/// 예시 문구 (네이버 스포츠 문자중계 기준):
/// - "3번타자 구자욱"
/// - "구자욱 : 좌익수 플라이 아웃"
/// - "1루주자 김지찬 : 도루로 2루까지 진루"
/// - "3루주자 김지찬 : 홈인"
/// - "김영웅 : 유격수 실책으로 출루"
public struct RelayTextClassifier: Sendable {
    public struct BatterIntro: Equatable, Sendable {
        public var order: Int?
        public var name: String
    }

    public init() {}

    private static let introRegex = try! NSRegularExpression(
        pattern: #"^(\d+)\s*번\s*타자\s*[:：]?\s*(\S+)\s*$"#
    )

    public func batterIntro(in text: String) -> BatterIntro? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard
            let match = Self.introRegex.firstMatch(in: trimmed, range: range),
            let orderRange = Range(match.range(at: 1), in: trimmed),
            let nameRange = Range(match.range(at: 2), in: trimmed)
        else { return nil }
        return BatterIntro(order: Int(trimmed[orderRange]), name: String(trimmed[nameRange]))
    }

    /// "1루주자 김지찬 : 홈인" → "김지찬"
    public func subject(of text: String) -> String? {
        guard let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let head = text[..<colon].trimmingCharacters(in: .whitespaces)
        return head.split(separator: " ").last.map(String.init)
    }

    /// 콜론 뒤의 상황 설명 부분
    public func body(of text: String) -> String {
        guard let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return text }
        return text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    /// 한 줄에서 여러 상황이 나올 수 있다 (예: "폭투로 홈인" → [폭투, 득점])
    public func classify(_ text: String) -> [PlayKind] {
        if batterIntro(in: text) != nil { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body(of: trimmed)

        if trimmed.hasPrefix("투수"), body.contains("교체") {
            return [.pitcherChange]
        }

        var kinds: [PlayKind] = []
        if let primary = Self.rules.first(where: { $0.matches(body) })?.kind {
            kinds.append(primary)
        }
        if body.contains("홈인") {
            kinds.append(.run)
        }
        if body.contains("실책") {
            kinds.append(.error)
        }
        return kinds
    }

    private struct Rule: Sendable {
        let kind: PlayKind
        let matches: @Sendable (String) -> Bool
    }

    /// 순서가 중요하다: 더 구체적인 문구를 먼저 검사한다.
    private static let rules: [Rule] = [
        Rule(kind: .homeRun) { $0.contains("홈런") },
        Rule(kind: .caughtStealing) { $0.contains("도루실패") || $0.contains("도루 실패") },
        Rule(kind: .stolenBase) { $0.contains("도루") },
        Rule(kind: .doublePlay) { $0.contains("병살") },
        Rule(kind: .sacrificeFly) { $0.contains("희생플라이") || $0.contains("희생 플라이") },
        Rule(kind: .sacrificeBunt) { $0.contains("희생번트") || $0.contains("희생 번트") },
        Rule(kind: .strikeout) { $0.contains("삼진") },
        Rule(kind: .flyOut) { $0.contains("플라이") && $0.contains("아웃") },
        Rule(kind: .lineOut) { $0.contains("라인드라이브") && $0.contains("아웃") },
        Rule(kind: .groundOut) { $0.contains("땅볼") && $0.contains("아웃") },
        Rule(kind: .intentionalWalk) {
            $0.contains("고의4구") || $0.contains("고의 4구") || $0.contains("고의사구")
        },
        Rule(kind: .walk) { $0.contains("볼넷") },
        Rule(kind: .hitByPitch) { $0.contains("몸에 맞는") },
        Rule(kind: .triple) { $0.contains("3루타") },
        Rule(kind: .double) { $0.contains("2루타") },
        Rule(kind: .single) { $0.contains("1루타") || $0.contains("안타") },
        Rule(kind: .wildPitch) { $0.contains("폭투") },
        Rule(kind: .passedBall) { $0.contains("포일") },
    ]
}
