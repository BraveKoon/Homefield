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
                VStack(alignment: .leading, spacing: AppStyle.stackSpacing) {
                    DayStrip(date: $date)

                    if settings.isAutumn {
                        AutumnBanner()
                    }

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

                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        NavigationLink(value: game) {
                            GameCard(game: game, isFavorite: involvesFavorite(game))
                        }
                        .buttonStyle(.pressable)
                        .appearing(index)
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
                        .transition(.opacity)
                    }
                }
                .padding(AppStyle.screenPadding)
            }
            .background { ThemedBackground() }
            .gentleAnimation()
            .overlay {
                if isLoading && games.isEmpty { ProgressView() }
            }
            .navigationTitle("홈구장")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RotationView()
                    } label: {
                        Label("선발", systemImage: "figure.baseball")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        StandingsView()
                    } label: {
                        Label("순위", systemImage: "list.number")
                    }
                }
            }
            .navigationDestination(for: GameSummary.self) { game in
                LiveGameView(game: game)
            }
            // 당겨서 새로고침하는 동안 화면이 다시 그려지며 작업이 취소되지 않도록 따로 돌리고 끝날 때까지 기다린다
            .refreshable { await Task { await load() }.value }
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
        } catch is CancellationError {
            // 날짜를 바꾸는 등으로 앞 요청이 취소된 것은 오류가 아니다
        } catch let error as URLError where error.code == .cancelled {
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

/// 날짜 줄: 일요일~토요일 한 주씩 보여 주고 좌우로 넘기면 한 주씩 이동한다. 아래 화살표를 누르면 달력.
private struct DayStrip: View {
    @Environment(\.teamTheme) private var theme
    @Binding var date: Date
    @State private var showingCalendar = false
    /// 보이는 주의 일요일
    @State private var visibleWeek: Date?
    /// 주 목록의 가운데 주 (달력에서 먼 날짜를 고르면 그 주 기준으로 다시 만든다)
    @State private var anchorWeek = DayStrip.weekStart(of: Date())

    private static let weekRange = -26...26

    /// 일요일 시작 달력
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }()

    static func weekStart(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private var weeks: [Date] {
        Self.weekRange.compactMap { Self.calendar.date(byAdding: .weekOfYear, value: $0, to: anchorWeek) }
    }

    var body: some View {
        let selected = Self.calendar.startOfDay(for: date)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingCalendar = true
            } label: {
                HStack(spacing: 4) {
                    Text((visibleWeek ?? selected).formatted(.dateTime.year().month(.wide)))
                        .font(.title3.bold())
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.primary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("달력에서 날짜 고르기")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(weeks, id: \.self) { week in
                        weekRow(week, selected: selected)
                            .containerRelativeFrame(.horizontal)
                            .id(week)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleWeek)
            .frame(height: 62)
        }
        .onAppear {
            visibleWeek = Self.weekStart(of: date)
        }
        .onChange(of: date) { _, newValue in
            showingCalendar = false
            let week = Self.weekStart(of: newValue)
            if !weeks.contains(week) { anchorWeek = week }
            if visibleWeek != week {
                withAnimation(.snappy) { visibleWeek = week }
            }
        }
        .onChange(of: visibleWeek) { _, newWeek in
            // 다른 주로 넘기면 그 주의 같은 요일을 고른다
            guard let newWeek, Self.weekStart(of: date) != newWeek else { return }
            let weekday = Self.calendar.component(.weekday, from: date)
            if let day = Self.calendar.date(byAdding: .day, value: weekday - 1, to: newWeek) {
                date = day
            }
        }
        .sheet(isPresented: $showingCalendar) {
            NavigationStack {
                DatePicker("날짜", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.calendar, Self.calendar)
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
    }

    /// 일~토 7칸
    private func weekRow(_ week: Date, selected: Date) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = Self.calendar.date(byAdding: .day, value: offset, to: week) ?? week
                dayButton(day, weekdayIndex: offset, selected: Self.calendar.isDate(day, inSameDayAs: selected))
            }
        }
        .padding(.horizontal, 1)
    }

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private func dayButton(_ day: Date, weekdayIndex: Int, selected: Bool) -> some View {
        let isToday = Self.calendar.isDateInToday(day)
        let weekendColor: Color = weekdayIndex == 0 ? .red : (weekdayIndex == 6 ? .blue : .primary)
        return Button {
            withAnimation(.tap) { date = day }
        } label: {
            VStack(spacing: 2) {
                Text(isToday ? "오늘" : Self.weekdaySymbols[weekdayIndex])
                    .font(.caption2.bold())
                    .foregroundStyle(selected ? .white : (isToday ? theme.primary : weekendColor))
                Text(day.formatted(.dateTime.day()))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(selected ? .white : weekendColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                let shape = RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous)
                if selected {
                    shape.fill(theme.gradient)
                } else {
                    shape.fill(.thinMaterial)
                        .overlay {
                            shape.strokeBorder(
                                isToday ? theme.primary.opacity(0.45) : Color.primary.opacity(0.06),
                                lineWidth: isToday ? 1.2 : AppStyle.hairline
                            )
                        }
                }
            }
        }
        .buttonStyle(.pressable)
    }
}

/// 경기 카드: 양 팀 배지와 점수, 상태
struct GameCard: View {
    let game: GameSummary
    var isFavorite = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous)
    }

    /// "선발 임찬규 · 올러" (일정에 예고가 있을 때만)
    private var starters: String? {
        let names = [game.awayStarter, game.homeStarter].compactMap { $0 }
        guard !names.isEmpty else { return nil }
        return "선발 " + names.joined(separator: " · ")
    }

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
            if let starters {
                Label(starters, systemImage: "figure.baseball")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppStyle.cardPadding)
        .background(.thinMaterial, in: shape)
        .overlay {
            if isFavorite {
                shape.strokeBorder(LinearGradient(
                    colors: [TeamTheme.forTeam(game.away.code).primary, TeamTheme.forTeam(game.home.code).primary],
                    startPoint: .leading,
                    endPoint: .trailing
                ), lineWidth: 1.5)
            } else {
                shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: AppStyle.hairline)
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
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

/// 가을야구 기간 머리말 카드
private struct AutumnBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("🍁")
                .font(.system(size: 34))
                .rotationEffect(.degrees(-15))
            VStack(alignment: .leading, spacing: 2) {
                Text("가을야구")
                    .font(.title3.weight(.black))
                Text("올해의 마지막 야구, 끝까지 함께 응원해요")
                    .font(.caption.weight(.semibold))
                    .opacity(0.9)
            }
            Spacer(minLength: 0)
            Text("🍂").font(.title2).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(AppStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                AutumnStyle.warmGradient
                FallingLeaves(count: 6, animated: false, opacity: 0.25, scale: 0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous))
        }
        .shadow(color: AutumnStyle.maple.opacity(0.22), radius: 7, y: 3)
    }
}
