import HomefieldCore
import SwiftUI
import UIKit

/// 선수 사진 (없으면 이름 첫 글자)
struct PlayerAvatar: View {
    @Environment(SongLibrary.self) private var library
    let teamCode: String
    let name: String
    var size: CGFloat = 44

    var body: some View {
        let theme = TeamTheme.forTeam(teamCode)
        Group {
            if let url = library.photoURL(teamCode: teamCode, name: name),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    theme.gradient
                    Text(String(name.prefix(1)))
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: size > 30 ? 2 : 1))
        .accessibilityLabel("\(name) 사진")
    }
}

/// B ●●○  S ●○  O ●○
struct CountView: View {
    let state: LiveGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("B", filled: state.balls, total: 3, color: .green)
            row("S", filled: state.strikes, total: 2, color: .yellow)
            row("O", filled: state.outs, total: 2, color: .red)
        }
        .font(.caption.monospaced().bold())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.balls)볼 \(state.strikes)스트라이크 \(state.outs)아웃")
    }

    private func row(_ label: String, filled: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).frame(width: 12, alignment: .leading)
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? color : Color.secondary.opacity(0.25))
                    .frame(width: 11, height: 11)
            }
        }
    }
}

/// 야구장 그림 위에 수비수, 주자, 타자, 투수를 보여 준다
struct FieldView: View {
    let state: LiveGameState
    /// 수비 팀·공격 팀 코드 (사진과 색)
    let fieldingTeamCode: String?
    let battingTeamCode: String?

    private static let spots: [FieldPosition: CGPoint] = [
        .left: CGPoint(x: 0.17, y: 0.30),
        .center: CGPoint(x: 0.50, y: 0.15),
        .right: CGPoint(x: 0.83, y: 0.30),
        .shortstop: CGPoint(x: 0.35, y: 0.43),
        .second: CGPoint(x: 0.65, y: 0.43),
        .third: CGPoint(x: 0.21, y: 0.60),
        .first: CGPoint(x: 0.79, y: 0.60),
        .pitcher: CGPoint(x: 0.50, y: 0.60),
        .catcher: CGPoint(x: 0.50, y: 0.95),
    ]

    /// 1루, 2루, 3루, 홈
    private static let bases: [CGPoint] = [
        CGPoint(x: 0.68, y: 0.66),
        CGPoint(x: 0.50, y: 0.50),
        CGPoint(x: 0.32, y: 0.66),
        CGPoint(x: 0.50, y: 0.83),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                field(in: size)
                ForEach(FieldPosition.allCases, id: \.self) { position in
                    if let name = state.fielders[position], let spot = Self.spots[position] {
                        fielderChip(name: name, position: position)
                            .position(x: spot.x * size.width, y: spot.y * size.height)
                    }
                }
                ForEach(0..<3, id: \.self) { index in
                    if let runner = state.bases[index] {
                        runnerChip(runner)
                            .position(x: Self.bases[index].x * size.width, y: Self.bases[index].y * size.height - 16)
                    }
                }
                if let batter = state.batterName {
                    VStack(spacing: 2) {
                        if let battingTeamCode {
                            PlayerAvatar(teamCode: battingTeamCode, name: batter, size: 30)
                        }
                        nameTag(batter, background: .white, foreground: .black)
                    }
                    .position(x: 0.30 * size.width, y: 0.90 * size.height)
                }
            }
        }
        .aspectRatio(1.1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func field(in size: CGSize) -> some View {
        let w = size.width, h = size.height
        return ZStack {
            // 잔디
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(hex: 0x2E7D32), Color(hex: 0x1B5E20)], startPoint: .top, endPoint: .bottom))
            // 외야 펜스 모양
            Path { path in
                path.move(to: CGPoint(x: 0.50 * w, y: 0.95 * h))
                path.addLine(to: CGPoint(x: 0.02 * w, y: 0.47 * h))
                path.addQuadCurve(to: CGPoint(x: 0.98 * w, y: 0.47 * h), control: CGPoint(x: 0.50 * w, y: -0.12 * h))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.06))
            // 내야 흙
            Path { path in
                path.move(to: CGPoint(x: 0.50 * w, y: 0.95 * h))
                path.addLine(to: CGPoint(x: 0.24 * w, y: 0.66 * h))
                path.addQuadCurve(to: CGPoint(x: 0.76 * w, y: 0.66 * h), control: CGPoint(x: 0.50 * w, y: 0.30 * h))
                path.closeSubpath()
            }
            .fill(Color(hex: 0xB8804A))
            // 내야 잔디
            Path { path in
                path.move(to: CGPoint(x: Self.bases[3].x * w, y: Self.bases[3].y * h - 8))
                path.addLine(to: CGPoint(x: Self.bases[0].x * w - 8, y: Self.bases[0].y * h))
                path.addLine(to: CGPoint(x: Self.bases[1].x * w, y: Self.bases[1].y * h + 8))
                path.addLine(to: CGPoint(x: Self.bases[2].x * w + 8, y: Self.bases[2].y * h))
                path.closeSubpath()
            }
            .fill(Color(hex: 0x2E7D32))
            // 베이스
            ForEach(0..<4, id: \.self) { index in
                let occupied = index < 3 && state.bases[index] != nil
                Rectangle()
                    .fill(occupied ? Color.yellow : Color.white)
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(45))
                    .position(x: Self.bases[index].x * w, y: Self.bases[index].y * h)
            }
            // 마운드
            Circle()
                .fill(Color(hex: 0xB8804A))
                .frame(width: 18, height: 18)
                .position(x: 0.50 * w, y: 0.66 * h)
        }
    }

    private func fielderChip(name: String, position: FieldPosition) -> some View {
        VStack(spacing: 2) {
            if position == .pitcher, let fieldingTeamCode {
                PlayerAvatar(teamCode: fieldingTeamCode, name: name, size: 26)
            }
            nameTag(name, background: .black.opacity(0.55), foreground: .white)
        }
    }

    private func runnerChip(_ name: String) -> some View {
        nameTag(name, background: .yellow, foreground: .black)
    }

    private func nameTag(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let pitcher = state.pitcherName { parts.append("투수 \(pitcher)") }
        if let batter = state.batterName { parts.append("타자 \(batter)") }
        let runners = (0..<3).compactMap { index in state.bases[index].map { "\(index + 1)루 \($0)" } }
        parts.append(runners.isEmpty ? "주자 없음" : runners.joined(separator: ", "))
        return parts.joined(separator: ", ")
    }
}

