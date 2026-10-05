import Foundation

/// 기간 + 설명 한 줄 (응원가 변천사, 팀 이력)
public struct TimelineEntry: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    /// 예: "2015", "2012–2019"
    public var period: String
    public var text: String

    public init(period: String, text: String) {
        self.period = period
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case period
        case text
    }
}

/// 사용자가 입력하거나 JSON 으로 가져오는 선수 정보
public struct PlayerProfile: Codable, Hashable, Sendable {
    /// 응원 동작(율동) 순서
    public var moves: [String]
    /// 응원 구호 (가사 전체가 아닌 짧은 구호 권장)
    public var chant: String?
    /// 응원가 변천사
    public var cheerHistory: [TimelineEntry]
    /// 팀 이력
    public var teamHistory: [TimelineEntry]
    public var memo: String?

    public init(
        moves: [String] = [],
        chant: String? = nil,
        cheerHistory: [TimelineEntry] = [],
        teamHistory: [TimelineEntry] = [],
        memo: String? = nil
    ) {
        self.moves = moves
        self.chant = chant
        self.cheerHistory = cheerHistory
        self.teamHistory = teamHistory
        self.memo = memo
    }

    public var isEmpty: Bool {
        moves.isEmpty && (chant ?? "").isEmpty && cheerHistory.isEmpty && teamHistory.isEmpty && (memo ?? "").isEmpty
    }

    /// 다른 프로필에서 비어 있지 않은 항목만 덮어쓴다
    public mutating func merge(_ other: PlayerProfile) {
        if !other.moves.isEmpty { moves = other.moves }
        if let chant = other.chant, !chant.isEmpty { self.chant = chant }
        if !other.cheerHistory.isEmpty { cheerHistory = other.cheerHistory }
        if !other.teamHistory.isEmpty { teamHistory = other.teamHistory }
        if let memo = other.memo, !memo.isEmpty { self.memo = memo }
    }

    private enum CodingKeys: String, CodingKey {
        case moves, chant, cheerHistory, teamHistory, memo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moves = try container.decodeIfPresent([String].self, forKey: .moves) ?? []
        chant = try container.decodeIfPresent(String.self, forKey: .chant)
        cheerHistory = try container.decodeIfPresent([TimelineEntry].self, forKey: .cheerHistory) ?? []
        teamHistory = try container.decodeIfPresent([TimelineEntry].self, forKey: .teamHistory) ?? []
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
    }
}

/// 여러 선수 정보를 한 번에 가져오는 JSON 파일
///
/// ```json
/// {
///   "players": [
///     {
///       "team": "SS",
///       "name": "구자욱",
///       "moves": ["양손 들고 박수 두 번", "오른손 앞으로 뻗기"],
///       "chant": "구자욱 안타!",
///       "cheerHistory": [{ "period": "2015", "text": "첫 응원가" }],
///       "teamHistory": [{ "period": "2012–", "text": "삼성 라이온즈" }],
///       "memo": ""
///     }
///   ]
/// }
/// ```
public struct PlayerProfilesFile: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public var teamCode: String
        public var name: String
        public var profile: PlayerProfile

        private enum CodingKeys: String, CodingKey {
            case team, name
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let team = try container.decode(String.self, forKey: .team)
            guard let code = SongFileNameParser.teamCode(for: team) else {
                throw DecodingError.dataCorruptedError(forKey: .team, in: container, debugDescription: "알 수 없는 팀: \(team)")
            }
            teamCode = code
            name = try container.decode(String.self, forKey: .name)
                .precomposedStringWithCanonicalMapping
                .trimmingCharacters(in: .whitespaces)
            profile = try PlayerProfile(from: decoder)
        }
    }

    public var players: [Entry]

    public static func decode(_ data: Data) throws -> PlayerProfilesFile {
        try JSONDecoder().decode(PlayerProfilesFile.self, from: data)
    }

    /// 채워 넣을 수 있게 선수 목록으로 만든 JSON (이미 있는 정보는 그대로, 빈 항목은 빈 칸)
    public static func template(_ players: [(teamCode: String, name: String, profile: PlayerProfile)]) throws -> Data {
        struct Row: Encodable {
            let team: String
            let name: String
            let moves: [String]
            let chant: String
            let cheerHistory: [TimelineEntry]
            let teamHistory: [TimelineEntry]
            let memo: String
        }
        struct File: Encodable {
            let players: [Row]
        }
        let rows = players.map { player in
            Row(
                team: player.teamCode,
                name: player.name,
                moves: player.profile.moves,
                chant: player.profile.chant ?? "",
                cheerHistory: player.profile.cheerHistory,
                teamHistory: player.profile.teamHistory,
                memo: player.profile.memo ?? ""
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(File(players: rows))
    }
}
