import ActivityKit
import Foundation

/// 잠금화면·다이내믹 아일랜드 실시간 중계 (앱과 위젯 확장이 같이 쓴다)
struct GameActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var awayScore: Int?
        var homeScore: Int?
        /// "3회말", 경기 전이면 "18:30" 같은 상태 문구
        var title: String
        /// "경기 전" / "경기 중" / "경기 종료"
        var status: String
        var isLive: Bool
        var balls: Int
        var strikes: Int
        var outs: Int
        /// 1루, 2루, 3루 주자
        var bases: [Bool]
        var pitcher: String?
        var batter: String?
        /// 최근 중계 문장 (최신이 먼저, 최대 3개)
        var recentPlays: [String]
    }

    var gameId: String
    var awayCode: String
    var awayName: String
    var homeCode: String
    var homeName: String
}
