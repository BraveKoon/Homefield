import HomefieldCore

/// 앱이 보여 주는 팀 목록. 일반 빌드는 KBO 10개 구단, 데모 빌드는 가상 팀 둘.
enum AppTeams {
    static var all: [Team] {
        BuildFlavor.isDemo ? DemoLeague.teams : KBOTeams.all
    }

    static func name(for code: String) -> String? {
        BuildFlavor.isDemo ? DemoLeague.name(for: code) : KBOTeams.name(for: code)
    }

    static func contains(_ code: String) -> Bool {
        name(for: code) != nil
    }
}
