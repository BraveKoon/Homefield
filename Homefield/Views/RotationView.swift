import HomefieldCore
import SwiftUI

/// 팀의 선발 등판 기록과 다음 선발 예고
struct RotationView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.teamTheme) private var theme

    @State private var teamCode: String?
    @State private var starters: TeamStarters?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.stackSpacing) {
                teamPicker

                if let starters, !starters.isEmpty {
                    if let upcoming = starters.upcoming {
                        section("다음 선발 예고") {
                            UpcomingStarterCard(upcoming: upcoming, teamCode: starters.teamCode)
                        }
                    }
                    if !starters.starts.isEmpty {
                        section("최근 선발 등판") {
                            VStack(spacing: 0) {
                                ForEach(Array(starters.starts.enumerated()), id: \.element.id) { index, start in
                                    if index > 0 { Divider() }
                                    StartRow(start: start)
                                }
                            }
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous))
                        }
                    }
                } else if !isLoading {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.baseball")
                            .font(.largeTitle)
                            .foregroundStyle(theme.primary)
                        Text("선발 기록이 없어요")
                            .font(.headline)
                        Text("최근 2주 안에 치른 경기에서 선발을 읽습니다. 선발 예고는 발표된 뒤에 나옵니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .cardStyle()
                }

                Text("지난 등판은 그날 중계의 투수 명단에서, 선발 예고는 경기 일정에서 읽습니다. 다음 차례를 짐작해서 채우지는 않습니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(AppStyle.screenPadding)
        }
        .background { ThemedBackground() }
        .gentleAnimation()
        .overlay {
            if isLoading && starters == nil { ProgressView() }
        }
        .navigationTitle("선발")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await Task { await load(force: true) }.value }
        .task(id: teamCode ?? settings.favoriteTeamCode ?? "") { await load() }
        .onAppear { if teamCode == nil { teamCode = settings.favoriteTeamCode ?? KBOTeams.all.first?.code } }
    }

    private var current: String? {
        teamCode ?? settings.favoriteTeamCode
    }

    private var teamPicker: some View {
        Menu {
            ForEach(KBOTeams.all, id: \.code) { team in
                Button {
                    teamCode = team.code
                } label: {
                    Label(team.name, systemImage: team.code == current ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 10) {
                if let current {
                    TeamBadge(code: current, size: 34)
                    Text(KBOTeams.name(for: current) ?? current)
                        .font(.headline)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                Spacer(minLength: 0)
                if isLoading { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(.primary)
            .cardStyle(padding: 12)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.heavy))
            content()
        }
    }

    private func load(force: Bool = false) async {
        guard let current else { return }
        if !force, starters?.teamCode == current { return }
        isLoading = true
        defer { isLoading = false }
        let collected = await StarterCollector(provider: settings.makeProvider())
            .collect(teamCode: current)
        guard !Task.isCancelled else { return }
        withAnimation(.appear) { starters = collected }
    }
}

/// 다음 선발 예고
private struct UpcomingStarterCard: View {
    let upcoming: TeamStarters.Upcoming
    let teamCode: String

    var body: some View {
        HStack(spacing: 14) {
            PlayerAvatar(teamCode: teamCode, name: upcoming.pitcher, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(upcoming.pitcher)
                    .font(.title3.weight(.heavy))
                Text(matchup)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            TeamBadge(code: upcoming.opponentCode, size: 38)
        }
        .cardStyle()
    }

    private var matchup: String {
        let opponent = TeamTheme.shortName(for: upcoming.opponentCode)
        let place = upcoming.isHome ? "홈" : "원정"
        guard let date = upcoming.date else { return "\(opponent)전 (\(place))" }
        return "\(date.formatted(.dateTime.month().day().weekday(.abbreviated))) \(opponent)전 (\(place))"
    }
}

/// 지난 선발 등판 한 줄
private struct StartRow: View {
    let start: TeamStarters.Start

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(teamCode: start.pitcher.teamCode, name: start.pitcher.name, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(start.pitcher.name)
                    .font(.body.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            TeamBadge(code: start.opponentCode, size: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var detail: String {
        let opponent = TeamTheme.shortName(for: start.opponentCode)
        let place = start.isHome ? "홈" : "원정"
        guard let date = start.date else { return "\(opponent)전 (\(place))" }
        return "\(date.formatted(.dateTime.month().day())) \(opponent)전 (\(place))"
    }
}
