import Foundation

/// 응원 라인업에 넣은 선수가 활약하면 주는 카드 포인트
public enum LineupBonus {
    public struct Award: Hashable, Sendable {
        public var cardId: String
        public var playerName: String
        /// "홈런", "삼진", "승리투수", "데일리 MVP"
        public var title: String
        public var points: Int
        /// 같은 상황을 두 번 주지 않으려고 쓰는 열쇠
        public var key: String

        public init(cardId: String, playerName: String, title: String, points: Int, key: String) {
            self.cardId = cardId
            self.playerName = playerName
            self.title = title
            self.points = points
            self.key = key
        }

        /// "홍길동 홈런 +50P"
        public var displayText: String {
            "\(playerName) \(title) +\(points)P"
        }
    }

    /// 타자(주자)가 받는 포인트
    public static func batterPoints(for kind: PlayKind) -> Int? {
        switch kind {
        case .homeRun: 50
        case .triple: 40
        case .double: 30
        case .single: 20
        case .stolenBase: 20
        case .run: 15
        case .sacrificeFly, .sacrificeBunt: 10
        case .walk, .hitByPitch: 5
        default: nil
        }
    }

    /// 마운드에 선 투수가 받는 포인트
    public static func pitcherPoints(for kind: PlayKind) -> Int? {
        switch kind {
        case .strikeout: 15
        case .doublePlay: 15
        default: nil
        }
    }

    /// 이 상황으로 라인업 카드가 받을 포인트. 라인업에 없는 선수면 nil.
    public static func award(
        for event: DetectedEvent,
        game: GameSummary,
        state: LiveGameState,
        collection: CardCollection
    ) -> Award? {
        guard case .play(let kind) = event.kind else { return nil }
        let battingSide = state.battingSide ?? event.side

        // 안타·홈런·도루처럼 타자나 주자가 한 일
        if let points = batterPoints(for: kind),
           let subject = event.subject,
           let side = battingSide,
           let card = collection.lineupCard(teamCode: game.team(for: side).code, name: subject) {
            return Award(cardId: card.id, playerName: card.name, title: kind.displayName, points: points, key: key(game: game, eventId: event.id, card: card))
        }

        // 삼진·병살처럼 투수가 한 일
        if let points = pitcherPoints(for: kind),
           let pitcher = state.pitcherName,
           let side = state.fieldingSide ?? battingSide?.opposite,
           let card = collection.lineupCard(teamCode: game.team(for: side).code, name: pitcher) {
            return Award(cardId: card.id, playerName: card.name, title: kind.displayName, points: points, key: key(game: game, eventId: event.id, card: card))
        }

        return nil
    }

    /// 중계 문장으로 주는 포인트 ("승리투수: 올러", "데일리 MVP KIA 전상현")
    public static func award(
        forRelayText text: String,
        entryId: String,
        game: GameSummary,
        collection: CardCollection
    ) -> Award? {
        guard let relay = RelayAward.parse(text) else { return nil }
        let card: PlayerCard?
        switch relay {
        case .winningPitcher(let name):
            // 이긴 팀 투수만 (점수가 갈리기 전에는 알 수 없다)
            card = winningSide(of: game).flatMap { collection.lineupCard(teamCode: game.team(for: $0).code, name: name) }
        case .dailyMVP(let teamCode, let name):
            card = collection.lineupCard(teamCode: teamCode, name: name)
        }
        guard let card else { return nil }
        return Award(
            cardId: card.id,
            playerName: card.name,
            title: relay.title,
            points: relay.points,
            key: key(game: game, eventId: entryId, card: card)
        )
    }

    /// 이긴 팀 (점수가 같거나 없으면 nil)
    static func winningSide(of game: GameSummary) -> TeamSide? {
        guard let home = game.homeScore, let away = game.awayScore, home != away else { return nil }
        return home > away ? .home : .away
    }

    private static func key(game: GameSummary, eventId: String, card: PlayerCard) -> String {
        "\(game.id)-\(eventId)-\(card.id)"
    }
}

/// 중계에 그대로 나오는 시상 문장
public enum RelayAward: Hashable, Sendable {
    /// "승리투수: 올러"
    case winningPitcher(name: String)
    /// "데일리 MVP KIA 전상현"
    case dailyMVP(teamCode: String, name: String)

    public var title: String {
        switch self {
        case .winningPitcher: "승리투수"
        case .dailyMVP: "데일리 MVP"
        }
    }

    public var points: Int {
        switch self {
        case .winningPitcher: 80
        case .dailyMVP: 100
        }
    }

    public static func parse(_ text: String) -> RelayAward? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = capture(#"^승리\s*투수\s*[:：]\s*(\S+)"#, in: line)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return .winningPitcher(name: name)
        }
        if let match = captures(#"데일리\s*MVP\s+(\S+)\s+(\S+)"#, in: line), match.count == 2,
           let code = KBOTeams.code(forShortName: match[0]) {
            return .dailyMVP(teamCode: code, name: match[1])
        }
        return nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text)?.first
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

public extension CardWallet {
    /// 라인업 선수 활약 포인트. 같은 상황은 한 번만 준다.
    @discardableResult
    mutating func award(lineupBonus award: LineupBonus.Award) -> Bool {
        insert(key: "play-\(award.key)", points: award.points)
    }
}
