import ActivityKit
import SwiftUI
import WidgetKit

/// 잠금화면 알림 영역과 다이내믹 아일랜드에 보이는 실시간 중계
struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameActivityAttributes.self) { context in
            LockScreenGameView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TeamScoreColumn(code: attributes.awayCode, name: attributes.awayName, score: state.awayScore, compact: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamScoreColumn(code: attributes.homeCode, name: attributes.homeName, score: state.homeScore, compact: true)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(state.title).font(.headline)
                        CountDots(balls: state.balls, strikes: state.strikes, outs: state.outs, dotSize: 7)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let latest = state.recentPlays.first {
                        Text(latest)
                            .font(.footnote)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            } compactLeading: {
                Text("\(TeamTheme.shortName(for: attributes.awayCode)) \(state.awayScore.map(String.init) ?? "-")")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(TeamTheme.forTeam(attributes.awayCode).primary.lighter)
            } compactTrailing: {
                Text("\(state.homeScore.map(String.init) ?? "-") \(TeamTheme.shortName(for: attributes.homeCode))")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(TeamTheme.forTeam(attributes.homeCode).primary.lighter)
            } minimal: {
                Text("\(state.awayScore.map(String.init) ?? "-"):\(state.homeScore.map(String.init) ?? "-")")
                    .font(.caption2.bold().monospacedDigit())
            }
            .keylineTint(TeamTheme.forTeam(attributes.homeCode).primary)
        }
    }
}

/// 잠금화면: 위는 점수판, 아래는 최근 중계 문장
///
/// 잠금화면 실시간 중계는 높이가 160pt 까지라 넘치면 위아래가 잘린다.
/// 점수판을 가로 한 줄로 두고 중계 문장은 두 줄만 보여 준다.
struct LockScreenGameView: View {
    let attributes: GameActivityAttributes
    let state: GameActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                LockScreenTeamSide(code: attributes.awayCode, name: attributes.awayName, score: state.awayScore, label: "원정", isHome: false)
                VStack(spacing: 2) {
                    Text(statusText)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background((state.isLive ? Color.red : Color.gray).opacity(0.85), in: Capsule())
                    CountDots(balls: state.balls, strikes: state.strikes, outs: state.outs, dotSize: 6, spacing: 2)
                    if let pitcher = state.pitcher {
                        Text("투수 \(pitcher)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .fixedSize()
                LockScreenTeamSide(code: attributes.homeCode, name: attributes.homeName, score: state.homeScore, label: "홈", isHome: true)
            }

            if !state.recentPlays.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.recentPlays.prefix(2).enumerated()), id: \.offset) { index, play in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(index == 0 ? Color.yellow : Color.white.opacity(0.4))
                                .frame(width: 5, height: 5)
                            Text(play)
                                .font(index == 0 ? .subheadline.weight(.semibold) : .caption)
                                .foregroundStyle(.white.opacity(index == 0 ? 1 : 0.75))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .foregroundStyle(.white)
        // 글자 크기를 크게 해 둔 사람도 160pt 안에 들어오게
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(12)
        .background {
            ZStack {
                LinearGradient(
                    colors: [TeamTheme.forTeam(attributes.awayCode).primary, TeamTheme.forTeam(attributes.homeCode).primary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                Color.black.opacity(0.35)
            }
        }
    }

    /// 경기 중이면 "3회말", 아니면 "경기 전 · 18:30", "경기 종료 · 9회말"
    private var statusText: String {
        if state.isLive || state.title == state.status { return state.title }
        return "\(state.status) · \(state.title)"
    }
}

/// 잠금화면 점수판 한쪽: 배지, 원정/홈과 팀 이름, 점수. 홈 팀은 좌우를 뒤집는다.
struct LockScreenTeamSide: View {
    let code: String
    let name: String
    let score: Int?
    let label: String
    let isHome: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isHome {
                scoreText
                Spacer(minLength: 0)
                nameStack
                TeamBadge(code: code, size: 30)
            } else {
                TeamBadge(code: code, size: 30)
                nameStack
                Spacer(minLength: 0)
                scoreText
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var nameStack: some View {
        VStack(alignment: isHome ? .trailing : .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
            Text(name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var scoreText: some View {
        Text(score.map(String.init) ?? "-")
            .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// 팀 배지(팀 색 + 짧은 이름), 원정/홈, 팀 이름, 점수
struct TeamScoreColumn: View {
    let code: String
    let name: String
    let score: Int?
    var label: String?
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            TeamBadge(code: code, size: compact ? 28 : 40)
            if let label {
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
            if !compact {
                Text(name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(score.map(String.init) ?? "-")
                .font(.system(size: compact ? 24 : 40, weight: .heavy, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

/// 팀 색 원 안에 짧은 팀 이름
struct TeamBadge: View {
    let code: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(TeamTheme.forTeam(code).gradient)
            Circle().stroke(.white.opacity(0.8), lineWidth: 1.5)
            Text(TeamTheme.shortName(for: code))
                .font(.system(size: size * 0.33, weight: .heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .padding(3)
        }
        .frame(width: size, height: size)
    }
}

/// B ●●○ / S ●○ / O ●○
struct CountDots: View {
    let balls: Int
    let strikes: Int
    let outs: Int
    var dotSize: CGFloat = 9
    var spacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            row("B", filled: balls, total: 3, color: .green)
            row("S", filled: strikes, total: 2, color: .yellow)
            row("O", filled: outs, total: 2, color: .red)
        }
        .font(.system(size: dotSize + 2, weight: .bold, design: .monospaced))
    }

    private func row(_ label: String, filled: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).frame(width: dotSize + 2, alignment: .leading)
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? color : Color.white.opacity(0.25))
                    .frame(width: dotSize, height: dotSize)
            }
        }
    }
}

private extension Color {
    /// 어두운 팀 색도 다이내믹 아일랜드(검은 배경)에서 보이도록 밝게
    var lighter: Color {
        Color(uiColor: UIColor(self).withAlphaComponent(1).lighter())
    }
}

private extension UIColor {
    func lighter() -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation * 0.8, brightness: max(brightness, 0.85), alpha: alpha)
    }
}
