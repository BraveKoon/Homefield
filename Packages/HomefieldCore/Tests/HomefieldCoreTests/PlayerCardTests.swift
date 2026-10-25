import XCTest
@testable import HomefieldCore

final class PlayerCardTests: XCTestCase {
    private let season = 2026

    // MARK: 점수

    func testInningsPitchedParsing() {
        var stats = SeasonStats(playerId: "1", kind: .pitcher)
        stats.innings = "161 1/3"
        XCTAssertEqual(stats.inningsPitched ?? 0, 161.333, accuracy: 0.001)
        stats.innings = "69 2/3"
        XCTAssertEqual(stats.inningsPitched ?? 0, 69.667, accuracy: 0.001)
        stats.innings = "7"
        XCTAssertEqual(stats.inningsPitched, 7)
        stats.innings = nil
        XCTAssertNil(stats.inningsPitched)
        stats.innings = "-"
        XCTAssertNil(stats.inningsPitched)
    }

    func testBatterRatingRewardsPlayingTimeAndProduction() {
        let star = batter("1", atBats: 523, average: 0.338, onBase: 0.434, homeRuns: 40, rbi: 124, games: 139)
        let regular = batter("2", atBats: 480, average: 0.260, onBase: 0.320, homeRuns: 8, rbi: 45, games: 130)
        let bench = batter("3", atBats: 40, average: 0.250, onBase: 0.300, homeRuns: 1, rbi: 4, games: 25)
        // 성적이 좋은 주전이 가장 높고, 거의 못 나온 선수는 낮다
        XCTAssertGreaterThan(CardRating.rating(for: star), CardRating.rating(for: regular))
        XCTAssertGreaterThan(CardRating.rating(for: regular), CardRating.rating(for: bench))
        XCTAssertLessThanOrEqual(CardRating.rating(for: star), 1)
        XCTAssertGreaterThanOrEqual(CardRating.rating(for: bench), 0)
        XCTAssertEqual(CardRating.rating(for: nil), 0)
    }

    func testPitcherRatingCoversStarterAndCloser() {
        let ace = pitcher("1", innings: "161 1/3", era: 2.30, wins: 14, strikeouts: 160, games: 29)
        let closer = pitcher("2", innings: "60", era: 2.10, saves: 32, strikeouts: 70, games: 60)
        let mopUp = pitcher("3", innings: "12", era: 6.50, games: 9)
        // 마무리는 이닝이 적어도 세이브로 주전급으로 잡힌다
        XCTAssertGreaterThan(CardRating.rating(for: closer), CardRating.rating(for: mopUp))
        XCTAssertGreaterThan(CardRating.rating(for: ace), CardRating.rating(for: mopUp))
        XCTAssertGreaterThan(CardRating.rating(for: closer), 0.4)
    }

    // MARK: 등급

    func testGradesFollowRecordRank() {
        let pool = makePool(count: 200)
        let counts = pool.countsByGrade
        // 5성은 가장 적고 1성은 가장 많다
        XCTAssertEqual(counts[.five], 8)
        XCTAssertEqual(counts[.four], 24)
        XCTAssertGreaterThan(counts[.one] ?? 0, counts[.five] ?? 0)
        // 점수가 가장 높은 선수가 5성
        XCTAssertEqual(pool.cards.first?.grade, .five)
        XCTAssertEqual(pool.cards.last?.grade, .one)
        // 점수 내림차순
        XCTAssertEqual(pool.cards.map(\.rating), pool.cards.map(\.rating).sorted(by: >))
    }

    func testBarelyPlayedPlayersStayOneStar() {
        // 거의 못 나온 선수만 모인 작은 풀이면 순위가 높아도 1성
        let players = (0..<10).map { Player(id: "\($0)", name: "선수\($0)", teamCode: "LG") }
        let stats = players.reduce(into: [String: SeasonStats]()) { result, player in
            result[player.id] = batter(player.id, atBats: 3, average: 0.333, onBase: 0.333, homeRuns: 0, rbi: 1, games: 2)
        }
        let pool = CardPool(season: season, players: players, stats: stats)
        XCTAssertTrue(pool.cards.allSatisfy { $0.grade == .one })
    }