/// 이닝별 스코어: 1~12회 점수, R(점수)·H(안타)·E(에러)
struct LineScoreView: View {
    @Environment(\.teamTheme) private var theme
    let game: GameSummary
    let lineScore: LineScore
    /// 진행 중인 이닝 (강조)
    var currentInning: Int?
    var battingSide: TeamSide?

    private let cellWidth: CGFloat = 22

    var body: some View {
        let innings = max(12, lineScore.inningCount)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("이닝별 스코어").font(.subheadline.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("R 점수 · H 안타 · E 에러").font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 4, verticalSpacing: 8) {
                    GridRow {
                        Color.clear.frame(width: 40, height: 1)
                        ForEach(1...innings, id: \.self) { inning in
                            Text("\(inning)")
                                .foregroundStyle(inning == currentInning ? theme.primary : .secondary)
                                .frame(width: cellWidth)
                        }
                        Divider().frame(height: 14)
                        header("R")
                        header("H")
                        header("E")
                    }
                    .font(.caption.monospacedDigit())
                    Divider().gridCellUnsizedAxes(.horizontal)
                    row(.away, innings: innings)
                    row(.home, innings: innings)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func header(_ text: String) -> some View {
        Text(text).bold().frame(width: 26)
    }

    private func row(_ side: TeamSide, innings: Int) -> some View {
        let line = lineScore.line(for: side)
        let team = game.team(for: side)
        return GridRow {
            Text(TeamTheme.shortName(for: team.code))
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 40, alignment: .leading)
            ForEach(0..<innings, id: \.self) { index in
                let value = index < line.innings.count ? line.innings[index] : nil
                let live = index + 1 == currentInning && side == battingSide
                Text(value.map(String.init) ?? "-")
                    .font(.callout.monospacedDigit())
                    .fontWeight(live ? .bold : .regular)
                    .foregroundStyle(live ? theme.primary : (value == nil ? .secondary : .primary))
                    .frame(width: cellWidth)
            }
            Divider().frame(height: 18)
            total(line.runs, bold: true)
            total(line.hits)
            total(line.errors)
        }
    }

    private func total(_ value: Int?, bold: Bool = false) -> some View {
        Text(value.map(String.init) ?? "-")
            .font(.callout.monospacedDigit())
            .fontWeight(bold ? .heavy : .semibold)
            .frame(width: 26)
    }

    private var accessibilityText: String {
        [TeamSide.away, .home].map { side in
            let line = lineScore.line(for: side)
            return "\(game.team(for: side).name) \(line.runs ?? 0)점 \(line.hits ?? 0)안타 \(line.errors ?? 0)실책"
        }.joined(separator: ", ")
    }
}
