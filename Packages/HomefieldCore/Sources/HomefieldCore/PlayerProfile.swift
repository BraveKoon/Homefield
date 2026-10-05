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

/// 선수 정보: 팀 이력과 메모 (팀 이력은 KBO 공식 기록에서 채우고, JSON 으로도 가져올 수 있다)
public struct PlayerProfile: Codable, Hashable, Sendable {
    /// 팀 이력
    public var teamHistory: [TimelineEntry]
    public var memo: String?

    public init(teamHistory: [TimelineEntry] = [], memo: String? = nil) {
        self.teamHistory = teamHistory
        self.memo = memo
    }

    public var isEmpty: Bool {
        teamHistory.isEmpty && (memo ?? "").isEmpty
    }

    /// 다른 프로필에서 비어 있지 않은 항목만 덮어쓴다
    public mutating func merge(_ other: PlayerProfile) {
        if !other.teamHistory.isEmpty { teamHistory = other.teamHistory }
        if let memo = other.memo, !memo.isEmpty { self.memo = memo }
    }

    private enum CodingKeys: String, CodingKey {
        case teamHistory, memo
    }

    /// 예전 버전에 저장된 응원 동작·응원가 변천사 항목은 무시한다
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
}
