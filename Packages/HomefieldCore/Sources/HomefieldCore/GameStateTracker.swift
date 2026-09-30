import Foundation

/// 수비 위치
public enum FieldPosition: String, CaseIterable, Codable, Sendable {
    case pitcher, catcher, first, second, third, shortstop, left, center, right

    public var shortName: String {
        switch self {
        case .pitcher: "투"
        case .catcher: "포"
        case .first: "1루"
        case .second: "2루"
        case .third: "3루"
        case .shortstop: "유"
        case .left: "좌"
        case .center: "중"
        case .right: "우"
        }
    }

    /// "좌익수", "좌", "선발투수", "SS" 같은 표기 → 수비 위치 (지명타자·대타 등은 nil)
    public init?(label: String) {
        let text = label.trimmingCharacters(in: .whitespaces)
        if text.contains("지명") || text.contains("대타") || text.contains("대주자") { return nil }
        let rules: [(FieldPosition, [String])] = [
            (.pitcher, ["투수", "투", "P"]),
            (.catcher, ["포수", "포", "C"]),
            (.first, ["1루", "1B"]),
            (.second, ["2루", "2B"]),
            (.third, ["3루", "3B"]),
            (.shortstop, ["유격", "유", "SS"]),
            (.left, ["좌익", "좌", "LF"]),
            (.center, ["중견", "중", "CF"]),
            (.right, ["우익", "우", "RF"]),
        ]
        // 긴 표기부터 확인 ("선발투수" → 투수, "1루수" → 1루)
        for (position, labels) in rules where labels.filter({ $0.count > 1 }).contains(where: { text.contains($0) }) {
            self = position
            return
        }
        for (position, labels) in rules where labels.contains(text) {
            self = position
            return
        }
        return nil
    }
}

/// 지금 경기 상황: 볼카운트, 아웃, 주자, 수비 위치, 투수
public struct LiveGameState: Equatable, Sendable {
    public var inning: Int?
    public var battingSide: TeamSide?
    public var balls = 0
    public var strikes = 0
    public var outs = 0
    /// [1루, 2루, 3루] 주자 이름. 이름을 모르면 "주자".
    public var bases: [String?] = [nil, nil, nil]
    public var batterName: String?
    /// 팀별 수비 위치 → 선수 이름
    public var defense: [TeamSide: [FieldPosition: String]] = [:]

    public init() {}

    public var fieldingSide: TeamSide? { battingSide?.opposite }

    public var fielders: [FieldPosition: String] {
        fieldingSide.flatMap { defense[$0] } ?? [:]
    }

    public var pitcherName: String? { fielders[.pitcher] }

    /// "3회말"
    public var halfInningTitle: String? {
        guard let inning, let battingSide else { return nil }
        return "\(inning)회\(battingSide == .away ? "초" : "말")"
    }
}

/// 문자중계 한 줄씩 따라가며 경기 상황을 계산한다.
///
/// 제공자가 볼카운트·아웃·주자를 직접 주면(`RelayEntry.state`) 그 값을 우선한다.
public final class GameStateTracker {
    public private(set) var state = LiveGameState()
    private let classifier = RelayTextClassifier()
    /// 병살 뒤에 나오는 주자 아웃 줄을 두 번 세지 않도록
    private var skipNextRunnerOut = false
    /// 선수 코드 → 이름 (제공자가 알려 주는 현재 투수 코드를 이름으로 바꿀 때)
    private var names: [String: String] = [:]

