import Foundation

/// 포인트를 얻는 방법
public enum CardReward: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 앱을 처음 받았을 때 한 번
    case welcome
    /// 하루에 한 번 앱을 열면
    case dailyVisit
    /// 경기 중계를 한 번 보면 (경기당 한 번)
    case watchGame
    /// 직관 인증 한 번
    case checkIn

    public var id: String { rawValue }

    public var points: Int {
        switch self {
        case .welcome: 3_000
        case .dailyVisit: 20
        case .watchGame: 50
        case .checkIn: 200
        }
    }

    public var displayName: String {
        switch self {
        case .welcome: "첫 선물"
        case .dailyVisit: "매일 접속"
        case .watchGame: "경기 시청"
        case .checkIn: "직관 인증"
        }
    }

    /// 되풀이해서 받을 수 있는 적립 (첫 선물은 한 번만)
    public static var recurring: [CardReward] {
        allCases.filter { $0 != .welcome }
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
        insert(key: "\(reward.rawValue)-\(key)", points: reward.points)
    }

    /// 열쇠 없이 포인트를 넣는다 (중복 카드 환불처럼 여러 번 할 수 있는 것)
    mutating func insert(points amount: Int) {
        guard amount > 0 else { return }
        points += amount
    }

    /// 처음 보는 열쇠면 포인트를 넣는다 (같은 적립을 두 번 주지 않는다)
    @discardableResult
    mutating func insert(key: String, points amount: Int) -> Bool {
        guard awarded.insert(key).inserted else { return false }
        points += amount
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

    /// 연속 뽑기 한 번에 여는 카드팩 수
    public static let bulkCount = 10

    /// 카드팩을 count 개 열 수 있는지. 기본 카드팩은 하루 한 번이라 한 개만.
    public func canOpen(_ kind: CardPackKind, count: Int, on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard count >= 1 else { return false }
        if kind == .basic { return count == 1 && canOpenDailyPack(on: date, calendar: calendar) }
        return wallet.points >= kind.cost * count
    }

    /// 카드팩을 열고 받은 카드를 넣는다. 열 수 없으면 nil.
    public mutating func open<G: RandomNumberGenerator>(
        _ kind: CardPackKind,
        from pool: CardPool,
        on date: Date = Date(),
        calendar: Calendar = .current,
        using generator: inout G
    ) -> [PlayerCard]? {
        open(kind, count: 1, from: pool, on: date, calendar: calendar, using: &generator)
    }

    /// 카드팩을 count 개 연다 (연속 뽑기). 포인트가 모자라면 한 개도 열지 않고 nil.
    public mutating func open<G: RandomNumberGenerator>(
        _ kind: CardPackKind,
        count: Int,
        from pool: CardPool,
        on date: Date = Date(),
        calendar: Calendar = .current,
        using generator: inout G
    ) -> [PlayerCard]? {
        guard canOpen(kind, count: count, on: date, calendar: calendar) else { return nil }
        var drawn: [PlayerCard] = []
        for _ in 0..<count {
            drawn += pool.open(kind, using: &generator)
        }
        guard !drawn.isEmpty else { return nil }
        if kind == .basic {
            markDailyPackOpened(on: date)
        } else {
            guard wallet.spend(kind.cost * count) else { return nil }
        }
        for card in drawn { add(card) }
        return drawn
    }
}

/// 포인트를 주는 코드 한 개
public struct CardCoupon: Hashable, Sendable {
    /// 사용자가 입력하는 코드
    public var code: String
    public var points: Int

    public init(code: String, points: Int) {
        self.code = code
        self.points = points
    }
}

public enum CardCoupons {
    public static let all: [CardCoupon] = [
        CardCoupon(code: "0609Bangjy!", points: 100_000),
    ]

    /// 앞뒤 빈칸과 대소문자는 넘어가 준다 (키보드가 첫 글자를 바꿀 수 있다)
    public static func coupon(for input: String) -> CardCoupon? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return all.first { $0.code.compare(cleaned, options: .caseInsensitive) == .orderedSame }
    }
}

public enum CardCouponError: LocalizedError, Equatable {
    case unknown
    case alreadyUsed

    public var errorDescription: String? {
        switch self {
        case .unknown: "없는 코드예요. 다시 확인해 주세요."
        case .alreadyUsed: "이미 사용한 코드예요."
        }
    }
}

