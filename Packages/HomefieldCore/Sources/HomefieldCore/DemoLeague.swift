import Foundation

/// 가상 리그: 가상 팀 둘과 가상 선수들, 가상 시즌 기록.
/// 심사·소개용 데모 빌드가 실제 구단·선수 대신 쓴다. 실존 선수의 이름이나 기록을 쓰지 않는다.
public enum DemoLeague {
    public static let teams: [Team] = [DemoGameProvider.home, DemoGameProvider.away]

    /// 카드의 시즌
    public static let season = 2026

    public static func name(for code: String) -> String? {
        teams.first { $0.code == code }?.name
    }

    public static func contains(_ code: String) -> Bool {
        teams.contains { $0.code == code }
    }

    private struct Batter {
        var name: String
        var average: Double
        var atBats: Int
        var homeRuns: Int
        var rbi: Int
        var onBase: Double
    }

    private struct Pitcher {
        var name: String
        var number: String
        var era: Double
        var wins: Int
        var losses: Int
        var saves: Int
        var innings: String
        var strikeouts: Int
        var games: Int
    }

    /// 타순대로 (경기 중계의 라인업과 같은 이름·수비 위치)
    private static let positions = ["중견수", "2루수", "우익수", "1루수", "3루수", "좌익수", "포수", "유격수", "지명타자"]

    private static let homeBatters = [
        Batter(name: "한결", average: 0.318, atBats: 540, homeRuns: 12, rbi: 70, onBase: 0.395),
        Batter(name: "서지후", average: 0.305, atBats: 505, homeRuns: 8, rbi: 58, onBase: 0.389),
        Batter(name: "강두원", average: 0.342, atBats: 520, homeRuns: 34, rbi: 105, onBase: 0.421),
        Batter(name: "곽민재", average: 0.289, atBats: 498, homeRuns: 22, rbi: 82, onBase: 0.358),
        Batter(name: "유태오", average: 0.276, atBats: 470, homeRuns: 15, rbi: 66, onBase: 0.341),
        Batter(name: "장우진", average: 0.262, atBats: 452, homeRuns: 9, rbi: 48, onBase: 0.331),
        Batter(name: "민경수", average: 0.251, atBats: 410, homeRuns: 6, rbi: 39, onBase: 0.312),
        Batter(name: "도하람", average: 0.243, atBats: 380, homeRuns: 3, rbi: 31, onBase: 0.301),
        Batter(name: "임준표", average: 0.232, atBats: 300, homeRuns: 5, rbi: 28, onBase: 0.296),
    ]

    private static let awayBatters = [
        Batter(name: "강한별", average: 0.281, atBats: 525, homeRuns: 4, rbi: 41, onBase: 0.349),
        Batter(name: "오세진", average: 0.322, atBats: 548, homeRuns: 6, rbi: 54, onBase: 0.402),
        Batter(name: "문태양", average: 0.331, atBats: 515, homeRuns: 28, rbi: 96, onBase: 0.410),
        Batter(name: "백도윤", average: 0.298, atBats: 505, homeRuns: 25, rbi: 91, onBase: 0.366),
        Batter(name: "한재희", average: 0.255, atBats: 430, homeRuns: 7, rbi: 44, onBase: 0.322),
        Batter(name: "고세혁", average: 0.287, atBats: 490, homeRuns: 18, rbi: 77, onBase: 0.352),
        Batter(name: "최용구", average: 0.266, atBats: 468, homeRuns: 11, rbi: 55, onBase: 0.335),
        Batter(name: "남궁현", average: 0.241, atBats: 390, homeRuns: 2, rbi: 27, onBase: 0.298),
        Batter(name: "표정우", average: 0.228, atBats: 280, homeRuns: 1, rbi: 19, onBase: 0.284),
    ]

    private static let homePitchers = [
        Pitcher(name: "윤성현", number: "18", era: 2.85, wins: 15, losses: 6, saves: 0, innings: "182 1/3", strikeouts: 168, games: 30),
        Pitcher(name: "이세준", number: "41", era: 3.40, wins: 5, losses: 3, saves: 24, innings: "58 2/3", strikeouts: 71, games: 62),
        Pitcher(name: "주하준", number: "29", era: 4.10, wins: 9, losses: 8, saves: 0, innings: "140 2/3", strikeouts: 112, games: 27),
        Pitcher(name: "엄도현", number: "47", era: 3.95, wins: 4, losses: 2, saves: 2, innings: "64 1/3", strikeouts: 58, games: 58),
        Pitcher(name: "방지호", number: "35", era: 5.20, wins: 2, losses: 5, saves: 0, innings: "48", strikeouts: 39, games: 33),
    ]

