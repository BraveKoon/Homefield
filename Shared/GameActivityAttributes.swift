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
        /// 지금 타석에서 던진 공 수 ("10구"). 모르면 nil.
        var pitchCount: Int? = nil
        /// 타자의 시즌 타율 (".356"). 공식 기록이 없으면 nil.
        var batterAverage: String? = nil
    }

    var gameId: String
    var awayCode: String
    var awayName: String
    var homeCode: String
    var homeName: String
    /// "창원" 같은 구장 이름
    var stadium: String? = nil
    /// 응원팀이 이 경기에 나오면 그 팀 코드 (MY TEAM 표시, 배경색)
    var favoriteCode: String? = nil
}

/// 홈 화면 위젯 종류 이름 (앱에서 위젯을 다시 그리라고 할 때 쓴다)
enum TeamGameWidgetKind {
    static let kind = "TeamGameWidget"
}
