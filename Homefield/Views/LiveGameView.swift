import HomefieldCore
import SwiftUI

struct LiveGameView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SongLibrary.self) private var library
    @Environment(AudioDirector.self) private var director
    let game: GameSummary

    @State private var session: LiveGameSession?
    @State private var editingBatter: Player?
    /// 펼쳐 둔 이닝 (진행 중인 이닝이 바뀌면 그 이닝만 펼친다)
    @State private var expandedHalves: Set<String> = []

    var body: some View {
        List {
            if let session {
                Section {
                    Scoreboard(game: session.game, state: session.gameState)
                        .listRowInsets(EdgeInsets())
                        .animation(.snappy, value: session.game.homeScore)
                        .animation(.snappy, value: session.game.awayScore)
                    if let lineScore = session.game.lineScore {
                        LineScoreView(
                            game: session.game,
                            lineScore: lineScore,
                            currentInning: session.gameState.inning,
                            battingSide: session.gameState.battingSide
                        )
                        .padding(.vertical, 4)
                    }
                    FieldView(
                        state: session.gameState,
                        fieldingTeamCode: session.gameState.fieldingSide.map { session.game.team(for: $0).code },
                        battingTeamCode: session.gameState.battingSide.map { session.game.team(for: $0).code }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
                }

                Section("타석") {
                    if let batter = session.currentBatter {
                        BatterCard(batter: batter) { editingBatter = batter }
                    } else {
                        Text("다음 타자를 기다리는 중…")
                            .foregroundStyle(.secondary)
                    }
                    if let nowPlaying = director.nowPlaying {
                        Label(nowPlaying, systemImage: "speaker.wave.2.fill")
                            .font(.footnote)
                    }
                    if let error = director.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ControlsView(session: session)
                }

                if let error = session.lastError {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.red)
                    }
                }

                Section("중계") {
                    if session.log.isEmpty {
                        Text("중계를 기다리는 중…").foregroundStyle(.secondary)
                    }
                    ForEach(session.halves) { half in
                        DisclosureGroup(isExpanded: expansion(for: half.id)) {
                            ForEach(half.lines) { line in
                                RelayLineRow(line: line)
                            }
                        } label: {
                            HStack {
                                Text(half.title).font(.headline)
                                if half.id == session.currentHalfKey {
                                    Text("진행 중")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                Text("\(half.lines.filter { !$0.isPitch }.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .themedBackground()
        .onChange(of: session?.currentHalfKey) { _, newKey in
            // 이닝이 끝나면 지난 이닝은 접고 새 이닝을 펼친다
            if let newKey { expandedHalves = [newKey] }
        }
        .navigationTitle("\(game.away.name) vs \(game.home.name)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingBatter) { batter in
            NavigationStack {
                PlayerDetailView(
                    teamCode: batter.teamCode,
                    name: batter.name,
                    today: session?.todayLine(for: batter),
                    showsDoneButton: true
                )
            }
        }
        .onAppear {
            guard session == nil else { return }
            let session = LiveGameSession(
                game: game,
                provider: settings.makeProvider(),
                settings: settings,
                library: library,
                director: director
            )
            self.session = session
            session.start()
            expandedHalves = [session.currentHalfKey]
        }
        .onDisappear {
            session?.stop()
            session = nil
        }
    }
}

private extension LiveGameView {
    func expansion(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedHalves.contains(key) },
            set: { isExpanded in
                if isExpanded { expandedHalves.insert(key) } else { expandedHalves.remove(key) }
            }
        )
    }
}

private struct RelayLineRow: View {
    let line: LiveGameSession.LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.badge)
                .frame(width: 22)
            Text(line.text)
                .font(line.isPitch ? .footnote : .body)
                .fontWeight(line.isBatter ? .semibold : .regular)
                .foregroundStyle(line.isPitch ? .secondary : .primary)
            Spacer(minLength: 0)
        }
    }
}

private struct Scoreboard: View {
    let game: GameSummary
    let state: LiveGameState

    var body: some View {
        HStack(alignment: .center) {
            teamColumn(game.away, score: game.awayScore, label: "원정", batting: state.battingSide == .away)
            VStack(spacing: 6) {
                if let title = state.halfInningTitle {
                    Text(title).font(.headline)
                } else {
                    StatusBadge(game: game)
                }
                CountView(state: state)
                if let pitcher = state.pitcherName {
                    Text("투수 \(pitcher)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            teamColumn(game.home, score: game.homeScore, label: "홈", batting: state.battingSide == .home)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background {
            ZStack {
                LinearGradient(
                    colors: [TeamTheme.forTeam(game.away.code).primary, TeamTheme.forTeam(game.home.code).primary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                Color.black.opacity(0.35)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func teamColumn(_ team: Team, score: Int?, label: String, batting: Bool) -> some View {
        VStack(spacing: 4) {
            TeamBadge(code: team.code, size: 40)
            HStack(spacing: 4) {
                if batting {
                    Image(systemName: "baseball.fill").font(.caption2).foregroundStyle(.yellow)
                }
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
            Text(team.name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(score.map(String.init) ?? "-")
                .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BatterCard: View {
    @Environment(SongLibrary.self) private var library
    let batter: Player
    let onEdit: () -> Void

    var body: some View {
        let assignment = library.assignment(for: batter)
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                PlayerAvatar(teamCode: batter.teamCode, name: batter.name, size: 52)
                Text([batter.battingOrder.map { "\($0)번" }, batter.backNumber.map { "#\($0)" }].compactMap { $0 }.joined(separator: " "))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(batter.name).font(.title2.bold())
                Text("\(library.teamName(for: batter.teamCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(assignment.walkUp?.title ?? "등장곡 없음", systemImage: "figure.walk")
                    .font(.footnote)
                Label(library.cheer(for: batter)?.title ?? "응원가 없음", systemImage: "megaphone")
                    .font(.footnote)
            }
            Spacer()
            Button("선수 정보", action: onEdit)
                .buttonStyle(.bordered)
        }
    }
}

private struct ControlsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AudioDirector.self) private var director
    let session: LiveGameSession

    var body: some View {
        @Bindable var settings = settings
        @Bindable var director = director

        Toggle(isOn: $director.isMuted) {
            Label("음소거", systemImage: director.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
        }
        Button {
            director.stopMusic()
        } label: {
            Label("지금 나오는 노래 끄기", systemImage: "stop.circle")
        }
        VStack(alignment: .leading) {
            Stepper(value: $settings.broadcastDelay, in: 0...120, step: 1) {
                Label("방송 싱크: \(Int(settings.broadcastDelay))초 늦게", systemImage: "tv")
            }
            if session.pendingBatches > 0 {
                Text("대기 중인 상황 \(session.pendingBatches)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
