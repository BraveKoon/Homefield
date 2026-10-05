import HomefieldCore
import SwiftUI

/// 응원팀 색이 위에서 은은하게 내려오고, 야구공 실밥 무늬가 깔린 배경
struct ThemedBackground: View {
    @Environment(\.teamTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [theme.primary.opacity(colorScheme == .dark ? 0.55 : 0.32), theme.secondary.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.55)
            )
            StitchPattern()
                .foregroundStyle(theme.primary.opacity(colorScheme == .dark ? 0.10 : 0.07))
        }
        .ignoresSafeArea()
    }
}

/// 야구공 실밥처럼 생긴 곡선을 비스듬히 반복해서 그린다
private struct StitchPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 120
            var row = 0
            var y: CGFloat = -spacing / 2
            while y < size.height + spacing {
                var x: CGFloat = row.isMultiple(of: 2) ? -spacing / 2 : 0
                while x < size.width + spacing {
                    var seam = Path()
                    seam.addArc(center: CGPoint(x: x, y: y), radius: 34, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                    context.stroke(seam, with: .foreground, lineWidth: 1.5)
                    // 실밥
                    for step in 0..<6 {
                        let angle = Angle.degrees(212 + Double(step) * 23).radians
                        let inner = CGPoint(x: x + cos(angle) * 29, y: y + sin(angle) * 29)
                        let outer = CGPoint(x: x + cos(angle) * 39, y: y + sin(angle) * 39)
                        var stitch = Path()
                        stitch.move(to: inner)
                        stitch.addLine(to: outer)
                        context.stroke(stitch, with: .foreground, lineWidth: 1.5)
                    }
                    x += spacing
                }
                y += spacing * 0.8
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// 목록·폼 기본 회색 배경 대신 팀 색 배경
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { ThemedBackground() }
    }

    /// 배경 위에 떠 있는 카드
    func cardStyle(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

/// 팀 색 동그라미 + 짧은 팀 이름 (로고 대신)
struct TeamBadge: View {
    let code: String
    var size: CGFloat = 44

    var body: some View {
        let theme = TeamTheme.forTeam(code)
        ZStack {
            Circle().fill(theme.gradient)
            Text(TeamTheme.shortName(for: code))
                .font(.system(size: size * (TeamTheme.shortName(for: code).count > 2 ? 0.26 : 0.32), weight: .heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .padding(size * 0.08)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: size > 36 ? 2 : 1))
        .shadow(color: theme.primary.opacity(0.35), radius: size * 0.12, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

/// 응원팀 고르는 격자 (첫 실행·설정에서 같이 쓴다)
struct TeamPickerGrid: View {
    @Binding var selection: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(KBOTeams.all, id: \.code) { team in
                let selected = selection == team.code
                let theme = TeamTheme.forTeam(team.code)
                Button {
                    withAnimation(.spring(duration: 0.35)) { selection = team.code }
                } label: {
                    HStack(spacing: 10) {
                        TeamBadge(code: team.code, size: 40)
                        Text(team.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .foregroundStyle(selected ? .white : .primary)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selected ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(.regularMaterial))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selected ? Color.white.opacity(0.8) : theme.primary.opacity(0.25), lineWidth: selected ? 2 : 1)
                    }
                    .scaleEffect(selected ? 1.03 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// 처음 실행할 때 응원팀을 고른다
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selection: String?

    var body: some View {
        let theme = TeamTheme.forTeam(selection)
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                    Text("홈구장")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(.white)
                    Text("집에서도 야구장처럼.\n응원하는 팀을 골라 주세요.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 48)

                TeamPickerGrid(selection: $selection)
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("앱 색과 노래 재생 범위가 응원팀에 맞춰집니다. 설정에서 언제든 바꿀 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 140)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    finish(with: selection)
                } label: {
                    Text(selection.map { "\(KBOTeams.name(for: $0) ?? $0) 응원하기" } ?? "팀을 골라 주세요")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primary)
                .disabled(selection == nil)

                Button("나중에 정할게요") { finish(with: nil) }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .background {
            ZStack {
                theme.gradient
                StitchPattern().foregroundStyle(.white.opacity(0.08))
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: selection)
        }
        .onAppear { selection = settings.favoriteTeamCode }
    }

    private func finish(with code: String?) {
        if let code { settings.favoriteTeamCode = code }
        settings.hasCompletedOnboarding = true
    }
}
