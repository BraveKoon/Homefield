import Foundation

public enum TeamSide: String, Codable, Sendable, Hashable {
    case home
    case away

    public var opposite: TeamSide { self == .home ? .away : .home }
}

public struct Team: Hashable, Codable, Sendable {
    public var code: String
    public var name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public enum GameStatus: String, Codable, Sendable {
    case scheduled
    case live
    case finished
    case cancelled
    case unknown

    public var displayName: String {
        switch self {
        case .scheduled: "경기 전"
        case .live: "경기 중"
        case .finished: "경기 종료"
        case .cancelled: "취소"
        case .unknown: "-"
        }
    }
}

public struct GameSummary: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var home: Team
    public var away: Team
    public var homeScore: Int?
    public var awayScore: Int?
    public var status: GameStatus
    /// 제공자가 주는 진행 상황 문구 (예: "5회말")
    public var statusText: String?
    public var startTime: Date?
    public var stadium: String?

    public init(
        id: String,
        home: Team,
        away: Team,
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        status: GameStatus,
        statusText: String? = nil,
        startTime: Date? = nil,
        stadium: String? = nil
    ) {
        self.id = id
        self.home = home
        self.away = away
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.status = status
        self.statusText = statusText
        self.startTime = startTime
        self.stadium = stadium
    }

    public func team(for side: TeamSide) -> Team {
        side == .home ? home : away
    }
}

public struct Player: Identifiable, Hashable, Codable, Sendable {
    /// 제공자의 선수 코드. 없으면 "팀코드-이름".
    public var id: String
    public var name: String
    public var teamCode: String
    public var backNumber: String?
    public var battingOrder: Int?
    public var position: String?

    public init(
        id: String,
        name: String,
        teamCode: String,
        backNumber: String? = nil,
        battingOrder: Int? = nil,
        position: String? = nil
    ) {
        self.id = id
        self.name = name
        self.teamCode = teamCode
        self.backNumber = backNumber
        self.battingOrder = battingOrder
        self.position = position
    }
}

/// 문자 중계 한 줄. 데이터 제공자와 무관한 형태.
public struct RelayEntry: Hashable, Sendable {
    public var id: String
    /// 경기 전체에서 증가하는 정렬 키
    public var sequence: Int
    public var inning: Int?
    public var battingSide: TeamSide?
    public var text: String
    public var batterId: String?

    public init(
        id: String,
        sequence: Int,
        inning: Int? = nil,
        battingSide: TeamSide? = nil,
        text: String,
        batterId: String? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.inning = inning
        self.battingSide = battingSide
        self.text = text
        self.batterId = batterId
    }
}

public struct RelaySnapshot: Sendable {
    public var game: GameSummary?
    public var currentInning: Int?
    public var entries: [RelayEntry]
    public var lineups: [TeamSide: [Player]]

    public init(
        game: GameSummary? = nil,
        currentInning: Int? = nil,
        entries: [RelayEntry],
        lineups: [TeamSide: [Player]] = [:]
    ) {
        self.game = game
        self.currentInning = currentInning
        self.entries = entries
        self.lineups = lineups
    }
}

public enum KBOTeams {
    public static let all: [Team] = [
        Team(code: "LG", name: "LG 트윈스"),
        Team(code: "HT", name: "KIA 타이거즈"),
        Team(code: "SS", name: "삼성 라이온즈"),
        Team(code: "OB", name: "두산 베어스"),
        Team(code: "LT", name: "롯데 자이언츠"),
        Team(code: "SK", name: "SSG 랜더스"),
        Team(code: "HH", name: "한화 이글스"),
        Team(code: "NC", name: "NC 다이노스"),
        Team(code: "KT", name: "KT 위즈"),
        Team(code: "WO", name: "키움 히어로즈"),
    ]

    public static func name(for code: String) -> String? {
        all.first { $0.code == code }?.name
    }
}