    func testSameRecordsGiveSameGrades() {
        let first = makePool(count: 50)
        let second = makePool(count: 50)
        XCTAssertEqual(first.cards.map(\.id), second.cards.map(\.id))
        XCTAssertEqual(first.cards.map(\.grade), second.cards.map(\.grade))
    }

    func testPoolDropsDuplicatePlayersAndUsesPositionForKind() {
        let players = [
            Player(id: "1", name: "김투수", teamCode: "LG", position: "투수"),
            Player(id: "1", name: "김투수", teamCode: "LG", position: "투수"),
            Player(id: "2", name: "박타자", teamCode: "LG", position: "유격수"),
        ]
        let pool = CardPool(season: season, players: players, stats: [:])
        XCTAssertEqual(pool.cards.count, 2)
        // 기록이 없으면 포지션으로 투수/타자를 가린다
        XCTAssertEqual(pool.cards.first { $0.playerId == "1" }?.kind, .pitcher)
        XCTAssertEqual(pool.cards.first { $0.playerId == "2" }?.kind, .batter)
    }

    // MARK: 카드팩

    func testPackContentsMatchTheirGrades() {
        let pool = makePool(count: 300)
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<60 {
            let basic = pool.open(.basic, using: &generator)
            XCTAssertEqual(basic.count, 3)
            XCTAssertTrue(basic.allSatisfy { $0.grade <= .three }, "기본 카드팩은 1~3성")

            let premium = pool.open(.premium, using: &generator)
            XCTAssertEqual(premium.count, 3)
            XCTAssertTrue(premium.allSatisfy { $0.grade >= .three }, "고급 카드팩은 3~5성")

            XCTAssertEqual(pool.open(.four, using: &generator).map(\.grade), [.four])
            XCTAssertEqual(pool.open(.five, using: &generator).map(\.grade), [.five])
        }
    }

    func testPackOddsAreRoughlyFollowed() {
        let pool = makePool(count: 300)
        var generator = SeededGenerator(seed: 7)
        var drawn: [CardGrade: Int] = [:]
        let packs = 2_000
        for _ in 0..<packs {
            for card in pool.open(.basic, using: &generator) {
                drawn[card.grade, default: 0] += 1
            }
        }
        let total = Double(packs * 3)
        XCTAssertEqual(Double(drawn[.one] ?? 0) / total, 0.60, accuracy: 0.05)
        XCTAssertEqual(Double(drawn[.two] ?? 0) / total, 0.30, accuracy: 0.05)
        XCTAssertEqual(Double(drawn[.three] ?? 0) / total, 0.10, accuracy: 0.05)
    }

    func testBetterPlayersComeOutMoreOftenInTheSameGrade() throws {
        // 같은 등급 안에서는 출전·성적 점수가 높은 선수가 더 자주 나온다
        let players = (0..<40).map { Player(id: "\($0)", name: "선수\($0)", teamCode: "LG") }
        var stats: [String: SeasonStats] = [:]
        for (index, player) in players.enumerated() {
            stats[player.id] = batter(
                player.id,
                atBats: 500 - index * 10,
                average: 0.330 - Double(index) * 0.003,
                onBase: 0.400,
                homeRuns: 30 - index / 2,
                rbi: 100 - index,
                games: 140
            )
        }
        let pool = CardPool(season: season, players: players, stats: stats)
        let threeStars = pool.cards(grade: .three)
        let best = try XCTUnwrap(threeStars.first)
        let worst = try XCTUnwrap(threeStars.last)
        var generator = SeededGenerator(seed: 99)
        var hits: [String: Int] = [:]
        for _ in 0..<4_000 {
            for card in pool.open(.premium, using: &generator) {
                hits[card.id, default: 0] += 1
            }
        }
        XCTAssertGreaterThan(hits[best.id] ?? 0, hits[worst.id] ?? 0)
    }

    func testEmptyGradeFallsBackToNearest() {
        // 기록이 없어 모두 1성인 풀에서 5성 카드팩을 열면 가장 가까운 등급으로 준다
        let players = (0..<5).map { Player(id: "\($0)", name: "선수\($0)", teamCode: "LG") }
        let pool = CardPool(season: season, players: players, stats: [:])
        var generator = SeededGenerator(seed: 1)
        let drawn = pool.open(.five, using: &generator)
        XCTAssertEqual(drawn.count, 1)
        XCTAssertEqual(drawn.first?.grade, .one)

        // 선수가 아예 없으면 빈 손
        let empty = CardPool(season: season, players: [], stats: [:])
        XCTAssertTrue(empty.open(.basic, using: &generator).isEmpty)
    }

