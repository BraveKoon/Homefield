import Foundation

/// 한 팀의 선발 등판 기록과 다음 선발 예고.
///
/// 지난 등판은 중계의 투수 명단 첫 번째(그날 선발)에서 읽고, 다음 선발은 일정의 선발 예고에서 읽는다.
/// 둘 다 확인된 데이터만 쓰고, 다음 차례를 짐작해서 채우지 않는다.
public struct TeamStarters: Codable, Hashable, Sendable {
    /// 지난 선발 등판 한 번
    public struct Start: Codable, Hashable, Sendable, Identifiable {
        public var gameId: String
        public var date: Date?
        public var pitcher: Player
        public var opponentCode: String
        public var isHome: Bool

        public var id: String { gameId }

        public init(gameId: String, date: Date?, pitcher: Player, opponentCode: String, isHome: Bool) {
            self.gameId = gameId
            self.date = date
            self.pitcher = pitcher
            self.opponentCode = opponentCode
            self.isHome = isHome
        }
    }

    /// 아직 하지 않은 경기의 선발 예고
    public struct Upcoming: Codable, Hashable, Sendable {
        public var gameId: String
        public var date: Date?
        public var pitcher: String
        public var opponentCode: String
        public var isHome: Bool

        public init(gameId: String, date: Date?, pitcher: String, opponentCode: String, isHome: Bool) {
            self.gameId = gameId
            self.date = date
            self.pitcher = pitcher
            self.opponentCode = opponentCode
            self.isHome = isHome
        }
    }

    public var teamCode: String
    /// 최근 등판이 앞
    public var starts: [Start]
    /// 선발 예고 (제공자가 줄 때만)
    public var upcoming: Upcoming?
    public var updatedAt: Date

    public init(teamCode: String, starts: [Start] = [], upcoming: Upcoming? = nil, updatedAt: Date = Date()) {
        self.teamCode = teamCode
        self.starts = starts
        self.upcoming = upcoming
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        starts.isEmpty && upcoming == nil
    }

    /// 지난 등판에 나온 투수 (최근 순, 중복 없이)
    public var pitchers: [Player] {
        var seen = Set<String>()
        return starts.map(\.pitcher).filter { seen.insert($0.name).inserted }
    }
}

/// 한 팀의 선발 등판을 모은다
public struct StarterCollector: Sendable {
    public var provider: any GameDataProvider
    /// 며칠 전까지 거슬러 볼지
    public var lookbackDays: Int
    /// 몇 번의 등판까지 모을지
    public var maxStarts: Int
    /// 선발 예고를 며칠 앞까지 찾을지
    public var lookaheadDays: Int

    public init(provider: any GameDataProvider, lookbackDays: Int = 14, maxStarts: Int = 5, lookaheadDays: Int = 3) {
        self.provider = provider
        self.lookbackDays = lookbackDays
        self.maxStarts = maxStarts
        self.lookaheadDays = lookaheadDays
    }

    public func collect(teamCode: String, today: Date = Date(), calendar: Calendar = .current) async -> TeamStarters {
        var starts: [TeamStarters.Start] = []
        for back in 0...max(lookbackDays, 0) {
            guard starts.count < maxStarts,
                  let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let games = try? await provider.games(on: day)
            else { continue }
            for game in games where starts.count < maxStarts {
                guard let side = side(of: teamCode, in: game),
                      game.status == .live || game.status == .finished,
                      let snapshot = try? await provider.relay(gameId: game.id, inning: nil),
                      // 투수 명단 첫 번째가 그날 선발
                      let starter = snapshot.pitchers[side]?.first
                else { continue }
                starts.append(
                    TeamStarters.Start(
                        gameId: game.id,
                        date: game.startTime,
                        pitcher: starter,
                        opponentCode: game.team(for: side.opposite).code,
                        isHome: side == .home
                    )
                )
            }
        }
        return TeamStarters(
            teamCode: teamCode,
            starts: starts,
            upcoming: await upcoming(teamCode: teamCode, today: today, calendar: calendar)
        )
    }

    /// 아직 하지 않은 경기 중 가장 가까운 선발 예고
    private func upcoming(teamCode: String, today: Date, calendar: Calendar) async -> TeamStarters.Upcoming? {
        for ahead in 0...max(lookaheadDays, 0) {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: today),
                  let games = try? await provider.games(on: day)
            else { continue }
            let sorted = games.sorted { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }
            for game in sorted {
                guard game.status == .scheduled,
                      let side = side(of: teamCode, in: game),
                      let pitcher = game.starter(for: side)
                else { continue }
                return TeamStarters.Upcoming(
                    gameId: game.id,
                    date: game.startTime,
                    pitcher: pitcher,
                    opponentCode: game.team(for: side.opposite).code,
                    isHome: side == .home
                )
            }
        }
        return nil
    }

    private func side(of teamCode: String, in game: GameSummary) -> TeamSide? {
        if game.home.code == teamCode { return .home }
        if game.away.code == teamCode { return .away }
        return nil
    }
}
