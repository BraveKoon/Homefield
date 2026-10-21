import Foundation

/// 홈 화면 위젯에 보여 줄 한 팀의 경기: 오늘 경기, 없으면 가까운 다음 경기
public struct TeamGameFinder: Sendable {
    public struct Result: Hashable, Sendable {
        public var game: GameSummary
        /// 오늘 경기인지 (아니면 다음 경기 예고)
        public var isToday: Bool

        public init(game: GameSummary, isToday: Bool) {
            self.game = game
            self.isToday = isToday
        }
    }

    public var provider: any GameDataProvider
    public var lookaheadDays: Int

    public init(provider: any GameDataProvider, lookaheadDays: Int = 7) {
        self.provider = provider
        self.lookaheadDays = lookaheadDays
    }

    public func find(teamCode: String, now: Date = Date(), calendar: Calendar = .current) async throws -> Result? {
        for ahead in 0...lookaheadDays {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: now) else { continue }
            let games: [GameSummary]
            do {
                games = try await provider.games(on: day)
            } catch {
                // 오늘 일정을 못 받으면 다음 날 경기를 보여 주면 틀리니 실패로 돌린다
                if ahead == 0 { throw error }
                continue
            }
            let mine = games.filter { $0.home.code == teamCode || $0.away.code == teamCode }
            if let game = Self.pick(mine, now: now) {
                return Result(game: game, isToday: ahead == 0)
            }
        }
        return nil
    }

    /// 같은 날 여러 경기(더블헤더)면 진행 중 > 곧 시작 > 마지막에 끝난 경기 순으로 고른다
    static func pick(_ games: [GameSummary], now: Date) -> GameSummary? {
        let sorted = games.sorted { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }
        if let live = sorted.first(where: { $0.status == .live }) { return live }
        if let finished = sorted.last(where: { $0.status == .finished }),
           let next = sorted.first(where: { $0.status == .scheduled }),
           let start = next.startTime, start.timeIntervalSince(now) > 60 * 60 {
            // 1차전이 끝나고 2차전까지 한 시간 넘게 남았으면 1차전 결과를 먼저
            return finished
        }
        return sorted.first { $0.status == .scheduled }
            ?? sorted.last { $0.status == .finished }
            ?? sorted.first
    }

    /// 위젯을 다시 그릴 때: 경기 중 5분, 시작 전이면 시작 시각(멀면 3시간 뒤), 끝났으면 3시간 뒤
    public static func nextRefresh(for result: Result?, now: Date = Date()) -> Date {
        guard let result else { return now.addingTimeInterval(3 * 60 * 60) }
        let game = result.game
        switch game.status {
        case .live:
            return now.addingTimeInterval(5 * 60)
        case .scheduled:
            guard let start = game.startTime else { return now.addingTimeInterval(60 * 60) }
            if start <= now { return now.addingTimeInterval(5 * 60) }
            return min(start, now.addingTimeInterval(3 * 60 * 60))
        case .finished, .cancelled, .unknown:
            return now.addingTimeInterval(3 * 60 * 60)
        }
    }
}
