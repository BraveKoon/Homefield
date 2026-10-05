import SwiftUI

/// 응원팀 색으로 앱 분위기를 바꾼다
struct TeamTheme {
    let primary: Color
    let secondary: Color

    /// 앱 기본 (응원팀 없음)
    static let `default` = TeamTheme(primary: Color(hex: 0xCC1C29), secondary: Color(hex: 0x12204A))

    static func forTeam(_ code: String?) -> TeamTheme {
        guard let code, let theme = themes[code] else { return .default }
        return theme
    }

    private static let themes: [String: TeamTheme] = [
        "LG": TeamTheme(primary: Color(hex: 0xC30452), secondary: Color(hex: 0x000000)),
        "HT": TeamTheme(primary: Color(hex: 0xEA0029), secondary: Color(hex: 0x06141F)),
        "SS": TeamTheme(primary: Color(hex: 0x074CA1), secondary: Color(hex: 0x0B2242)),
        "OB": TeamTheme(primary: Color(hex: 0x1A1748), secondary: Color(hex: 0xED1C24)),
        "LT": TeamTheme(primary: Color(hex: 0x041E42), secondary: Color(hex: 0xD00F31)),
        "SK": TeamTheme(primary: Color(hex: 0xCE0E2D), secondary: Color(hex: 0x333333)),
        "HH": TeamTheme(primary: Color(hex: 0xFF6600), secondary: Color(hex: 0x07111F)),
        "NC": TeamTheme(primary: Color(hex: 0x315288), secondary: Color(hex: 0xAF917B)),
        "KT": TeamTheme(primary: Color(hex: 0x1B1B1B), secondary: Color(hex: 0xEB1C24)),
        "WO": TeamTheme(primary: Color(hex: 0x820024), secondary: Color(hex: 0x3A0D16)),
        "DRM": TeamTheme(primary: Color(hex: 0x1F6F4A), secondary: Color(hex: 0x0E2A1C)),
    ]

    /// 배지에 넣을 짧은 팀 이름
    static func shortName(for code: String) -> String {
        shortNames[code] ?? String(code.prefix(3))
    }

    private static let shortNames: [String: String] = [
        "LG": "LG", "HT": "KIA", "SS": "삼성", "OB": "두산", "LT": "롯데",
        "SK": "SSG", "HH": "한화", "NC": "NC", "KT": "KT", "WO": "키움",
    ]

    /// 짙은 배경에서 쓸 그라데이션
    var gradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct TeamThemeKey: EnvironmentKey {
    static let defaultValue = TeamTheme.default
}

extension EnvironmentValues {
    var teamTheme: TeamTheme {
        get { self[TeamThemeKey.self] }
        set { self[TeamThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