    func testPackCostsAndOddsText() {
        XCTAssertEqual(CardPackKind.basic.cost, 0)
        XCTAssertGreaterThan(CardPackKind.five.cost, CardPackKind.four.cost)
        XCTAssertGreaterThan(CardPackKind.four.cost, CardPackKind.premium.cost)
        for kind in CardPackKind.allCases {
            XCTAssertEqual(kind.odds.values.reduce(0, +), 1, accuracy: 0.0001, "\(kind) 확률 합은 1")
        }
        XCTAssertEqual(CardPackKind.five.oddsText, "5성 100%")
        XCTAssertTrue(CardPackKind.premium.oddsText.contains("5성 3%"))
    }

    // MARK: 모음

    func testCollectionCountsDuplicates() {
        let pool = makePool(count: 50)
        let card = pool.cards[0]
        var collection = CardCollection()
        XCTAssertTrue(collection.add(card))
        XCTAssertFalse(collection.add(card), "두 번째는 중복")
        XCTAssertEqual(collection.count(of: card.id), 2)
        XCTAssertEqual(collection.owned.count, 1)
        XCTAssertEqual(collection.cards(ofTeam: card.teamCode).count, 1)
        XCTAssertEqual(collection.completion(of: pool), 1.0 / 50)
    }

    func testOpeningPacksSpendsPointsAndDailyPackIsOncePerDay() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let pool = makePool(count: 100)
        var generator = SeededGenerator(seed: 5)
        var collection = CardCollection()

        // 기본 카드팩은 공짜지만 하루 한 번
        XCTAssertTrue(collection.canOpen(.basic, on: today, calendar: calendar))
        XCTAssertEqual(collection.open(.basic, from: pool, on: today, calendar: calendar, using: &generator)?.count, 3)
        XCTAssertFalse(collection.canOpen(.basic, on: today, calendar: calendar))
        XCTAssertNil(collection.open(.basic, from: pool, on: today, calendar: calendar, using: &generator))
        XCTAssertNotNil(collection.open(.basic, from: pool, on: tomorrow, calendar: calendar, using: &generator))

