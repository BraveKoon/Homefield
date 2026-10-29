import ActivityKit
import SwiftUI
import WidgetKit

/// 잠금화면 알림 영역과 다이내믹 아일랜드(홈 화면 위쪽)에 보이는 실시간 중계
struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameActivityAttributes.self) { context in
            LockScreenGameView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(TeamTheme.forTeam(context.attributes.favoriteCode ?? context.attributes.homeCode).primary.deep)
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

/// 잠금화면: 한 장짜리 점수판.
/// 1줄 팀·점수·주자, 2줄 투수·이닝·타자, 3줄 투구 수·볼카운트·타율, 맨 아래 최근 중계 한 줄.
struct LockScreenGameView: View {
    let attributes: GameActivityAttributes
    let state: GameActivityAttributes.ContentState

    private var accent: Color {
        TeamTheme.forTeam(attributes.favoriteCode ?? attributes.homeCode).primary
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                scoreRow
                matchupRow
                if state.isLive {
                    detailRow
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if let latest = state.recentPlays.first {
                Text(latest)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.black.opacity(0.24), in: Capsule())
                    .padding(.horizontal, 12)
                    .padding(.bottom, 11)
            }
        }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [accent.deep, accent.deep.opacity(0.85)], startPoint: .top, endPoint: .bottom))
    }

    /// 키움  0  ◇◆◇  0  SSG
    private var scoreRow: some View {
        HStack(spacing: 0) {
            Text(TeamTheme.shortName(for: attributes.awayCode))
                .font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
            score(state.awayScore)
            BasesDiamond(bases: state.bases, size: 40, occupiedColor: .white)
                .padding(.horizontal, 16)
            score(state.homeScore)
            Text(TeamTheme.shortName(for: attributes.homeCode))
                .font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .lineLimit(1)
    }

    private func score(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "-")
            .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
            .frame(minWidth: 22)
    }

    /// 투수 | 1회말 | 타자
    private var matchupRow: some View {
        HStack(spacing: 8) {
            Text(state.pitcher ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(state.isLive ? state.title : state.status)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.18), in: Capsule())
                .fixedSize()
            Text(state.batter ?? "")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// 10구 | B ●●● S ●● OUT ●● | .356
    private var detailRow: some View {
        HStack(spacing: 8) {
            Text(state.pitchCount.map { "\($0)구" } ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            InlineCount(balls: state.balls, strikes: state.strikes, outs: state.outs)
                .fixedSize()
            Text(state.batterAverage ?? "")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
    }
}

/// B ●●● S ●● OUT ●● 를 한 줄로
private struct InlineCount: View {
    let balls: Int
    let strikes: Int
    let outs: Int

    var body: some View {
        HStack(spacing: 9) {
            group("B", filled: balls, total: 3, color: Color(hex: 0x3DDC84))
            group("S", filled: strikes, total: 2, color: Color(hex: 0xFFD23F))
            group("OUT", filled: outs, total: 2, color: Color(hex: 0xFF5A5A))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("볼 \(balls), 스트라이크 \(strikes), 아웃 \(outs)")
    }

    private func group(_ label: String, filled: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? color : Color.white.opacity(0.22))
                    .frame(width: 5, height: 5)
            }
        }
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
    /// 주자가 있는 베이스 색
    var occupiedColor: Color = .yellow

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
            .fill(occupied ? occupiedColor : Color.white.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: side * 0.15).stroke(Color.white.opacity(occupied ? 0 : 0.6), lineWidth: 1))
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
    /// 잠금화면 점수판 바탕: 팀 색을 어둡게 (KIA 빨강 → 짙은 자주)
    var deep: Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return Color(hue: hue, saturation: min(saturation, 0.85), brightness: min(brightness, 0.4))
    }

    /// 어두운 팀 색(두산·롯데·KT 남색·검정)도 검은 배경에서 보이도록 밝게
    var vivid: Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return Color(hue: hue, saturation: min(saturation, 0.85), brightness: max(brightness, 0.75))
    }
}
