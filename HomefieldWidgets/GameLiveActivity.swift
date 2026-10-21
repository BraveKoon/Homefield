import ActivityKit
import SwiftUI
import WidgetKit

/// 잠금화면 알림 영역과 다이내믹 아일랜드(홈 화면 위쪽)에 보이는 실시간 중계
struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameActivityAttributes.self) { context in
            LockScreenGameView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandTeam(code: attributes.awayCode, score: state.awayScore, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTeam(code: attributes.homeCode, score: state.homeScore, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        StatusPill(title: state.title, isLive: state.isLive)
                        HStack(spacing: 10) {
                            BasesDiamond(bases: state.bases, size: 26)
                            CountDots(balls: state.balls, strikes: state.strikes, outs: state.outs, dotSize: 6)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if state.pitcher != nil || state.batter != nil {
                            MatchupLine(pitcher: state.pitcher, batter: state.batter)
                        }
                        if let latest = state.recentPlays.first {
                            PlayLine(text: latest, highlighted: true)
                        }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    TeamDot(code: attributes.awayCode, size: 18)
                    Text(state.awayScore.map(String.init) ?? "-")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                }
            } compactTrailing: {
                HStack(spacing: 4) {
                    Text(state.homeScore.map(String.init) ?? "-")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    TeamDot(code: attributes.homeCode, size: 18)
                }
            } minimal: {
                ZStack {
                    Circle().fill(TeamTheme.forTeam(attributes.favoriteCode ?? attributes.homeCode).primary.vivid)
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .keylineTint(TeamTheme.forTeam(attributes.favoriteCode ?? attributes.homeCode).primary.vivid)
        }
    }
}

// MARK: - 잠금화면

/// 잠금화면: 위는 점수판(팀·점수·이닝), 가운데는 볼카운트·주자·투타, 아래는 최근 중계
struct LockScreenGameView: View {
    let attributes: GameActivityAttributes
    let state: GameActivityAttributes.ContentState

    private var accent: Color {
        TeamTheme.forTeam(attributes.favoriteCode ?? attributes.homeCode).primary
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            HStack(alignment: .center, spacing: 0) {
                TeamColumn(code: attributes.awayCode, name: attributes.awayName)
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        ScoreText(score: state.awayScore, winning: (state.awayScore ?? 0) > (state.homeScore ?? 0))
                        Text(":")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        ScoreText(score: state.homeScore, winning: (state.homeScore ?? 0) > (state.awayScore ?? 0))
                    }
                    StatusPill(title: state.title, isLive: state.isLive)
                }
                .frame(minWidth: 130)
                TeamColumn(code: attributes.homeCode, name: attributes.homeName)
            }

            if state.isLive {
                Divider().overlay(.white.opacity(0.15))
                HStack(spacing: 12) {
                    CountDots(balls: state.balls, strikes: state.strikes, outs: state.outs, dotSize: 8)
                    MatchupLine(pitcher: state.pitcher, batter: state.batter)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BasesDiamond(bases: state.bases, size: 34)
                }
            }

            if !state.recentPlays.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(state.recentPlays.prefix(2).enumerated()), id: \.offset) { index, play in
                        PlayLine(text: play, highlighted: index == 0)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.95), Color.black.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 응원팀 짧은 이름을 크게 흐리게 깔아 둔다 (로고 대신)
                Text(TeamTheme.shortName(for: attributes.favoriteCode ?? attributes.homeCode))
                    .font(.system(size: 90, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.06))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 10, y: -12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let favorite = attributes.favoriteCode {
                TeamDot(code: favorite, size: 16)
                Text("MY TEAM")
                    .font(.caption2.weight(.black))
                    .tracking(1)
            } else {
                Image(systemName: "baseball.fill").font(.caption2)
                Text("홈구장")
                    .font(.caption2.weight(.black))
            }
            Spacer()
            if let stadium = attributes.stadium {
                Label(stadium, systemImage: "mappin.and.ellipse")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}

// MARK: - 부품