    private static let awayPitchers = [
        Pitcher(name: "배준서", number: "21", era: 3.05, wins: 13, losses: 7, saves: 0, innings: "175 1/3", strikeouts: 155, games: 29),
        Pitcher(name: "석민우", number: "19", era: 3.75, wins: 3, losses: 4, saves: 31, innings: "55 1/3", strikeouts: 66, games: 60),
        Pitcher(name: "옥진호", number: "33", era: 4.30, wins: 8, losses: 9, saves: 0, innings: "145", strikeouts: 101, games: 28),
        Pitcher(name: "변태건", number: "45", era: 4.00, wins: 4, losses: 3, saves: 1, innings: "60 2/3", strikeouts: 52, games: 55),
        Pitcher(name: "마동혁", number: "51", era: 5.40, wins: 1, losses: 4, saves: 0, innings: "40 1/3", strikeouts: 33, games: 30),
    ]

    private static func playerId(_ team: Team, _ name: String) -> String {
        "\(team.code)-\(name)"
    }

    /// 두 팀의 가상 선수 (타자 9명 + 투수 5명씩)
    public static func players() -> [Player] {
        var result: [Player] = []
        for (team, batters, pitchers) in [
            (DemoGameProvider.home, homeBatters, homePitchers),
            (DemoGameProvider.away, awayBatters, awayPitchers),
        ] {
            for (index, batter) in batters.enumerated() {
                result.append(Player(
                    id: playerId(team, batter.name),
                    name: batter.name,
                    teamCode: team.code,
                    backNumber: String(index + 10),
                    battingOrder: index + 1,
                    position: positions[index]
                ))
            }
            for pitcher in pitchers {
                result.append(Player(
                    id: playerId(team, pitcher.name),
                    name: pitcher.name,
                    teamCode: team.code,
                    backNumber: pitcher.number,
                    position: "투수"
                ))
            }
        }
        return result
    }

    /// 팀별 1군 엔트리 (응원가 화면용)
    public static func rosters() -> [String: TeamRoster] {
        let all = players()
        return Dictionary(uniqueKeysWithValues: teams.map { team in
            (team.code, TeamRoster(
                teamCode: team.code,
                players: all.filter { $0.teamCode == team.code },
                gameId: DemoGameProvider.gameId,
                gameDate: nil
            ))
        })
    }

    /// 가상 시즌 기록 (선수 id → 기록). 카드 등급이 1성부터 5성까지 고르게 나오게 짠 값이다.
    public static func stats(updatedAt: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> [String: SeasonStats] {
        var result: [String: SeasonStats] = [:]
        for (team, batters, pitchers) in [
            (DemoGameProvider.home, homeBatters, homePitchers),
            (DemoGameProvider.away, awayBatters, awayPitchers),
        ] {
            for batter in batters {
                let id = playerId(team, batter.name)
                var stats = SeasonStats(playerId: id, kind: .batter, updatedAt: updatedAt)
                stats.average = batter.average
                stats.atBats = batter.atBats
                stats.hits = Int((batter.average * Double(batter.atBats)).rounded())
                stats.homeRuns = batter.homeRuns
                stats.rbi = batter.rbi
                stats.onBase = batter.onBase
                stats.games = 140
                result[id] = stats
            }
            for pitcher in pitchers {
                let id = playerId(team, pitcher.name)
                var stats = SeasonStats(playerId: id, kind: .pitcher, updatedAt: updatedAt)
                stats.era = pitcher.era
                stats.wins = pitcher.wins
                stats.losses = pitcher.losses
                stats.saves = pitcher.saves
                stats.innings = pitcher.innings
                stats.strikeouts = pitcher.strikeouts
                stats.games = pitcher.games
                result[id] = stats
            }
        }
        return result
    }

    /// 데모 빌드의 카드 목록
    public static func cardPool() -> CardPool {
        CardPool(season: season, players: players(), stats: stats())
    }
}