public extension CardWallet {
    /// 코드를 쓰고 포인트를 받는다. 코드마다 한 번만 쓸 수 있다.
    @discardableResult
    mutating func redeem(code: String) throws -> CardCoupon {
        guard let coupon = CardCoupons.coupon(for: code) else { throw CardCouponError.unknown }
        guard insert(key: "coupon-\(coupon.code)", points: coupon.points) else { throw CardCouponError.alreadyUsed }
        return coupon
    }
}

/// 카드 목록을 어떤 기준으로 늘어놓을지
public enum CardSortField: String, Codable, CaseIterable, Sendable, Identifiable {
    case grade
    case team
    case name

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .grade: "등급"
        case .team: "팀"
        case .name: "가나다"
        }
    }

    /// 내림차순·오름차순 버튼에 쓸 이름
    public func orderName(descending: Bool) -> String {
        switch self {
        case .grade: descending ? "높은순" : "낮은순"
        case .team, .name: descending ? "역순" : "가나다순"
        }
    }
}

public struct CardSort: Codable, Hashable, Sendable {
    public var field: CardSortField
    public var isDescending: Bool

    public init(field: CardSortField = .grade, isDescending: Bool = true) {
        self.field = field
        self.isDescending = isDescending
    }

    public var displayName: String {
        "\(field.displayName) \(field.orderName(descending: isDescending))"
    }

    /// 한글 이름은 글자 순서가 그대로 가나다 순서라 그냥 견주어도 된다
    public func apply(to cards: [PlayerCard]) -> [PlayerCard] {
        cards.sorted(by: isBefore)
    }

    private func isBefore(_ left: PlayerCard, _ right: PlayerCard) -> Bool {
        switch field {
        case .grade:
            if left.grade != right.grade { return isDescending ? left.grade > right.grade : left.grade < right.grade }
            if left.rating != right.rating { return isDescending ? left.rating > right.rating : left.rating < right.rating }
            return left.name < right.name
        case .team:
            let leftTeam = Self.teamName(left.teamCode)
            let rightTeam = Self.teamName(right.teamCode)
            if leftTeam != rightTeam { return isDescending ? leftTeam > rightTeam : leftTeam < rightTeam }
            // 같은 팀 안에서는 등급 높은 선수를 위로
            if left.grade != right.grade { return left.grade > right.grade }
            return left.name < right.name
        case .name:
            if left.name != right.name { return isDescending ? left.name > right.name : left.name < right.name }
            return left.id < right.id
        }
    }

    static func teamName(_ code: String) -> String {
        KBOTeams.name(for: code) ?? code
    }
}

public extension CardCollection {
    /// 가진 카드를 고른 기준으로 늘어놓는다
    func owned(sortedBy sort: CardSort) -> [PlayerCard] {
        sort.apply(to: owned)
    }

    /// 이 카드가 라인업 몇 번 칸에 들어가 있는지 (없으면 nil)
    func lineupSlot(of cardId: String) -> Int? {
        lineupCards.firstIndex { $0?.id == cardId }
    }
}

public extension CardGrade {
    /// 중복 카드를 되팔 때 돌려받는 포인트.
    /// 카드팩 값보다 한참 낮게 둬서, 뽑고 되파는 것으로 포인트가 늘어나지 않게 한다.
    var refundPoints: Int {
        switch self {
        case .one: 5
        case .two: 10
        case .three: 25
        case .four: 60
        case .five: 150
        }
    }
}

public extension CardCollection {
    /// 되팔 수 있는 장수 (도감에 한 장은 남긴다)
    func spareCount(of id: String) -> Int {
        max(count(of: id) - 1, 0)
    }

    /// 중복으로 가진 카드
    var spares: [PlayerCard] {
        owned.filter { spareCount(of: $0.id) > 0 }
    }

    /// 중복을 모두 되팔면 받는 포인트
    var totalRefund: Int {
        spares.reduce(0) { $0 + $1.grade.refundPoints * spareCount(of: $1.id) }
    }

    /// 중복 카드를 되팔고 받은 포인트. 중복이 없으면 nil.
    @discardableResult
    mutating func refund(_ cardId: String, count: Int = 1) -> Int? {
        guard count >= 1, let card = cards[cardId], spareCount(of: cardId) >= count else { return nil }
        let points = card.grade.refundPoints * count
        counts[cardId] = self.count(of: cardId) - count
        wallet.insert(points: points)
        return points
    }

    /// 중복 카드를 모두 되팔고 받은 포인트
    @discardableResult
    mutating func refundAllSpares() -> Int {
        var total = 0
        for card in spares {
            total += refund(card.id, count: spareCount(of: card.id)) ?? 0
        }
        return total
    }
}
