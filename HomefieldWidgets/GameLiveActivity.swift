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
struct LockScreenGameView: View {
    let attributes: GameActivityAttributes
    let state: GameActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                TeamScoreColumn(code: attributes.awayCode, name: attributes.awayName, score: state.awayScore, label: "원정")
                VStack(spacing: 6) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    CountDots(balls: state.balls, strikes: state.strikes, outs: state.outs, dotSize: 9)
                    if let pitcher = state.pitcher {
                        Text("투수 \(pitcher)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Text(state.status)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background((state.isLive ? Color.red : Color.gray).opacity(0.85), in: Capsule())
                }
                .frame(minWidth: 96)
                TeamScoreColumn(code: attributes.homeCode, name: attributes.homeName, score: state.homeScore, label: "홈")
            }

            if !state.recentPlays.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(state.recentPlays.prefix(3).enumerated()), id: \.offset) { index, play in
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
                .padding(10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
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
            ZStack {
                Circle().fill(TeamTheme.forTeam(code).gradient)
                Circle().stroke(.white.opacity(0.8), lineWidth: 1.5)
                Text(TeamTheme.shortName(for: code))
                    .font(.system(size: compact ? 10 : 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .padding(3)
            }
            .frame(width: compact ? 28 : 40, height: compact ? 28 : 40)
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

/// B ●●○ / S ●○ / O ●○
struct CountDots: View {
    let balls: Int
    let strikes: Int
    let outs: Int
    var dotSize: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
