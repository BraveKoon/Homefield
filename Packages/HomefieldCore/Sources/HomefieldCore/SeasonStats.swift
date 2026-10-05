import Foundation

/// 데이터 제공자가 알려 주는 선수의 이번 시즌 공식 기록
public struct SeasonStats: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case batter
        case pitcher
    }

    /// 제공자의 선수 코드
    public var playerId: String
    public var kind: Kind
    public var updatedAt: Date

    // 타자
    public var average: Double?
    public var atBats: Int?
    public var hits: Int?
    public var homeRuns: Int?
    public var rbi: Int?
    public var onBase: Double?

    public var games: Int?

    // 투수
    public var era: Double?
    public var wins: Int?
    public var losses: Int?
    public var saves: Int?
    /// "69 1/3" 처럼 표기된 이닝
    public var innings: String?
    public var strikeouts: Int?
    public var walks: Int?

    public init(playerId: String, kind: Kind, updatedAt: Date = Date()) {
        self.playerId = playerId
        self.kind = kind
        self.updatedAt = updatedAt
    }

    /// 날짜를 뺀 기록이 같은지 (같으면 다시 저장하지 않는다)
    public func sameNumbers(as other: SeasonStats) -> Bool {
        var copy = other
        copy.updatedAt = updatedAt
        return copy == self
    }

    public struct Item: Hashable, Sendable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
    }

    /// 화면에 보여 줄 (이름, 값) 목록
    public var displayItems: [Item] {
        var items: [Item] = []
        func add(_ label: String, _ value: String?) {
            if let value { items.append(Item(label: label, value: value)) }
        }
        switch kind {
        case .batter:
            add("타율", average.map(Self.rate))
            add("경기", games.map(String.init))
            add("타수", atBats.map(String.init))
            add("안타", hits.map(String.init))
            add("홈런", homeRuns.map(String.init))
            add("타점", rbi.map(String.init))
            add("출루율", onBase.map(Self.rate))
            add("볼넷", walks.map(String.init))
            add("삼진", strikeouts.map(String.init))
        case .pitcher:
            add("평균자책", era.map { String(format: "%.2f", $0) })
            add("경기", games.map(String.init))
            add("승", wins.map(String.init))
            add("패", losses.map(String.init))
            add("세이브", saves.map(String.init))
            add("이닝", innings)
            add("삼진", strikeouts.map(String.init))
            add("볼넷", walks.map(String.init))
        }
        return items
    }

    /// 0.3 → ".300", 1.0 → "1.000"
    static func rate(_ value: Double) -> String {
        let text = String(format: "%.3f", value)
        return text.hasPrefix("0.") ? String(text.dropFirst()) : text
    }
}
