import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// KBO 공식 홈페이지 선수 기록에서 읽은 경력: 학교·팀 경력 한 줄과 연도별 소속 팀
public struct KBOPlayerCareer: Codable, Hashable, Sendable {
    public struct Season: Codable, Hashable, Sendable {
        public var year: Int
        /// "KIA", "LG" 처럼 기록표에 나오는 팀 이름
        public var team: String

        public init(year: Int, team: String) {
            self.year = year
            self.team = team
        }
    }

    public var playerId: String
    public var name: String?
    /// 예: "가동초-청원중-휘문고-LG-경찰"
    public var career: String?
    /// 1군 기록이 있는 해마다 소속 팀 (오래된 해부터)
    public var seasons: [Season]
    public var fetchedAt: Date

    public init(playerId: String, name: String? = nil, career: String? = nil, seasons: [Season] = [], fetchedAt: Date = Date()) {
        self.playerId = playerId
        self.name = name
        self.career = career
        self.seasons = seasons
        self.fetchedAt = fetchedAt
    }

    /// 같은 팀이 이어진 해를 묶은 팀 이력. 예: [2015–2020 넥센 히어로즈, 2021–2026 KIA 타이거즈]
    public var teamHistory: [TimelineEntry] {
        var result: [TimelineEntry] = []
        var start: Season?
        var last: Season?
        func flush() {
            guard let start, let last else { return }
            let period = start.year == last.year ? "\(start.year)" : "\(start.year)–\(last.year)"
            result.append(TimelineEntry(period: period, text: Self.fullTeamName(start.team)))
        }
        for season in seasons.sorted(by: { $0.year < $1.year }) {
            if let current = start, current.team == season.team {
                last = season
            } else {
                flush()
                start = season
                last = season
            }
        }
        flush()
        return result
    }

    /// "KIA" → "KIA 타이거즈". 지금 구단 이름만 바꾸고 예전 이름(SK, 넥센, 해태 등)은 그 시절 이름 그대로 둔다.
    static func fullTeamName(_ team: String) -> String {
        currentShortNames[team].flatMap(KBOTeams.name(for:)) ?? team
    }

    private static let currentShortNames: [String: String] = [
        "LG": "LG", "KIA": "HT", "삼성": "SS", "두산": "OB", "롯데": "LT",
        "SSG": "SK", "한화": "HH", "NC": "NC", "KT": "KT", "키움": "WO",
    ]
}

public enum KBOPlayerPageParser {
    /// 선수 기록 페이지(Record/Player/{Hitter|Pitcher}Detail/Total.aspx) HTML 을 읽는다
    public static func parse(html: String, playerId: String, fetchedAt: Date = Date()) -> KBOPlayerCareer {
        KBOPlayerCareer(
            playerId: playerId,
            name: label("lblName", in: html),
            career: label("lblCareer", in: html),
            seasons: seasons(in: html),
            fetchedAt: fetchedAt
        )
    }

    /// <span id="..._playerProfile_lblCareer">가동초-청원중-휘문고-LG-경찰</span>
    static func label(_ suffix: String, in html: String) -> String? {
        let pattern = #"id="[^"]*playerProfile_\#(suffix)"[^>]*>([^<]*)<"#
        guard let text = firstCapture(pattern, in: html)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return decodeEntities(text)
    }

    /// 머리글에 "연도"와 "팀명"이 있는 표의 행들
    static func seasons(in html: String) -> [KBOPlayerCareer.Season] {
        for table in matches(#"<table(?:\s[^>]*)?>(.*?)</table>"#, in: html) {
            let headers = matches(#"<th(?:\s[^>]*)?>(.*?)</th>"#, in: table).map(stripTags)
            guard let yearColumn = headers.firstIndex(of: "연도"), let teamColumn = headers.firstIndex(of: "팀명") else { continue }
            var result: [KBOPlayerCareer.Season] = []
            for row in matches(#"<tr(?:\s[^>]*)?>(.*?)</tr>"#, in: table) {
                let cells = matches(#"<td(?:\s[^>]*)?>(.*?)</td>"#, in: row).map(stripTags)
                guard cells.count > max(yearColumn, teamColumn), let year = Int(cells[yearColumn]) else { continue }
                let team = cells[teamColumn]
                if !team.isEmpty { result.append(.init(year: year, team: team)) }
            }
            return result
        }
        return []
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first
    }

    private static func stripTags(_ text: String) -> String {
        decodeEntities(text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

/// KBO 공식 홈페이지에서 선수 경력을 받는다 (선수 코드는 네이버와 같다, 2026-10-05 확인)
public struct KBOPlayerService: Sendable {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// 투수/타자 페이지가 따로 있어서, 먼저 짐작한 쪽에 연도별 기록이 없으면 다른 쪽도 본다
    public func career(playerId: String, isPitcher: Bool) async throws -> KBOPlayerCareer {
        let kinds = isPitcher ? ["Pitcher", "Hitter"] : ["Hitter", "Pitcher"]
        var fallback: KBOPlayerCareer?
        for kind in kinds {
            let url = URL(string: "https://www.koreabaseball.com/Record/Player/\(kind)Detail/Total.aspx?playerId=\(playerId)")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw GameDataError.badStatus(http.statusCode)
            }
            let career = KBOPlayerPageParser.parse(html: String(decoding: data, as: UTF8.self), playerId: playerId)
            if !career.seasons.isEmpty { return career }
            if fallback == nil, career.name != nil { fallback = career }
        }
        guard let fallback else { throw GameDataError.emptyResponse }
        return fallback
    }
}
