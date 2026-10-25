import Foundation

/// 카드팩 종류
public enum CardPackKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 그 해 선수만, 1~3성
    case basic
    /// 그 해 선수만, 3~5성
    case premium
    /// 4성 확정
    case four
    /// 5성 확정
    case five

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .basic: "기본 카드팩"
        case .premium: "고급 카드팩"
        case .four: "4성 카드팩"
        case .five: "5성 카드팩"
        }
    }

    public var summary: String {
        switch self {
        case .basic: "1~3성 카드 3장"
        case .premium: "3~5성 카드 3장"
        case .four: "4성 카드 1장 확정"
        case .five: "5성 카드 1장 확정"
        }
    }

    /// 한 팩에서 나오는 카드 수
    public var cardCount: Int {
        switch self {
        case .basic, .premium: 3
        case .four, .five: 1
        }
    }

    /// 포인트 값. 기본 카드팩은 하루 한 번 무료라서 0.
    public var cost: Int {
        switch self {
        case .basic: 0
        case .premium: 150
        case .four: 400
        case .five: 1000
        }
    }

    /// 등급별 확률 (합 1)
    public var odds: [CardGrade: Double] {
        switch self {
        case .basic: [.one: 0.60, .two: 0.30, .three: 0.10]
        case .premium: [.three: 0.80, .four: 0.17, .five: 0.03]
        case .four: [.four: 1]
        case .five: [.five: 1]
        }
    }

    /// 확률을 사람이 읽을 수 있게 (큰 등급부터)
    public var oddsText: String {
        odds.sorted { $0.key > $1.key }
            .map { "\($0.key.displayName) \(Self.percent($0.value))" }
            .joined(separator: " · ")
    }

    static func percent(_ value: Double) -> String {
        let percent = value * 100
        return percent < 1 ? String(format: "%.1f%%", percent) : "\(Int(percent.rounded()))%"
    }
}

/// 한 시즌의 카드 목록. 등급은 그해 기록 점수의 순위로 정한다.
public struct CardPool: Sendable {
    /// 점수가 높은 순
    public let cards: [PlayerCard]
    public let season: Int

    /// 위에서부터 몇 %까지 그 등급인지
    static let cutoffs: [(grade: CardGrade, limit: Double)] = [
        (.five, 0.04),
        (.four, 0.16),
        (.three, 0.40),
        (.two, 0.70),
    ]

    /// 이 점수 아래는 거의 못 나온 선수라 1성으로 둔다
    static let lowPlayingTime = 0.08

    public init(season: Int, players: [Player], stats: [String: SeasonStats]) {
        self.season = season
        // 같은 선수가 여러 번 들어와도 한 장만
        var seen = Set<String>()
        let unique = players.filter { seen.insert($0.id).inserted }
        let rated = unique
            .map { player -> (player: Player, stats: SeasonStats?, rating: Double) in
                let stat = stats[player.id]
                return (player, stat, CardRating.rating(for: stat))
            }
            // 점수가 같으면 이름 순 (같은 기록이면 늘 같은 등급이 나오도록)
            .sorted { ($0.rating, $1.player.name) > ($1.rating, $0.player.name) }

        let total = max(rated.count, 1)
        cards = rated.enumerated().map { index, item in
            let percentile = Double(index) / Double(total)
            let grade = item.rating < Self.lowPlayingTime ? .one : Self.grade(atPercentile: percentile)
            let kind = item.stats?.kind ?? (TeamRoster.Group(position: item.player.position) == .pitcher ? .pitcher : .batter)
            return PlayerCard(
                playerId: item.player.id,
                name: item.player.name,
                teamCode: item.player.teamCode,
                season: season,
                kind: kind,
                grade: grade,
                rating: item.rating,
                backNumber: item.player.backNumber,
                position: item.player.position,
                stats: item.stats
            )
        }
    }

    static func grade(atPercentile percentile: Double) -> CardGrade {
        cutoffs.first { percentile < $0.limit }?.grade ?? .one
    }

    public func cards(grade: CardGrade) -> [PlayerCard] {
        cards.filter { $0.grade == grade }
    }

    public var countsByGrade: [CardGrade: Int] {
        Dictionary(grouping: cards, by: \.grade).mapValues(\.count)
    }

    /// 카드팩 하나를 연다. 등급은 팩 확률로, 같은 등급 안에서는 출전·성적 점수가 높은 선수가 더 잘 나온다.
    public func open<G: RandomNumberGenerator>(_ kind: CardPackKind, using generator: inout G) -> [PlayerCard] {
        guard !cards.isEmpty else { return [] }
        return (0..<kind.cardCount).compactMap { _ in
            let grade = pickGrade(kind.odds, using: &generator)
            return pickCard(grade: grade, using: &generator)
        }
    }

    private func pickGrade<G: RandomNumberGenerator>(_ odds: [CardGrade: Double], using generator: inout G) -> CardGrade {
        let entries = odds.sorted { $0.key < $1.key }
        let total = entries.reduce(0) { $0 + $1.value }
        guard total > 0 else { return .one }
        var roll = Double.random(in: 0..<total, using: &generator)
        for entry in entries {
            roll -= entry.value
            if roll < 0 { return entry.key }
        }
        return entries.last?.key ?? .one
    }

    /// 그 등급에 선수가 없으면(시즌 초라 기록이 적을 때 등) 가장 가까운 등급에서 고른다
    private func pickCard<G: RandomNumberGenerator>(grade: CardGrade, using generator: inout G) -> PlayerCard? {
        let candidates = CardGrade.allCases
            .sorted { abs($0.rawValue - grade.rawValue) < abs($1.rawValue - grade.rawValue) }
        for candidate in candidates {
            let pool = cards(grade: candidate)
            if let picked = weightedPick(pool, using: &generator) { return picked }
        }
        return nil
    }

    private func weightedPick<G: RandomNumberGenerator>(_ pool: [PlayerCard], using generator: inout G) -> PlayerCard? {
        guard !pool.isEmpty else { return nil }
        // 기록이 적은 선수도 나올 수 있게 바닥 가중치를 둔다
        let weights = pool.map { 0.25 + $0.rating }
        let total = weights.reduce(0, +)
        var roll = Double.random(in: 0..<total, using: &generator)
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 { return pool[index] }
        }
        return pool.last
    }
}
