import HomefieldCore
import SwiftUI

/// KBO 정규시즌 팀 순위표 (네이버 스포츠)
struct StandingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.teamTheme) private var theme
    @State private var season = Calendar.current.component(.year, from: Date())
    @State private var standings: [TeamStanding] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var updatedAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .cardStyle(padding: 12)
                }

                if !standings.isEmpty {
                    VStack(spacing: 0) {
                        header
                        ForEach(standings) { standing in
                            Divider()
                            StandingRow(standing: standing, isFavorite: standing.teamCode == settings.favoriteTeamCode)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if let updatedAt {
                        Text("네이버 스포츠 기준 · \(updatedAt.formatted(date: .omitted, time: .shortened)) 업데이트 · 당겨서 새로고침")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !isLoading && errorMessage == nil {
                    Text("순위 정보가 없어요")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(16)
        }
        .background { ThemedBackground() }
        .overlay {
            if isLoading && standings.isEmpty { ProgressView() }
        }
        .navigationTitle("\(String(season)) 순위")
        .refreshable { await Task { await load() }.value }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("순위").frame(width: 30)
            Text("팀").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 38)
            Text("경기").frame(width: 34)
            Text("승-패-무").frame(width: 74)
            Text("승률").frame(width: 42)
            Text("차").frame(width: 32)
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await NaverSportsProvider().standings(season: season)
            withAnimation { standings = loaded }
            updatedAt = Date()
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = "순위를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }
}

private struct StandingRow: View {
    let standing: TeamStanding
    let isFavorite: Bool

    var body: some View {
        let theme = TeamTheme.forTeam(standing.teamCode)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text("\(standing.rank)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 30)
                HStack(spacing: 8) {
                    TeamBadge(code: standing.teamCode, size: 30)
                    Text(TeamTheme.shortName(for: standing.teamCode))
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(theme.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(standing.games)").frame(width: 34)
                Text("\(standing.wins)-\(standing.losses)-\(standing.draws)")
                    .frame(width: 74)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(standing.winRateText).frame(width: 42).fontWeight(.semibold)
                Text(standing.gamesBehindText).frame(width: 32)
            }
            .font(.subheadline.monospacedDigit())

            HStack(spacing: 6) {
                Color.clear.frame(width: 30, height: 1)
                LastFiveView(results: standing.lastFive ?? "")
                if let streak = standing.streak, !streak.isEmpty {
                    Text(streak)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background((streak.contains("승") ? Color.red : streak.contains("패") ? Color.blue : Color.gray).opacity(0.15), in: Capsule())
                        .foregroundStyle(streak.contains("승") ? Color.red : streak.contains("패") ? Color.blue : Color.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isFavorite ? theme.primary.opacity(0.10) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(standing.rank)위 \(standing.teamName), \(standing.wins)승 \(standing.losses)패 \(standing.draws)무, 승률 \(standing.winRateText), 게임차 \(standing.gamesBehindText)")
    }
}

/// 최근 5경기: 승 빨강, 패 파랑, 무 회색
private struct LastFiveView: View {
    let results: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Text(label(result))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(color(result), in: Circle())
            }
        }
    }

    private func label(_ result: Character) -> String {
        switch result {
        case "W": "승"
        case "L": "패"
        case "D": "무"
        default: String(result)
        }
    }

    private func color(_ result: Character) -> Color {
        switch result {
        case "W": .red
        case "L": .blue
        default: .gray
        }
    }
}
