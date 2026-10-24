import Foundation
import HomefieldCore

/// 앱과 위젯이 같이 보는 설정 (App Group)
enum SharedSettings {
    static let appGroup = "group.com.bravekoon.homefield"

    private static let favoriteKey = "favoriteTeamCode"
    private static let autumnKey = "autumnMode"

    /// App Group 을 못 쓰면(서명에 그룹이 없으면) 각자 저장소를 쓰게 되어 위젯은 응원팀을 모른다
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// 앱에서 고른 응원팀
    static var favoriteTeamCode: String? {
        get { defaults?.string(forKey: favoriteKey) }
        set { defaults?.set(newValue, forKey: favoriteKey) }
    }

    /// 가을야구 분위기 (설정 → 가을야구 테마)
    static var autumnMode: AutumnBaseball.Mode {
        get { defaults?.string(forKey: autumnKey).flatMap(AutumnBaseball.Mode.init(rawValue:)) ?? .auto }
        set { defaults?.set(newValue.rawValue, forKey: autumnKey) }
    }
}
