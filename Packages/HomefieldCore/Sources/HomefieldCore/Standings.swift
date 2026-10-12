import Foundation

/// 팀 순위표 한 줄
public struct TeamStanding: Codable, Hashable, Sendable, Identifiable {
    public var teamCode: String
    public var teamName: String
    public var rank: Int
    public var games: Int
    public var wins: Int
    public var losses: Int
    public var draws: Int
    /// 승률 (0.647)
    public var winRate: Double
    /// 게임차 (1위는 0)
    public var gamesBehind: Double
    /// "10승", "2패"
    public var streak: String?
    /// 최근 5경기, 앞이 먼저 치른 경기 ("WWLWD")
    public var lastFive: String?

    public var id: String { teamCode }

    public init(
        teamCode: String,
        teamName: String,
        rank: Int,
        games: Int,
        wins: Int,
        losses: Int,
        draws: Int,
        winRate: Double,
        gamesBehind: Double,
        streak: String? = nil,
        lastFive: String? = nil
    ) {
        self.teamCode = teamCode
        self.teamName = teamName
        self.rank = rank
        self.games = games
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.winRate = winRate
        self.gamesBehind = gamesBehind
        self.streak = streak
        self.lastFive = lastFive
    }

    /// ".647"
    public var winRateText: String {
        let text = String(format: "%.3f", winRate)
        return text.hasPrefix("0.") ? String(text.dropFirst()) : text
    }

    /// "-" (1위), "3.5"
    public var gamesBehindText: String {
        guard gamesBehind > 0 else { return "-" }
        return gamesBehind.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(gamesBehind)) : String(format: "%.1f", gamesBehind)
    }
}
