import Foundation

/// 포인트를 얻는 방법
public enum CardReward: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 하루에 한 번 앱을 열면
    case dailyVisit
    /// 경기 중계를 한 번 보면 (경기당 한 번)
    case watchGame
    /// 직관 인증 한 번
    case checkIn

    public var id: String { rawValue }

    public var points: Int {
        switch self {
        case .dailyVisit: 20
        case .watchGame: 50
        case .checkIn: 200
        }
    }

    public var displayName: String {
        switch self {
        case .dailyVisit: "매일 접속"
        case .watchGame: "경기 시청"
        case .checkIn: "직관 인증"
        }
    }
}

/// 포인트 지갑. 같은 항목을 두 번 주지 않도록 지급한 열쇠를 남긴다.
public struct CardWallet: Codable, Hashable, Sendable {
    public private(set) var points: Int
    /// 이미 지급한 적립 항목 ("dailyVisit-2026-10-25", "watchGame-<경기 번호>")
    public private(set) var awarded: Set<String>

    public init(points: Int = 0, awarded: Set<String> = []) {
        self.points = points
        self.awarded = awarded
    }

    /// 아직 안 준 적립이면 주고 true
    @discardableResult
    public mutating func award(_ reward: CardReward, key: String) -> Bool {
        let full = "\(reward.rawValue)-\(key)"
        guard awarded.insert(full).inserted else { return false }
        points += reward.points
        return true
    }

    public func canAfford(_ kind: CardPackKind) -> Bool {
        points >= kind.cost
    }

    /// 포인트가 모자라면 false
    @discardableResult
    public mutating func spend(_ amount: Int) -> Bool {
        guard amount >= 0, points >= amount else { return false }
        points -= amount
        return true
    }
}

/// 모은 카드와 응원 라인업. 기기 안에만 저장된다.
public struct CardCollection: Codable, Hashable, Sendable {
    /// 카드 id → 가진 장수
    public private(set) var counts: [String: Int]
    /// 카드 id → 뽑았을 때의 카드
    public private(set) var cards: [String: PlayerCard]
    /// 응원 라인업 9칸 (카드 id, 빈 칸은 nil)
    public private(set) var lineup: [String?]
    public var wallet: CardWallet
    /// 기본 카드팩을 마지막으로 받은 날
    public private(set) var lastDailyPack: Date?

    public static let lineupSize = 9

    public init(
        counts: [String: Int] = [:],
        cards: [String: PlayerCard] = [:],
        lineup: [String?] = Array(repeating: nil, count: CardCollection.lineupSize),
        wallet: CardWallet = CardWallet(),
        lastDailyPack: Date? = nil
    ) {
        self.counts = counts
        self.cards = cards
        self.lineup = lineup
        self.wallet = wallet
        self.lastDailyPack = lastDailyPack
    }

    // MARK: 카드

    /// 가지고 있는 카드 (등급 높은 순, 같으면 점수 순)
    public var owned: [PlayerCard] {
        cards.values.sorted {
            ($0.grade, $0.rating, $1.name) > ($1.grade, $1.rating, $0.name)
        }
    }

    public func count(of id: String) -> Int {
        counts[id] ?? 0
    }

    public func has(_ id: String) -> Bool {
        count(of: id) > 0
    }

    /// 처음 뽑은 카드면 true (중복이면 장수만 올린다)
    @discardableResult
    public mutating func add(_ card: PlayerCard) -> Bool {
        let isNew = !has(card.id)
        counts[card.id] = count(of: card.id) + 1
        // 기록이 더 새것이면 카드 정보를 갱신한다
        if isNew || (card.stats?.updatedAt ?? .distantPast) > (cards[card.id]?.stats?.updatedAt ?? .distantPast) {
            cards[card.id] = card
        }
        return isNew
    }

    public func cards(ofTeam code: String) -> [PlayerCard] {
        owned.filter { $0.teamCode == code }
    }

    public func cards(grade: CardGrade) -> [PlayerCard] {
        owned.filter { $0.grade == grade }
    }

    public var countsByGrade: [CardGrade: Int] {
        Dictionary(grouping: owned, by: \.grade).mapValues(\.count)
    }

    /// 도감을 채운 비율 (그 시즌 전체 카드 수 대비)
    public func completion(of pool: CardPool) -> Double {
        guard !pool.cards.isEmpty else { return 0 }
        let mine = pool.cards.filter { has($0.id) }.count
        return Double(mine) / Double(pool.cards.count)
    }

    // MARK: 응원 라인업

    public var lineupCards: [PlayerCard?] {
        normalizedLineup.map { $0.flatMap { cards[$0] } }
    }

    /// 저장된 라인업이 9칸이 아니거나 없는 카드가 들어 있어도 쓸 수 있게 다듬는다
    private var normalizedLineup: [String?] {
        var result = lineup.map { id in id.flatMap { has($0) ? $0 : nil } }
        if result.count < Self.lineupSize {
            result += Array(repeating: nil, count: Self.lineupSize - result.count)
        }
        return Array(result.prefix(Self.lineupSize))
    }

    /// 라인업에 넣는다. 같은 카드가 다른 칸에 있으면 그 칸을 비운다.
    public mutating func setLineup(_ cardId: String?, at slot: Int) {
        guard slot >= 0, slot < Self.lineupSize else { return }
        var next = normalizedLineup
        if let cardId {
            guard has(cardId) else { return }
            for (index, existing) in next.enumerated() where existing == cardId {
                next[index] = nil
            }
        }
        next[slot] = cardId
        lineup = next
    }

    /// 이 선수가 라인업에 있으면 그 카드 (타석에 섰을 때 화면에 띄운다)
    public func lineupCard(playerId: String) -> PlayerCard? {
        lineupCards.compactMap { $0 }.first { $0.playerId == playerId }
    }

    public func lineupCard(teamCode: String, name: String) -> PlayerCard? {
        lineupCards.compactMap { $0 }.first { $0.teamCode == teamCode && $0.name == name }
    }

    /// 라인업 카드 등급 합
    public var lineupPower: Int {
        lineupCards.compactMap { $0?.grade.rawValue }.reduce(0, +)
    }

    // MARK: 하루 한 번 기본 카드팩

    public func canOpenDailyPack(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let lastDailyPack else { return true }
        return !calendar.isDate(lastDailyPack, inSameDayAs: date)
    }

    public mutating func markDailyPackOpened(on date: Date = Date()) {
        lastDailyPack = date
    }

    /// 카드팩을 열 수 있는지 (기본은 하루 한 번, 나머지는 포인트)
    public func canOpen(_ kind: CardPackKind, on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        kind == .basic ? canOpenDailyPack(on: date, calendar: calendar) : wallet.canAfford(kind)
    }

    /// 카드팩을 열고 받은 카드를 넣는다. 열 수 없으면 nil.
    public mutating func open<G: RandomNumberGenerator>(
        _ kind: CardPackKind,
        from pool: CardPool,
        on date: Date = Date(),
        calendar: Calendar = .current,
        using generator: inout G
    ) -> [PlayerCard]? {
        guard canOpen(kind, on: date, calendar: calendar) else { return nil }
        let drawn = pool.open(kind, using: &generator)
        guard !drawn.isEmpty else { return nil }
        if kind == .basic {
            markDailyPackOpened(on: date)
        } else {
            guard wallet.spend(kind.cost) else { return nil }
        }
        for card in drawn { add(card) }
        return drawn
    }
}