        // 고급 카드팩은 포인트가 있어야 열린다
        XCTAssertFalse(collection.canOpen(.premium, on: today, calendar: calendar))
        XCTAssertNil(collection.open(.premium, from: pool, on: today, calendar: calendar, using: &generator))
        collection.wallet.award(.checkIn, key: "20261025LGHT")
        XCTAssertEqual(collection.wallet.points, 200)
        XCTAssertNotNil(collection.open(.premium, from: pool, on: today, calendar: calendar, using: &generator))
        XCTAssertEqual(collection.wallet.points, 200 - CardPackKind.premium.cost)
    }

    func testWalletGivesEachRewardOnce() {
        var wallet = CardWallet()
        XCTAssertTrue(wallet.award(.dailyVisit, key: "2026-10-25"))
        XCTAssertFalse(wallet.award(.dailyVisit, key: "2026-10-25"), "같은 날은 한 번만")
        XCTAssertTrue(wallet.award(.dailyVisit, key: "2026-10-26"))
        XCTAssertTrue(wallet.award(.watchGame, key: "20261025LGHT"))
        XCTAssertFalse(wallet.award(.watchGame, key: "20261025LGHT"), "같은 경기는 한 번만")
        XCTAssertEqual(wallet.points, CardReward.dailyVisit.points * 2 + CardReward.watchGame.points)
        XCTAssertFalse(wallet.spend(wallet.points + 1))
        XCTAssertTrue(wallet.spend(wallet.points))
        XCTAssertEqual(wallet.points, 0)
    }

    func testLineupHoldsNineCardsWithoutDuplicates() {
        let pool = makePool(count: 50)
        var collection = CardCollection()
        for card in pool.cards.prefix(3) { collection.add(card) }
        let cards = Array(pool.cards.prefix(3))

        collection.setLineup(cards[0].id, at: 0)
        collection.setLineup(cards[1].id, at: 1)
        XCTAssertEqual(collection.lineupCards[0]?.id, cards[0].id)
        XCTAssertEqual(collection.lineupCards.count, CardCollection.lineupSize)

        // 같은 카드를 다른 칸에 넣으면 앞 칸이 빈다
        collection.setLineup(cards[0].id, at: 5)
        XCTAssertNil(collection.lineupCards[0])
        XCTAssertEqual(collection.lineupCards[5]?.id, cards[0].id)

        // 없는 카드는 안 들어가고, 칸 밖은 무시한다
        collection.setLineup("없는카드", at: 2)
        XCTAssertNil(collection.lineupCards[2])
        collection.setLineup(cards[1].id, at: 99)
        XCTAssertEqual(collection.lineupCards[1]?.id, cards[1].id)

        // 비우기
        collection.setLineup(nil, at: 5)
        XCTAssertNil(collection.lineupCards[5])

        XCTAssertEqual(collection.lineupPower, cards[1].grade.rawValue)
        XCTAssertEqual(collection.lineupCard(playerId: cards[1].playerId)?.id, cards[1].id)
        XCTAssertEqual(collection.lineupCard(teamCode: cards[1].teamCode, name: cards[1].name)?.id, cards[1].id)
        XCTAssertNil(collection.lineupCard(playerId: "아무도아님"))
    }

    func testCollectionSurvivesSavingAndLoading() throws {
        let pool = makePool(count: 30)
        var collection = CardCollection()
        for card in pool.cards.prefix(4) { collection.add(card) }
        collection.setLineup(pool.cards[0].id, at: 3)
        collection.wallet.award(.watchGame, key: "20261025LGHT")
        collection.markDailyPackOpened(on: Date(timeIntervalSince1970: 1_790_000_000))

        let data = try JSONEncoder().encode(collection)
        let loaded = try JSONDecoder().decode(CardCollection.self, from: data)
        XCTAssertEqual(loaded, collection)
        XCTAssertEqual(loaded.lineupCards[3]?.id, pool.cards[0].id)
        XCTAssertEqual(loaded.wallet.points, CardReward.watchGame.points)
    }

    // MARK: 도우미

    /// 기록 시각을 고정해 둔다 (저장·불러오기 비교가 소수점 때문에 흔들리지 않게)
    private let recordedAt = Date(timeIntervalSince1970: 1_789_000_000)

    private func batter(_ id: String, atBats: Int, average: Double, onBase: Double, homeRuns: Int, rbi: Int, games: Int) -> SeasonStats {
        var stats = SeasonStats(playerId: id, kind: .batter, updatedAt: recordedAt)
        stats.atBats = atBats
        stats.average = average
        stats.onBase = onBase
        stats.homeRuns = homeRuns
        stats.rbi = rbi
        stats.games = games
        return stats
    }

    private func pitcher(_ id: String, innings: String, era: Double, wins: Int = 0, saves: Int = 0, strikeouts: Int = 0, games: Int) -> SeasonStats {
        var stats = SeasonStats(playerId: id, kind: .pitcher, updatedAt: recordedAt)
        stats.innings = innings
        stats.era = era
        stats.wins = wins
        stats.saves = saves
        stats.strikeouts = strikeouts
        stats.games = games
        return stats
    }

    /// 점수가 골고루 퍼진 선수 풀
    private func makePool(count: Int) -> CardPool {
        let teams = KBOTeams.all.map(\.code)
        let players = (0..<count).map { index in
            Player(id: "p\(index)", name: "선수\(String(format: "%03d", index))", teamCode: teams[index % teams.count])
        }
        var stats: [String: SeasonStats] = [:]
        for (index, player) in players.enumerated() {
            let share = Double(count - index) / Double(count)
            stats[player.id] = batter(
                player.id,
                atBats: Int(share * 550),
                average: 0.200 + share * 0.150,
                onBase: 0.280 + share * 0.150,
                homeRuns: Int(share * 40),
                rbi: Int(share * 120),
                games: Int(share * 144)
            )
        }
        return CardPool(season: season, players: players, stats: stats)
    }
}

/// 테스트에서 늘 같은 결과가 나오도록 하는 난수 발생기
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x4d59_5df4_d0f3_3173 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
