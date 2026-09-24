import Foundation

public struct DetectedEvent: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case batterUp(Player)
        case play(PlayKind)
    }

    public var id: String
    public var kind: Kind
    /// 원본 중계 문구
    public var text: String
    /// 문구의 주어 (타자 또는 주자 이름)
    public var subject: String?
    public var side: TeamSide?
    public var inning: Int?

    public init(
        id: String,
        kind: Kind,
        text: String,
        subject: String? = nil,
        side: TeamSide? = nil,
        inning: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.subject = subject
        self.side = side
        self.inning = inning
    }
}

/// 중계 스냅샷을 받아 새로 생긴 상황만 이벤트로 돌려준다.
///
/// 처음 호출될 때는 지난 기록을 다시 재생하지 않고, 현재 타석에 있는 타자만 알려준다.
public final class GameEventDetector {
    private let classifier = RelayTextClassifier()
    private var seen = Set<String>()
    private var primed = false
    private var game: GameSummary?
    private var lineups: [TeamSide: [Player]] = [:]

    public init() {}

    public func process(_ snapshot: RelaySnapshot) -> [DetectedEvent] {
        if let game = snapshot.game { self.game = game }
        for (side, players) in snapshot.lineups where !players.isEmpty {
            lineups[side] = players
        }

        let entries = snapshot.entries.sorted { $0.sequence < $1.sequence }
        let fresh = entries.filter { !seen.contains($0.id) }
        seen.formUnion(fresh.map(\.id))

        if !primed {
            primed = true
            return currentBatterEvents(in: entries)
        }
        return fresh.flatMap(events(for:))
    }

    private func events(for entry: RelayEntry) -> [DetectedEvent] {
        if let intro = classifier.batterIntro(in: entry.text) {
            let (player, side) = resolvePlayer(intro: intro, entry: entry)
            return [DetectedEvent(
                id: entry.id,
                kind: .batterUp(player),
                text: entry.text,
                subject: player.name,
                side: side,
                inning: entry.inning
            )]
        }
        let subject = classifier.subject(of: entry.text)
        return classifier.classify(entry.text).enumerated().map { index, kind in
            DetectedEvent(
                id: "\(entry.id)#\(index)",
                kind: .play(kind),
                text: entry.text,
                subject: subject,
                side: entry.battingSide,
                inning: entry.inning
            )
        }
    }

    /// 앱을 켠 시점에 타석에 있는 타자 (아직 결과가 안 나온 경우만)
    private func currentBatterEvents(in entries: [RelayEntry]) -> [DetectedEvent] {
        guard let introIndex = entries.lastIndex(where: { classifier.batterIntro(in: $0.text) != nil }) else {
            return []
        }
        let finished = entries[(introIndex + 1)...].contains { entry in
            classifier.classify(entry.text).contains(where: \.endsPlateAppearance)
        }
        return finished ? [] : events(for: entries[introIndex])
    }

    private func resolvePlayer(intro: RelayTextClassifier.BatterIntro, entry: RelayEntry) -> (Player, TeamSide?) {
        let sides: [TeamSide] = entry.battingSide.map { [$0, $0.opposite] } ?? [.away, .home]

        if let batterId = entry.batterId {
            for side in sides {
                if let player = lineups[side]?.first(where: { $0.id == batterId }) {
                    return (with(player, order: intro.order), side)
                }
            }
        }
        for side in sides {
            if let player = lineups[side]?.first(where: { $0.name == intro.name }) {
                return (with(player, order: intro.order), side)
            }
        }

        let side = entry.battingSide
        let teamCode = side.flatMap { game?.team(for: $0).code } ?? ""
        let player = Player(
            id: entry.batterId ?? "\(teamCode)-\(intro.name)",
            name: intro.name,
            teamCode: teamCode,
            battingOrder: intro.order
        )
        return (player, side)
    }

    private func with(_ player: Player, order: Int?) -> Player {
        var player = player
        if let order { player.battingOrder = order }
        return player
    }
}