    private static let pitchRegex = try! NSRegularExpression(pattern: #"^\d+\s*구\s+(.+)$"#)
    private static let runnerRegex = try! NSRegularExpression(pattern: #"^([123])루주자\s+(\S+)\s*[:：]\s*(.*)$"#)
    private static let advanceRegex = try! NSRegularExpression(pattern: #"([123])루까지"#)
    private static let substitutionRegex = try! NSRegularExpression(
        pattern: #"^(\S+)\s+(\S+)\s*[:：]\s*(?:(\S+)\s+)?(\S+?)\s*\(으\)로\s*교체"#
    )

    public init() {}

    /// 라인업·투수 명단으로 수비 위치를 채운다 (이미 교체로 바뀐 위치는 유지)
    public func setLineups(_ lineups: [TeamSide: [Player]], pitchers: [TeamSide: [Player]]) {
        for player in lineups.values.flatMap({ $0 }) + pitchers.values.flatMap({ $0 }) {
            names[player.id] = player.name
        }
        for side in [TeamSide.home, .away] {
            var fielders = state.defense[side] ?? [:]
            for player in lineups[side] ?? [] {
                if let label = player.position, let position = FieldPosition(label: label), fielders[position] == nil {
                    fielders[position] = player.name
                }
            }
            if fielders[.pitcher] == nil, let starter = pitchers[side]?.first {
                fielders[.pitcher] = starter.name
            }
            if !fielders.isEmpty { state.defense[side] = fielders }
        }
    }

    public func apply(_ entries: [RelayEntry]) {
        for entry in entries.sorted(by: { $0.sequence < $1.sequence }) {
            apply(entry)
        }
    }

    private func apply(_ entry: RelayEntry) {
        if let inning = entry.inning, let side = entry.battingSide,
           inning != state.inning || side != state.battingSide {
            startHalf(inning: inning, side: side)
        }

        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let intro = classifier.batterIntro(in: text) {
            state.batterName = intro.name
            resetCount()
        } else if let pitch = firstCapture(Self.pitchRegex, in: text) {
            applyPitch(pitch)
        } else if applySubstitution(text) {
            // 선수 교체
        } else if let runner = runnerLine(text) {
            applyRunner(runner)
        } else {
            applyBatterResult(text)
        }

        if let provided = entry.state {
            override(with: provided)
        }
    }

    private func startHalf(inning: Int, side: TeamSide) {
        state.inning = inning
        state.battingSide = side
        state.outs = 0
        state.bases = [nil, nil, nil]
        state.batterName = nil
        skipNextRunnerOut = false
        resetCount()
    }

    private func resetCount() {
        state.balls = 0
        state.strikes = 0
    }

    private func applyPitch(_ body: String) {
        if body.contains("볼넷") {
            return
        } else if body.contains("파울") {
            state.strikes = min(state.strikes + 1, 2)
        } else if body.contains("스트라이크") || body.contains("헛스윙") {
            state.strikes = min(state.strikes + 1, 2)
        } else if body.contains("볼") {
            state.balls = min(state.balls + 1, 3)
        }
    }

    private func applyBatterResult(_ text: String) {
        let kinds = classifier.classify(text)
        guard !kinds.isEmpty else { return }
        let batter = classifier.subject(of: text) ?? state.batterName ?? "타자"

        for kind in kinds {
            switch kind {
            case .flyOut, .groundOut, .lineOut, .strikeout, .sacrificeFly, .sacrificeBunt:
                addOuts(1)
            case .doublePlay:
                addOuts(2)
                skipNextRunnerOut = true
            case .single:
                state.bases[0] = batter
            case .double:
                state.bases[1] = batter
            case .triple:
                state.bases[2] = batter
            case .homeRun:
                state.bases = [nil, nil, nil]
            case .walk, .intentionalWalk, .hitByPitch:
                state.bases[0] = batter
            case .error:
                if text.contains("출루") { state.bases[0] = batter }
            default:
                break
            }
        }
        if kinds.contains(where: \.endsPlateAppearance) || (kinds.contains(.error) && text.contains("출루")) {
            resetCount()
        }
    }

    private struct RunnerLine {
        let from: Int
        let name: String
        let body: String
    }

    private func runnerLine(_ text: String) -> RunnerLine? {
        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = Self.runnerRegex.firstMatch(in: text, range: range),
            let baseRange = Range(match.range(at: 1), in: text),
            let nameRange = Range(match.range(at: 2), in: text),
            let bodyRange = Range(match.range(at: 3), in: text),
            let base = Int(text[baseRange])
        else { return nil }
        return RunnerLine(from: base - 1, name: String(text[nameRange]), body: String(text[bodyRange]))
    }

    private func applyRunner(_ runner: RunnerLine) {
        func leave() {
            if state.bases[runner.from] == runner.name || state.bases[runner.from] == "주자" {
                state.bases[runner.from] = nil
            }
        }

        let kinds = classifier.classify("\(runner.name) : \(runner.body)")
        if runner.body.contains("홈인") {
            leave()
        } else if kinds.contains(.caughtStealing) || runner.body.contains("아웃") {
            leave()
            if skipNextRunnerOut && !kinds.contains(.caughtStealing) {
                skipNextRunnerOut = false
            } else {
                addOuts(1)
            }
        } else if let target = firstCapture(Self.advanceRegex, in: runner.body).flatMap(Int.init), (1...3).contains(target) {
            leave()
            state.bases[target - 1] = runner.name
        }
    }

    /// "투수 A : 투수 B (으)로 교체", "좌익수 A : 좌익수 B (으)로 교체"
    private func applySubstitution(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.substitutionRegex.firstMatch(in: text, range: range) else { return false }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        guard let oldLabel = group(1), let newName = group(4) else { return false }
        let label = group(3) ?? oldLabel
        // 수비 교체는 지금 수비하는 팀, 대타·대주자는 공격 팀이라 수비 위치에 영향 없음
        if let position = FieldPosition(label: label), let side = state.fieldingSide {
            state.defense[side, default: [:]][position] = newName
        }
        return true
    }

    private func addOuts(_ count: Int) {
        state.outs = min(state.outs + count, 3)
    }

    private func override(with provided: CountState) {
        if let balls = provided.balls { state.balls = balls }
        if let strikes = provided.strikes { state.strikes = strikes }
        if let outs = provided.outs { state.outs = outs }
        if let pitcherId = provided.pitcherId, let name = names[pitcherId], let side = state.fieldingSide {
            state.defense[side, default: [:]][.pitcher] = name
        }
        if let occupied = provided.basesOccupied, occupied.count == 3 {
            for index in 0..<3 {
                if !occupied[index] {
                    state.bases[index] = nil
                } else if state.bases[index] == nil {
                    state.bases[index] = "주자"
                }
            }
        }
    }

    private func firstCapture(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}
