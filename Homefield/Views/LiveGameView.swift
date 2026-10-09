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
    /// 사용자가 직접 펼치거나 접은 투구 묶음
    @State private var pitchToggles: [String: Bool] = [:]

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
                            ForEach(RelayItem.items(for: half.lines, isCurrentHalf: half.id == session.currentHalfKey)) { item in
                                switch item {
                                case .line(let line):
                                    RelayLineRow(line: line)
                                case .pitches(let id, let lines, let live):
                                    PitchGroupRow(lines: lines, isExpanded: pitchExpansion(for: id, live: live))
                                }
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
    /// 지금 타석의 투구는 펼치고, 끝난 타석의 투구는 접는다 (사용자가 누르면 그 선택을 따른다)
    func pitchExpansion(for id: String, live: Bool) -> Binding<Bool> {
        Binding(
            get: { pitchToggles[id] ?? live },
            set: { pitchToggles[id] = $0 }
        )
    }

    func expansion(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedHalves.contains(key) },
            set: { isExpanded in
                if isExpanded { expandedHalves.insert(key) } else { expandedHalves.remove(key) }
            }
        )
    }
}

/// 이닝 중계 목록의 한 항목: 일반 중계 줄 또는 한 타석의 투구 묶음
private enum RelayItem: Identifiable {
    case line(LiveGameSession.LogLine)
    /// live: 지금 진행 중인 타석의 투구
    case pitches(id: String, lines: [LiveGameSession.LogLine], live: Bool)

    var id: String {
        switch self {
        case .line(let line): line.id
        case .pitches(let id, _, _): "pitches-\(id)"
        }
    }

    /// 최신 줄이 앞에 오는 목록에서 이어진 투구 줄을 묶는다.
    /// 맨 앞(가장 최근)에 있는 투구 묶음만 아직 타석이 끝나지 않은 것으로 본다.
    static func items(for lines: [LiveGameSession.LogLine], isCurrentHalf: Bool) -> [RelayItem] {
        var items: [RelayItem] = []
        var pitches: [LiveGameSession.LogLine] = []
        func flush() {
            // 새 투구가 위에 붙어도 묶음이 그대로 유지되도록 그 타석의 첫 투구로 구분한다
            guard let oldest = pitches.last else { return }
            items.append(.pitches(id: oldest.id, lines: pitches, live: isCurrentHalf && items.isEmpty))
            pitches = []
        }
        for line in lines {
            if line.isPitch {
                pitches.append(line)
            } else {
                flush()
                items.append(.line(line))
            }
        }
        flush()
        return items
    }
}

/// 한 타석의 투구들. 접혀 있으면 "투구 3개 · 볼 2 스트라이크 1" 요약만 보인다.
private struct PitchGroupRow: View {
    let lines: [LiveGameSession.LogLine]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded.animation(.snappy)) {
            ForEach(lines) { line in
                RelayLineRow(line: line)
            }
        } label: {
            HStack(spacing: 8) {
                Text("⚾️").font(.caption).frame(width: 22)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        let texts = lines.map(\.text)
        let balls = texts.filter { $0.contains("볼") && !$0.contains("볼넷") }.count
        let strikes = texts.filter { $0.contains("스트라이크") || $0.contains("헛스윙") }.count
        let fouls = texts.filter { $0.contains("파울") }.count
        let parts = [
            balls > 0 ? "볼 \(balls)" : nil,
            strikes > 0 ? "스트라이크 \(strikes)" : nil,
            fouls > 0 ? "파울 \(fouls)" : nil,
        ].compactMap { $0 }
        return (["투구 \(lines.count)개"] + parts).joined(separator: " · ")
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
                if let title = state.halfInningTitle ?? game.statusText {
                    Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                }
                CountView(state: state)
                if let pitcher = state.pitcherName {
                    Text("투수 \(pitcher)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Text(game.status.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.85), in: Capsule())
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

    private var statusColor: Color {
        switch game.status {
        case .live: .red
        case .finished: .black
        default: .gray
        }
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
