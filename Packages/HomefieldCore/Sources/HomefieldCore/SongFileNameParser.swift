import Foundation

/// 파일 이름에서 팀·선수·곡 종류를 읽는다.
///
/// 규칙 (구분자는 `_`):
/// - `SS_구자욱_등장곡.mp3` → 삼성 구자욱 등장곡
/// - `SS_구자욱_응원가.m4a` → 삼성 구자욱 응원가
/// - `SS_팀응원가.mp3` 또는 `SS_팀_응원가.mp3` → 삼성 팀 응원가
///
/// 팀은 코드(`SS`)나 이름(`삼성`, `삼성 라이온즈`)으로 쓸 수 있다.
public struct SongFileName: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case walkUp
        case cheer
        case teamCheer
    }

    public var teamCode: String
    /// 팀 응원가면 nil
    public var playerName: String?
    public var kind: Kind

    public init(teamCode: String, playerName: String?, kind: Kind) {
        self.teamCode = teamCode
        self.playerName = playerName
        self.kind = kind
    }
}

public enum SongFileNameParser {
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]

    public static func isAudio(_ fileName: String) -> Bool {
        audioExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    public static func parse(_ fileName: String) -> SongFileName? {
        // Mac 에서 만든 파일 이름은 한글이 자모로 분해(NFD)되어 있을 수 있다
        let normalized = fileName.precomposedStringWithCanonicalMapping
        let stem = (normalized as NSString).deletingPathExtension
        let tokens = stem.split(separator: "_").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard tokens.count >= 2, let teamCode = teamCode(for: tokens[0]) else { return nil }

        if tokens.count == 2 {
            // SS_팀응원가, SS_응원가
            let token = tokens[1]
            if isTeamCheer(token) || kind(for: token) == .cheer {
                return SongFileName(teamCode: teamCode, playerName: nil, kind: .teamCheer)
            }
            return nil
        }

        guard tokens.count == 3, let kind = kind(for: tokens[2]) else { return nil }
        let name = tokens[1]
        if name == "팀" || name.lowercased() == "team" {
            return kind == .cheer ? SongFileName(teamCode: teamCode, playerName: nil, kind: .teamCheer) : nil
        }
        return SongFileName(teamCode: teamCode, playerName: name, kind: kind)
    }

    /// 팀 코드·이름·별칭 → 팀 코드
    public static func teamCode(for token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()
        if let team = KBOTeams.all.first(where: { $0.code == upper || $0.name == trimmed }) {
            return team.code
        }
        if let code = aliases[upper] ?? aliases[trimmed] {
            return code
        }
        if let team = KBOTeams.all.first(where: { $0.name.hasPrefix(trimmed) }) {
            return team.code
        }
        // 목록에 없는 팀(데모 팀 등)은 2~4자 영문 코드면 그대로 쓴다
        if (2...4).contains(upper.count), upper.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return upper
        }
        return nil
    }

    private static let aliases: [String: String] = [
        "KIA": "HT", "기아": "HT",
        "SSG": "SK", "에스에스지": "SK",
        "키움": "WO", "넥센": "WO", "KIWOOM": "WO",
        "삼성": "SS", "두산": "OB", "롯데": "LT", "한화": "HH", "엘지": "LG",
    ]

    private static func isTeamCheer(_ token: String) -> Bool {
        ["팀응원가", "팀응원", "팀", "team", "teamcheer"].contains(token.lowercased())
    }

    private static func kind(for token: String) -> SongFileName.Kind? {
        let lower = token.lowercased()
        let walkUp = ["등장곡", "등장", "입장곡", "walkup", "bgm"]
        let cheer = ["응원가", "응원곡", "응원", "cheer", "chant"]
        // "응원가2" 처럼 뒤에 번호가 붙어도 인식
        if walkUp.contains(where: { lower.hasPrefix($0) }) { return .walkUp }
        if cheer.contains(where: { lower.hasPrefix($0) }) { return .cheer }
        return nil
    }
}
