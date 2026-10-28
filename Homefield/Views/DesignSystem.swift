import SwiftUI

/// 앱 전체가 같이 쓰는 모양 값. 여기 숫자만 바꾸면 모든 화면이 따라간다.
enum AppStyle {
    /// 카드 모서리
    static let cardRadius: CGFloat = 18
    /// 작은 칸(알약, 버튼) 모서리
    static let smallRadius: CGFloat = 12
    /// 카드 안쪽 여백
    static let cardPadding: CGFloat = 16
    /// 화면 좌우 여백
    static let screenPadding: CGFloat = 16
    /// 카드 사이 간격
    static let stackSpacing: CGFloat = 12
    /// 테두리 선 (그림자 대신 얇은 선으로 띄운다)
    static let hairline: CGFloat = 0.5
}

extension Animation {
    /// 화면이 바뀔 때 (카드가 나타나고 사라질 때)
    static let appear = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// 눌렀을 때처럼 짧고 빠르게
    static let tap = Animation.spring(response: 0.26, dampingFraction: 0.74)
    /// 점수·숫자가 바뀔 때
    static let value = Animation.snappy(duration: 0.28)
}

/// 동작 줄이기를 켜면 움직임을 뺀다
struct ReducedMotionAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation

    func body(content: Content) -> some View {
        content.transaction { transaction in
            transaction.animation = reduceMotion ? nil : animation
        }
    }
}

extension View {
    /// 동작 줄이기를 지키는 애니메이션
    func gentleAnimation(_ animation: Animation = .appear) -> some View {
        modifier(ReducedMotionAnimation(animation: animation))
    }
}

/// 누르면 살짝 들어가는 버튼 (목록 카드에 쓴다)
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.tap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// 목록에서 차례로 하나씩 떠오르게 한다
struct AppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                    return
                }
                // 너무 길어지지 않게 앞 여섯 장까지만 차례를 둔다
                withAnimation(.appear.delay(Double(min(index, 6)) * 0.045)) { shown = true }
            }
    }
}

extension View {
    /// 목록 순서대로 떠오르는 등장
    func appearing(_ index: Int) -> some View {
        modifier(AppearModifier(index: index))
    }
}
