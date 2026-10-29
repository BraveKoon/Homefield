import Foundation

/// 중계의 투구 줄 ("10구 볼", "3구 헛스윙")에서 몇 번째 공인지 읽는다
public enum PitchCount {
    public static func number(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: #"^\d+(?=\s*구)"#, options: .regularExpression) else { return nil }
        return Int(trimmed[range])
    }

    /// 최신 줄이 앞인 중계에서 지금 타석의 투구 수. 타자 등장 줄을 만나면 거기서 멈춘다.
    /// - Parameter lines: (문장, 타자 등장 줄인지) 최신이 앞
    public static func current(in lines: [(text: String, isBatterIntro: Bool)]) -> Int? {
        for line in lines {
            if line.isBatterIntro { return nil }
            if let number = number(in: line.text) { return number }
        }
        return nil
    }
}
