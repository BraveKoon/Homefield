import Foundation

/// 나레이션 대상이 되는 경기 상황
public enum PlayKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case flyOut
    case groundOut
    case lineOut
    case strikeout
    case doublePlay
    case sacrificeFly
    case sacrificeBunt
    case single
    case double
    case triple
    case homeRun
    case walk
    case intentionalWalk
    case hitByPitch
    case stolenBase
    case caughtStealing
    case run
    case error
    case wildPitch
    case passedBall
    case pitcherChange

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flyOut: "플라이아웃"
        case .groundOut: "땅볼 아웃"
        case .lineOut: "라인드라이브 아웃"
        case .strikeout: "삼진"
        case .doublePlay: "병살"
        case .sacrificeFly: "희생플라이"
        case .sacrificeBunt: "희생번트"
        case .single: "안타"
        case .double: "2루타"
        case .triple: "3루타"
        case .homeRun: "홈런"
        case .walk: "볼넷"
        case .intentionalWalk: "고의사구"
        case .hitByPitch: "몸에 맞는 공"
        case .stolenBase: "도루 성공"
        case .caughtStealing: "도루 실패"
        case .run: "득점"
        case .error: "실책"
        case .wildPitch: "폭투"
        case .passedBall: "포일"
        case .pitcherChange: "투수 교체"
        }
    }

    public var defaultNarration: String {
        switch self {
        case .flyOut: "플라이아웃!"
        case .groundOut: "땅볼 아웃!"
        case .lineOut: "라인드라이브 아웃!"
        case .strikeout: "삼진 아웃!"
        case .doublePlay: "병살타!"
        case .sacrificeFly: "희생플라이!"
        case .sacrificeBunt: "희생번트!"
        case .single: "안타!"
        case .double: "2루타!"
        case .triple: "3루타!"
        case .homeRun: "홈런!"
        case .walk: "볼넷!"
        case .intentionalWalk: "고의사구."
        case .hitByPitch: "몸에 맞는 공!"
        case .stolenBase: "도루 성공!"
        case .caughtStealing: "도루 실패!"
        case .run: "득점!"
        case .error: "실책!"
        case .wildPitch: "폭투!"
        case .passedBall: "포일!"
        case .pitcherChange: "투수 교체."
        }
    }

    public var emoji: String {
        switch self {
        case .homeRun: "💥"
        case .run: "🏠"
        case .stolenBase: "🏃"
        case .error: "⚠️"
        case .single, .double, .triple: "🟢"
        case .walk, .intentionalWalk, .hitByPitch: "🚶"
        case .pitcherChange: "🔄"
        case .wildPitch, .passedBall: "🌀"
        default: "🔴"
        }
    }

    /// 이 상황이 나오면 현재 타자의 타석이 끝난다 (응원가 중지)
    public var endsPlateAppearance: Bool {
        switch self {
        case .stolenBase, .caughtStealing, .run, .error, .wildPitch, .passedBall, .pitcherChange:
            false
        default:
            true
        }
    }
}
