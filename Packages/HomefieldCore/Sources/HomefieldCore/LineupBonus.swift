import Foundation

/// 응원 라인업에 넣은 선수가 활약하면 주는 카드 포인트
public enum LineupBonus {
    public struct Award: Hashable, Sendable {
        public var cardId: String
        public var playerName: String
        public var kind: PlayKind
        public var points: Int
        /// 같은 상황을 두 번 주지 않으려고 쓰는 열쇠
        public var key: String

        public init(cardId: String, playerName: String, kind: PlayKind, points: Int, key: String) {
            self.cardId = cardId
            self.playerName = playerName
            self.kind = kind
            self.points = points
            self.key = key
        }

        /// "홍길동 홈런 +50P"
        public var displayText: String {
            "\(playerName) \(kind.displayName) +\(points)P"
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
            return Award(cardId: card.id, playerName: card.name, kind: kind, points: points, key: key(game: game, event: event, card: card))
        }

        // 삼진·병살처럼 투수가 한 일
        if let points = pitcherPoints(for: kind),
           let pitcher = state.pitcherName,
           let side = state.fieldingSide ?? battingSide?.opposite,
           let card = collection.lineupCard(teamCode: game.team(for: side).code, name: pitcher) {
            return Award(cardId: card.id, playerName: card.name, kind: kind, points: points, key: key(game: game, event: event, card: card))
        }

        return nil
    }

    private static func key(game: GameSummary, event: DetectedEvent, card: PlayerCard) -> String {
        "\(game.id)-\(event.id)-\(card.id)"
    }
}

public extension CardWallet {
    /// 라인업 선수 활약 포인트. 같은 상황은 한 번만 준다.
    @discardableResult
    mutating func award(lineupBonus award: LineupBonus.Award) -> Bool {
        insert(key: "play-\(award.key)", points: award.points)
    }
}
