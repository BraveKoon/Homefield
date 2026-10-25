import Foundation

/// 카드 등급. 1성이 가장 흔하고 5성이 가장 귀하다.
public enum CardGrade: Int, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case one = 1
    case two
    case three
    case four
    case five

    public var id: Int { rawValue }

    public var displayName: String { "\(rawValue)성" }

    public var stars: String { String(repeating: "★", count: rawValue) }

    public static func < (lhs: CardGrade, rhs: CardGrade) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 그 해 1군 선수 카드 한 장.
///
/// 등급과 뽑힐 확률은 모두 그 해 공식 기록(네이버 스포츠)으로 계산한다. 임의로 정하거나 지어내지 않는다.
public struct PlayerCard: Codable, Hashable, Sendable, Identifiable {
    /// 데이터 제공자의 선수 코드
    public var playerId: String
    public var name: String
    public var teamCode: String
    /// 카드의 연도 (2026 시즌 카드는 그 해 선수만 나온다)
    public var season: Int
    public var kind: SeasonStats.Kind
    public var grade: CardGrade
    /// 0...1. 출전 시간과 성적을 합친 값이라 같은 등급 안에서 뽑힐 확률로도 쓴다.
    public var rating: Double
    public var backNumber: String?
    public var position: String?
    /// 등급 근거가 된 그 해 기록 (카드에 그대로 보여 준다)
    public var stats: SeasonStats?

    public var id: String { "\(season)-\(playerId)" }

    public init(
        playerId: String,
        name: String,
        teamCode: String,
        season: Int,
        kind: SeasonStats.Kind,
        grade: CardGrade,
        rating: Double,
        backNumber: String? = nil,
        position: String? = nil,
        stats: SeasonStats? = nil
    ) {
        self.playerId = playerId
        self.name = name
        self.teamCode = teamCode
        self.season = season
        self.kind = kind
        self.grade = grade
        self.rating = rating
        self.backNumber = backNumber
        self.position = position
        self.stats = stats
    }
}

/// 공식 기록으로 선수의 카드 점수를 낸다.
///
/// 많이 나오는 선수(유명도)와 잘하는 선수(성적)가 모두 높게 나오도록, 출전 시간에 성적 가산점을 곱한다.
/// 유명도를 따로 지어내지 않고 확인된 기록만 쓴다.
public enum CardRating {
    /// 타자 규정타석 수준
    static let fullSeasonAtBats = 450.0
    /// 투수 규정이닝 수준
    static let fullSeasonInnings = 150.0

    /// 0...1
    public static func rating(for stats: SeasonStats?) -> Double {
        guard let stats else { return 0 }
        switch stats.kind {
        case .batter: return batter(stats)
        case .pitcher: return pitcher(stats)
        }
    }

    private static func batter(_ stats: SeasonStats) -> Double {
        let playingTime = clamp(Double(stats.atBats ?? 0) / fullSeasonAtBats)
        let average = scale(stats.average, from: 0.200, to: 0.350)
        let onBase = scale(stats.onBase, from: 0.280, to: 0.430)
        let homeRuns = clamp(Double(stats.homeRuns ?? 0) / 30)
        let rbi = clamp(Double(stats.rbi ?? 0) / 90)
        let quality = average * 0.3 + onBase * 0.2 + homeRuns * 0.3 + rbi * 0.2
        return combine(playingTime: playingTime, quality: quality)
    }

    private static func pitcher(_ stats: SeasonStats) -> Double {
        let starter = clamp((stats.inningsPitched ?? 0) / fullSeasonInnings)
        let closer = clamp(Double(stats.saves ?? 0) / 30)
        let appearances = clamp(Double(stats.games ?? 0) / 60)
        // 선발은 이닝, 마무리는 세이브, 중간 계투는 등판 수로 본다
        let playingTime = max(starter, closer * 0.9, appearances * 0.7)
        // 평균자책은 낮을수록 좋다
        let era = stats.era.map { scale(5.00 - $0, from: 0, to: 2.50) } ?? 0
        let wins = clamp(Double(stats.wins ?? 0) / 15)
        let strikeouts = clamp(Double(stats.strikeouts ?? 0) / 150)
        let quality = era * 0.45 + wins * 0.2 + strikeouts * 0.2 + closer * 0.15
        return combine(playingTime: playingTime, quality: quality)
    }

    /// 많이 나오면 기본 점수를 주고, 거기에 성적으로 가산한다
    private static func combine(playingTime: Double, quality: Double) -> Double {
        playingTime * (0.45 + 0.55 * clamp(quality))
    }

    private static func scale(_ value: Double?, from low: Double, to high: Double) -> Double {
        guard let value, high > low else { return 0 }
        return clamp((value - low) / (high - low))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
