import Foundation

/// 문자중계 한 줄을 잠금화면에 보여 줄 짧은 문장으로 바꾼다.
///
/// - "구자욱 : 좌익수 희생플라이 아웃" → "구자욱 희생플라이 (좌익수)"
/// - "1루주자 김지찬 : 도루로 2루까지 진루" → "김지찬 도루(1루 → 2루)"
/// - "3루주자 김지찬 : 홈인" → "김지찬 홈인"
/// - "3번타자 구자욱" → "3번타자 구자욱 타석"
/// - "1구 볼" 같은 투구 한 개는 nil (너무 잦아서 뺀다)
public struct RelayHeadline: Sendable {
    private let classifier = RelayTextClassifier()

    private static let pitchRegex = try! NSRegularExpression(pattern: #"^\d+\s*구\s"#)
    private static let runnerRegex = try! NSRegularExpression(pattern: #"^([123])루주자\s+(\S+)\s*[:：]\s*(.*)$"#)
    private static let targetBaseRegex = try! NSRegularExpression(pattern: #"([123])루"#)

    /// 결과 이름을 그대로 쓰는 타자 결과
    private static let namedResults: [PlayKind] = [
        .homeRun, .triple, .double, .single, .walk, .intentionalWalk, .hitByPitch,
        .strikeout, .doublePlay, .sacrificeFly, .sacrificeBunt, .flyOut, .lineOut, .groundOut,
    ]

    public init() {}

    public func headline(for rawText: String) -> String? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if Self.pitchRegex.firstMatch(in: text, range: range) != nil { return nil }

        if let intro = classifier.batterIntro(in: text) {
            return [intro.order.map { "\($0)번타자" }, intro.name, "타석"].compactMap { $0 }.joined(separator: " ")
        }

        if let match = Self.runnerRegex.firstMatch(in: text, range: range),
           let fromRange = Range(match.range(at: 1), in: text),
           let nameRange = Range(match.range(at: 2), in: text),
           let bodyRange = Range(match.range(at: 3), in: text) {
            return runnerHeadline(from: String(text[fromRange]), name: String(text[nameRange]), body: String(text[bodyRange]))
        }

        let kinds = classifier.classify(text)
        if kinds.contains(.pitcherChange) {
            return text.replacingOccurrences(of: #"\s*[:：]\s*"#, with: " → ", options: .regularExpression)
        }
        if let subject = classifier.subject(of: text) {
            let body = classifier.body(of: text)
            if let kind = Self.namedResults.first(where: kinds.contains) {
                var line = "\(subject) \(kind.displayName)"
                if let position = Self.fielder(in: body) { line += " (\(position))" }
                if kinds.contains(.error) { line += " · 실책" }
                return line
            }
            return "\(subject) \(body)"
        }
        return text
    }

    private func runnerHeadline(from: String, name: String, body: String) -> String {
        let target = firstTargetBase(in: body)
        if body.contains("도루실패") || body.contains("도루 실패") {
            return "\(name) 도루 실패"
        }
        if body.contains("도루") {
            return target.map { "\(name) 도루(\(from)루 → \($0))" } ?? "\(name) 도루"
        }
        if body.contains("홈인") {
            return "\(name) 홈인"
        }
        if body.contains("아웃") {
            return "\(name) 아웃 (\(from)루)"
        }
        if let target, body.contains("진루") {
            return "\(name) 진루(\(from)루 → \(target))"
        }
        return "\(name) \(body)"
    }

    /// "도루로 2루까지 진루" → "2루"
    private func firstTargetBase(in body: String) -> String? {
        let range = NSRange(body.startIndex..., in: body)
        guard let match = Self.targetBaseRegex.firstMatch(in: body, range: range),
              let base = Range(match.range(at: 0), in: body) else { return nil }
        return String(body[base])
    }

    /// "좌익수 희생플라이 아웃" → "좌익수"
    private static func fielder(in body: String) -> String? {
        let first = body.split(separator: " ").first.map(String.init) ?? ""
        let positions = ["투수", "포수", "1루수", "2루수", "3루수", "유격수", "좌익수", "중견수", "우익수"]
        return positions.first { first.hasPrefix($0) }
    }
}