/// 팀 배지 + 이름 (잠금화면)
private struct TeamColumn: View {
    let code: String
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            TeamDot(code: code, size: 42)
            Text(name)
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScoreText: View {
    let score: Int?
    let winning: Bool

    var body: some View {
        Text(score.map(String.init) ?? "-")
            .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(winning ? .white : .white.opacity(0.7))
            .contentTransition(.numericText())
    }
}

/// 다이내믹 아일랜드 펼침: 팀 배지·짧은 이름·점수
private struct IslandTeam: View {
    let code: String
    let score: Int?
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 6) {
                if alignment == .leading { TeamDot(code: code, size: 22) }
                Text(TeamTheme.shortName(for: code))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                if alignment == .trailing { TeamDot(code: code, size: 22) }
            }
            Text(score.map(String.init) ?? "-")
                .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// 팀 색 동그라미 + 짧은 이름 (위젯은 네트워크 이미지를 못 써서 로고 대신)
struct TeamDot: View {
    let code: String
    var size: CGFloat = 24

    var body: some View {
        let theme = TeamTheme.forTeam(code)
        ZStack {
            Circle().fill(LinearGradient(colors: [theme.primary.vivid, theme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(1, size * 0.05))
            if size >= 20 {
                Text(TeamTheme.shortName(for: code))
                    .font(.system(size: size * 0.3, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// "LIVE 7회초" / "경기 종료" 알약
struct StatusPill: View {
    let title: String
    let isLive: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isLive {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("LIVE").font(.system(size: 10, weight: .black))
            }
            Text(title).font(.caption.weight(.bold)).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background((isLive ? Color.red : Color.white.opacity(0.2)), in: Capsule())
        .foregroundStyle(.white)
    }
}

/// 투수 · 타자
private struct MatchupLine: View {
    let pitcher: String?
    let batter: String?

    var body: some View {
        HStack(spacing: 6) {
            if let pitcher {
                Text("투수").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(pitcher).font(.caption.weight(.bold))
            }
            if pitcher != nil, batter != nil {
                Text("·").foregroundStyle(.white.opacity(0.4))
            }
            if let batter {
                Text("타자").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(batter).font(.caption.weight(.bold))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// 최근 중계 한 줄
private struct PlayLine: View {
    let text: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(highlighted ? Color.yellow : Color.white.opacity(0.35))
                .frame(width: 6, height: 6)
            Text(text)
                .font(highlighted ? .footnote.weight(.semibold) : .caption)
                .foregroundStyle(.white.opacity(highlighted ? 1 : 0.7))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, highlighted ? 6 : 3)
        .background(highlighted ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 1·2·3루 다이아몬드 (주자 있으면 노란색)
struct BasesDiamond: View {
    let bases: [Bool]
    var size: CGFloat = 30

    var body: some View {
        let base = size * 0.36
        ZStack {
            diamond(occupied(1), base).offset(y: -size * 0.24)
            diamond(occupied(2), base).offset(x: -size * 0.27, y: size * 0.06)
            diamond(occupied(0), base).offset(x: size * 0.27, y: size * 0.06)
        }
        .frame(width: size, height: size * 0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(runnersText)
    }

    private func occupied(_ index: Int) -> Bool {
        index < bases.count && bases[index]
    }

    private var runnersText: String {
        let runners = (0..<3).filter(occupied).map { "\($0 + 1)루" }
        return runners.isEmpty ? "주자 없음" : "주자 " + runners.joined(separator: ", ")
    }

    private func diamond(_ occupied: Bool, _ side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.15)
            .fill(occupied ? Color.yellow : Color.white.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: side * 0.15).stroke(Color.white.opacity(occupied ? 0 : 0.5), lineWidth: 1))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(45))
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
                    .fill(index < filled ? color : Color.white.opacity(0.22))
                    .frame(width: dotSize, height: dotSize)
            }
        }
    }
}

extension Color {
    /// 어두운 팀 색(두산·롯데·KT 남색·검정)도 검은 배경에서 보이도록 밝게
    var vivid: Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return Color(hue: hue, saturation: min(saturation, 0.85), brightness: max(brightness, 0.75))
    }
}
