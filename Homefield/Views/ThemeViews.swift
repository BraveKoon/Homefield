import HomefieldCore
import SwiftUI

/// 위에서 응원팀 색이 옅게 내려오는 배경. 실밥 무늬는 질감으로만 아주 옅게 깐다.
struct ThemedBackground: View {
    @Environment(\.teamTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isAutumn) private var isAutumn

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [theme.primary.opacity(isDark ? 0.34 : 0.18), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )
            if isAutumn {
                // 가을야구: 아래쪽에만 노을빛을 옅게
                LinearGradient(
                    colors: [.clear, AutumnStyle.orange.opacity(isDark ? 0.16 : 0.12)],
                    startPoint: UnitPoint(x: 0.5, y: 0.6),
                    endPoint: .bottom
                )
            }
            StitchPattern()
                .foregroundStyle(theme.primary.opacity(isDark ? 0.05 : 0.035))
            if isAutumn {
                FallingLeaves(count: 7, opacity: isDark ? 0.3 : 0.34, scale: 0.9)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: isAutumn)
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
    func cardStyle(padding: CGFloat = AppStyle.cardPadding) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous)
        return self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: AppStyle.hairline)
            }
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

/// 팀 로고 (네이버 스포츠 이미지). 받기 전이나 없으면 팀 색 동그라미 + 짧은 팀 이름.
struct TeamBadge: View {
    @Environment(\.isAutumn) private var isAutumn
    let code: String
    var size: CGFloat = 44

    var body: some View {
        let theme = TeamTheme.forTeam(code)
        let isKBO = KBOTeams.name(for: code) != nil
        RemoteImage(url: isKBO ? SportsImageURL.teamLogo(code) : nil, contentMode: .fit) {
            ZStack {
                Circle().fill(theme.gradient)
                Text(TeamTheme.shortName(for: code))
                    .font(.system(size: size * (TeamTheme.shortName(for: code).count > 2 ? 0.26 : 0.32), weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.08)
            }
        }
        .padding(isKBO ? size * 0.14 : 0)
        .frame(width: size, height: size)
        .background(Circle().fill(.white))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.primary.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: size * 0.08, y: size * 0.03)
        .overlay(alignment: .bottomTrailing) {
            if isAutumn && size >= 30 { AutumnLeafBadge(size: size) }
        }
        .accessibilityHidden(true)
    }
}

/// 응원팀 고르는 격자 (첫 실행·설정에서 같이 쓴다)
struct TeamPickerGrid: View {
    @Binding var selection: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(AppTeams.all, id: \.code) { team in
                let selected = selection == team.code
                let theme = TeamTheme.forTeam(team.code)
                Button {
                    withAnimation(.appear) { selection = team.code }
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
                        RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous)
                            .fill(selected ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(.thinMaterial))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous)
                            .strokeBorder(selected ? Color.white.opacity(0.55) : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : AppStyle.hairline)
                    }
                    .scaleEffect(selected ? 1.02 : 1)
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// 처음 실행할 때: Apple 로그인(또는 게스트)을 고른 뒤 응원팀을 고른다
struct OnboardingView: View {
    private enum Step { case login, team }

    @Environment(AppSettings.self) private var settings
    @Environment(AccountStore.self) private var account
    // 데모 빌드는 로그인 단계 없이 팀 고르기부터
    @State private var step = BuildFlavor.isDemo ? Step.team : Step.login
    @State private var selection: String?

    var body: some View {
        let theme = TeamTheme.forTeam(selection)
        ZStack {
            ZStack {
                theme.gradient
                StitchPattern().foregroundStyle(.white.opacity(0.08))
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: selection)

            switch step {
            case .login:
                loginStep
                    .transition(.opacity)
            case .team:
                teamStep(theme: theme)
                    .transition(.opacity)
            }
        }
        .animation(.appear, value: step)
        .modifier(AccountDialogs())
        .onAppear {
            selection = settings.favoriteTeamCode
            // 이미 로그인돼 있으면(앱을 지웠다 깔았는데 세션이 남은 경우 등) 로그인 단계는 건너뛴다
            if account.isSignedIn { step = .team }
        }
        // 로그인과 첫 동기화가 끝나면: 계정에 응원팀이 있으면 바로 시작, 없으면 팀 고르기
        .onChange(of: account.status) { _, status in
            guard step == .login, account.isSignedIn else { return }
            switch status {
            case .synced:
                if settings.favoriteTeamCode != nil {
                    settings.hasCompletedOnboarding = true
                } else {
                    step = .team
                }
            case .failed:
                // 로그인은 됐지만 동기화를 못 했다: 일단 팀을 고르고, 동기화는 나중에 다시 한다
                step = .team
            default:
                break
            }
        }
    }

    // MARK: 로그인

    private var loginStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 10) {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                Text("홈구장")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(.white)
                Text("집에서도 야구장처럼.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 24)

            VStack(spacing: 14) {
                Text("로그인하면 카드·포인트·응원 라인업이\n다른 기기에서도 그대로 이어져요.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))

                ZStack {
                    AppleSignInButton(style: .white, height: 52)
                        .opacity(account.status == .working ? 0.4 : 1)
                        .disabled(account.status == .working)
                    if account.status == .working {
                        ProgressView().tint(.black)
                    }
                }

                if case .failed(let message) = account.status {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }

                Button("게스트로 진행하기") {
                    step = .team
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.vertical, 6)
                .disabled(account.status == .working)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: 응원팀 고르기

    private func teamStep(theme: TeamTheme) -> some View {
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
                    Text(selection.map { "\(AppTeams.name(for: $0) ?? $0) 응원하기" } ?? "팀을 골라 주세요")
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
    }

    private func finish(with code: String?) {
        if let code { settings.favoriteTeamCode = code }
        settings.hasCompletedOnboarding = true
    }
}
