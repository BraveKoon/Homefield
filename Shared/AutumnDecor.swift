import HomefieldCore
import SwiftUI

/// 가을야구 분위기: 단풍잎과 따뜻한 색 (앱·위젯 같이 쓴다)
enum AutumnStyle {
    static let orange = Color(hex: 0xE8772E)
    static let maple = Color(hex: 0xB83A1E)
    static let gold = Color(hex: 0xF2B33D)

    /// 앱 설정(App Group)을 따라 지금 가을 분위기인지
    static var isActive: Bool {
        AutumnBaseball.isActive(mode: SharedSettings.autumnMode)
    }

    static var warmGradient: LinearGradient {
        LinearGradient(colors: [orange, maple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct AutumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 가을야구 분위기를 보여 줄지
    var isAutumn: Bool {
        get { self[AutumnKey.self] }
        set { self[AutumnKey.self] = newValue }
    }
}

/// 흩날리는 단풍잎. animated 가 false 면(위젯·동작 줄이기) 제자리에 그린다.
struct FallingLeaves: View {
    var count = 14
    var animated = true
    var opacity = 0.55
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
                canvas(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(time: nil)
        }
    }

    private func canvas(time: TimeInterval?) -> some View {
        Canvas { context, size in
            let leaves = [Text("🍁"), Text("🍂")].map { context.resolve($0.font(.system(size: 22 * scale))) }
            for index in 0..<count {
                let seed = Self.random(index)
                let fall = time.map { CGFloat($0) * (14 + seed.speed * 22) } ?? 0
                let height = size.height + 40
                let y = (seed.y * height + fall).truncatingRemainder(dividingBy: height) - 20
                let sway = time.map { sin($0 * (0.5 + Double(seed.speed)) + Double(index)) * 14 } ?? 0
                let x = seed.x * size.width + CGFloat(sway)
                let spin = Angle.degrees(Double(seed.rotation) * 360 + (time ?? 0) * 25 * (index.isMultiple(of: 2) ? 1 : -1))

                var leaf = context
                leaf.opacity = opacity * (0.55 + 0.45 * Double(seed.size))
                leaf.translateBy(x: x, y: y)
                leaf.rotate(by: spin)
                leaf.scaleBy(x: 0.6 + seed.size * 0.7, y: 0.6 + seed.size * 0.7)
                leaf.draw(leaves[index % 2], at: .zero)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 잎마다 늘 같은 자리·크기 (0...1)
    private static func random(_ index: Int) -> (x: CGFloat, y: CGFloat, size: CGFloat, speed: CGFloat, rotation: CGFloat) {
        func value(_ salt: Int) -> CGFloat {
            var hash = UInt64(truncatingIfNeeded: index &* 2_654_435_761 &+ salt &* 40_503)
            hash ^= hash >> 13
            hash = hash &* 0x5bd1e995
            hash ^= hash >> 15
            return CGFloat(hash % 10_000) / 10_000
        }
        return (value(1), value(2), value(3), value(4), value(5))
    }
}

/// 로고 귀퉁이에 얹는 단풍잎
struct AutumnLeafBadge: View {
    let size: CGFloat

    var body: some View {
        Text("🍁")
            .font(.system(size: max(10, size * 0.36)))
            .rotationEffect(.degrees(-18))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .offset(x: size * 0.1, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
