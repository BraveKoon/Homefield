import HomefieldCore
import SwiftUI

struct GameListView: View {
    @Environment(AppSettings.self) private var settings
    @State private var date = Date()
    @State private var games: [GameSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if settings.useDemo {
                    Section {
                        Label("데모 모드: 가상 경기가 표시됩니다", systemImage: "play.rectangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    ForEach(games) { game in
                        NavigationLink(value: game) {
                            GameRow(game: game)
                        }
                    }
                } footer: {
                    if !isLoading && games.isEmpty && errorMessage == nil {
                        Text("이 날은 경기가 없습니다.")
                    }
                }
            }
            .overlay {
                if isLoading && games.isEmpty { ProgressView() }
            }
            .navigationTitle("홈구장")
            .navigationDestination(for: GameSummary.self) { game in
                LiveGameView(game: game)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker("날짜", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .refreshable { await load() }
            .task(id: LoadKey(date: Calendar.current.startOfDay(for: date), demo: settings.useDemo)) {
                await load()
            }
        }
    }

    private struct LoadKey: Equatable {
        let date: Date
        let demo: Bool
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await settings.makeProvider().games(on: date)
            games = loaded.sorted { sortKey($0) < sortKey($1) }
            errorMessage = nil
        } catch {
            errorMessage = "경기 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 진행 중인 경기를 먼저, 그다음 시작 시각 순
    private func sortKey(_ game: GameSummary) -> (Int, Date) {
        (game.status == .live ? 0 : 1, game.startTime ?? .distantFuture)
    }
}

struct GameRow: View {
    let game: GameSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(game.away.name) vs \(game.home.name)")
                    .font(.headline)
                HStack(spacing: 6) {
                    if let start = game.startTime {
                        Text(start, format: .dateTime.hour().minute())
                    }
                    if let stadium = game.stadium { Text(stadium) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let away = game.awayScore, let home = game.homeScore {
                    Text("\(away) : \(home)")
                        .font(.title3.monospacedDigit().bold())
                }
                StatusBadge(game: game)
            }
        }
    }
}

struct StatusBadge: View {
    let game: GameSummary

    var body: some View {
        Text(game.status == .live ? (game.statusText ?? "경기 중") : game.status.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(game.status == .live ? Color.red : Color.secondary.opacity(0.2), in: Capsule())
            .foregroundStyle(game.status == .live ? Color.white : Color.primary)
    }
}
