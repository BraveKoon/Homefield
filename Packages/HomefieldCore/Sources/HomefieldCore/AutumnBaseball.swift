import Foundation

/// 가을야구(포스트시즌) 분위기를 켤지 정한다
public enum AutumnBaseball {
    public enum Mode: String, CaseIterable, Codable, Sendable, Identifiable {
        /// 포스트시즌 기간(10월 1일 ~ 11월 15일)에만
        case auto
        case on
        case off

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .auto: "가을야구 기간에만"
            case .on: "항상"
            case .off: "끄기"
            }
        }
    }

    /// KBO 포스트시즌은 보통 10월 초에 시작해 11월 초에 한국시리즈가 끝난다
    public static func isSeason(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        switch parts.month {
        case 10: return true
        case 11: return (parts.day ?? 1) <= 15
        default: return false
        }
    }

    public static func isActive(mode: Mode, date: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch mode {
        case .auto: isSeason(date, calendar: calendar)
        case .on: true
        case .off: false
        }
    }
}
