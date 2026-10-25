import Foundation
import HomefieldCore
import Observation

/// 모은 카드, 포인트, 응원 라인업. 기기 안에만 저장된다.
@MainActor
@Observable
final class CardStore {
    private(set) var collection: CardCollection
    /// 그해 카드 목록 (1군 엔트리 + 공식 기록으로 만든다)
    private(set) var pool: CardPool?
    /// 방금 뽑은 카드 (카드팩 열기 화면에서 보여 준다)
    var lastOpened: [PlayerCard] = []
    /// 보고 있는 경기에서 라인업 선수가 받은 포인트
    private(set) var gameBonus = 0
    /// 가장 최근 라인업 활약 ("홍길동 홈런 +50P")
    private(set) var lastBonus: LineupBonus.Award?

    @ObservationIgnored private let storeURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("cards.json")
        collection = (try? JSONDecoder().decode(CardCollection.self, from: Data(contentsOf: storeURL))) ?? CardCollection()
        // 앱을 처음 받았으면 첫 선물
        award(.welcome, key: "install")
    }

    var points: Int { collection.wallet.points }

    var season: Int { pool?.season ?? Self.currentSeason() }

    var canOpenDailyPack: Bool {
        collection.canOpenDailyPack()
    }

    // MARK: 카드 목록

    /// 1군 엔트리와 시즌 기록으로 그해 카드 목록을 만든다. 기록이 바뀌면 등급도 따라 바뀐다.
    func refreshPool(library: SongLibrary) {
        let rosters = library.rosters.filter { SongLibrary.isKBOTeam($0.key) }
        guard !rosters.isEmpty else { return }
        let players = rosters.values.flatMap(\.players)
        // 엔트리를 받아 온 경기의 해를 시즌으로 본다 (비시즌에 지난해 카드가 되지 않도록)
        let season = rosters.values
            .compactMap(\.gameDate)
            .max()
            .map { Calendar.current.component(.year, from: $0) } ?? Self.currentSeason()
        pool = CardPool(season: season, players: players, stats: library.officialStats)
    }

    private static func currentSeason() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    // MARK: 포인트

    /// 하루에 한 번 앱을 열면
    func awardDailyVisit(on date: Date = Date()) {
        award(.dailyVisit, key: Self.dayKey(date))
    }

    /// 경기 중계를 보면 (경기당 한 번)
    func awardWatching(gameId: String) {
        award(.watchGame, key: gameId)
    }

    /// 응원 라인업에 넣은 선수가 활약하면 포인트를 준다
    func award(lineupBonus award: LineupBonus.Award) {
        guard collection.wallet.award(lineupBonus: award) else { return }
        gameBonus += award.points
        lastBonus = award
        save()
    }

    /// 다른 경기를 보기 시작하면 이 경기 보너스를 0으로
    func resetGameBonus() {
        gameBonus = 0
        lastBonus = nil
    }

    /// 직관 인증 기록을 포인트로 바꾼다. 이미 준 인증은 건너뛴다.
    func syncCheckIns(_ checkIns: [CheckIn]) {
        var changed = false
        for checkIn in checkIns {
            if collection.wallet.award(.checkIn, key: checkIn.id.uuidString) { changed = true }
        }
        if changed { save() }
    }

    /// 코드를 써서 포인트를 받는다
    @discardableResult
    func redeem(code: String) throws -> CardCoupon {
        let coupon = try collection.wallet.redeem(code: code)
        save()
        return coupon
    }

    private func award(_ reward: CardReward, key: String) {
        if collection.wallet.award(reward, key: key) { save() }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    // MARK: 카드팩

    func canOpen(_ kind: CardPackKind, count: Int = 1) -> Bool {
        pool != nil && collection.canOpen(kind, count: count)
    }

    /// 카드팩을 count 개 열고 받은 카드를 돌려준다. 못 열면 nil.
    @discardableResult
    func open(_ kind: CardPackKind, count: Int = 1) -> [PlayerCard]? {
        guard let pool else { return nil }
        var generator = SystemRandomNumberGenerator()
        guard let drawn = collection.open(kind, count: count, from: pool, using: &generator) else { return nil }
        lastOpened = drawn
        save()
        return drawn
    }

    /// 이 카드가 처음 나온 것인지 (카드팩 열기 화면에서 NEW 표시)
    func isSingleCopy(_ card: PlayerCard) -> Bool {
        collection.count(of: card.id) == 1
    }

    // MARK: 응원 라인업

    func setLineup(_ cardId: String?, at slot: Int) {
        collection.setLineup(cardId, at: slot)
        save()
    }

    /// 타석에 선 선수의 라인업 카드
    func lineupCard(for player: Player) -> PlayerCard? {
        collection.lineupCard(playerId: player.id)
            ?? collection.lineupCard(teamCode: player.teamCode, name: player.name)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(collection) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
