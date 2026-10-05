import HomefieldCore
import SwiftUI

struct GameListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.teamTheme) private var theme
    @State private var date = Date()
    @State private var games: [GameSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DayStrip(date: $date)

                    if settings.useDemo {
                        Label("데모 모드: 가상 경기가 표시됩니다", systemImage: "play.rectangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .cardStyle(padding: 12)
                    }

                    ForEach(games) { game in
                        NavigationLink(value: game) {
                            GameCard(game: game, isFavorite: involvesFavorite(game))
                        }
                        .buttonStyle(.plain)
                    }

                    if !isLoading && games.isEmpty && errorMessage == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.largeTitle)
                                .foregroundStyle(theme.primary)
                            Text("이 날은 경기가 없어요").font(.headline)
                            Text("다른 날짜를 골라 보세요.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .cardStyle()
                    }
                }
                .padding(16)
            }
            .background { ThemedBackground() }
            .overlay {
                if isLoading && games.isEmpty { ProgressView() }
            }
            .navigationTitle("홈구장")
            .navigationDestination(for: GameSummary.self) { game in
                LiveGameView(game: game)
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
            withAnimation {
                games = loaded.sorted { sortKey($0) < sortKey($1) }
            }
            errorMessage = nil
        } catch {
            errorMessage = "경기 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func involvesFavorite(_ game: GameSummary) -> Bool {
        guard let favorite = settings.favoriteTeamCode else { return false }
        return game.home.code == favorite || game.away.code == favorite
    }

    /// 응원팀 경기 먼저, 그다음 진행 중, 시작 시각 순
    private func sortKey(_ game: GameSummary) -> (Int, Int, Date) {
        (involvesFavorite(game) ? 0 : 1, game.status == .live ? 0 : 1, game.startTime ?? .distantFuture)
    }
}

/// 날짜 줄: 좌우로 넘겨 날짜를 고르고, 아래 화살표를 누르면 달력이 나온다
private struct DayStrip: View {
    @Environment(\.teamTheme) private var theme
    @Binding var date: Date
    @State private var showingCalendar = false
    /// 줄의 가운데 날짜 (달력에서 먼 날짜를 고르면 그 날짜 기준으로 다시 만든다)
    @State private var anchor = Calendar.current.startOfDay(for: Date())

    private let range = -60...60

    var body: some View {
        let calendar = Calendar.current
        let selected = calendar.startOfDay(for: date)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingCalendar = true
            } label: {
                HStack(spacing: 4) {
                    Text(selected.formatted(.dateTime.year().month(.wide)))
                        .font(.title3.bold())
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.primary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("달력에서 날짜 고르기")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(range, id: \.self) { offset in
                            let day = calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
                            dayButton(day, selected: calendar.isDate(day, inSameDayAs: selected))
                                .id(day)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onAppear {
                    proxy.scrollTo(selected, anchor: .center)
                }
                .onChange(of: selected) { _, newValue in
                    let distance = calendar.dateComponents([.day], from: anchor, to: newValue).day ?? 0
                    if !range.contains(distance) {
                        anchor = newValue
                    }
                    withAnimation(.snappy) { proxy.scrollTo(newValue, anchor: .center) }
                }
                .onChange(of: anchor) { _, _ in
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
            .frame(height: 58)
        }
        .sheet(isPresented: $showingCalendar) {
            NavigationStack {
                DatePicker("날짜", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(theme.primary)
                    .padding()
                    .navigationTitle("날짜 선택")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("오늘") { date = Date() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showingCalendar = false }
                        }
                    }
                Spacer()
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: date) { _, _ in
            // 달력에서 날짜를 누르면 바로 닫는다
            showingCalendar = false
        }
    }

    private func dayButton(_ day: Date, selected: Bool) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            withAnimation(.snappy) { date = day }
        } label: {
            VStack(spacing: 2) {
                Text(isToday ? "오늘" : day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.bold())
                Text(day.formatted(.dateTime.day()))
                    .font(.headline.monospacedDigit())
            }
            .frame(width: 50, height: 54)
            .foregroundStyle(selected ? .white : (isToday ? theme.primary : .primary))
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(.regularMaterial))
            }
        }
        .buttonStyle(.plain)
    }
}

/// 경기 카드: 양 팀 배지와 점수, 상태
struct GameCard: View {
    let game: GameSummary
    var isFavorite = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                StatusBadge(game: game)
                if isFavorite {
                    Label("응원팀", systemImage: "heart.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(TeamTheme.forTeam(game.home.code).primary)
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                HStack(spacing: 6) {
                    if let start = game.startTime {
                        Text(start, format: .dateTime.hour().minute())
                    }
                    if let stadium = game.stadium { Text(stadium) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack {
                team(game.away, score: game.awayScore, winning: (game.awayScore ?? 0) > (game.homeScore ?? 0))
                Text("vs")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                team(game.home, score: game.homeScore, winning: (game.homeScore ?? 0) > (game.awayScore ?? 0))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if isFavorite {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [TeamTheme.forTeam(game.away.code).primary, TeamTheme.forTeam(game.home.code).primary],
                        startPoint: .leading,
                        endPoint: .trailing
                    ), lineWidth: 2)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func team(_ team: Team, score: Int?, winning: Bool) -> some View {
        HStack(spacing: 10) {
            TeamBadge(code: team.code, size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(team.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(score.map(String.init) ?? "-")
                    .font(.system(size: 30, weight: winning ? .heavy : .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(winning || game.status != .finished ? .primary : .secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
