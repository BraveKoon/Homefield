import HomefieldCore
import SwiftUI

struct LiveGameView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SongLibrary.self) private var library
    @Environment(AudioDirector.self) private var director
    let game: GameSummary

    @State private var session: LiveGameSession?
    @State private var editingBatter: Player?

    var body: some View {
        List {
            if let session {
                Section { Scoreboard(game: session.game) }

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
                    ForEach(session.log) { line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.badge)
                            Text(line.text)
                                .fontWeight(line.isBatter ? .semibold : .regular)
                            Spacer()
                            Text(line.time, format: .dateTime.hour().minute().second())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
        }
        .onDisappear {
            session?.stop()
            session = nil
        }
    }
}

private struct Scoreboard: View {
    let game: GameSummary

    var body: some View {
        HStack {
            teamColumn(game.away, score: game.awayScore, label: "원정")
            VStack(spacing: 4) {
                StatusBadge(game: game)
                if let stadium = game.stadium {
                    Text(stadium).font(.caption2).foregroundStyle(.secondary)
                }
            }
            teamColumn(game.home, score: game.homeScore, label: "홈")
        }
        .padding(.vertical, 8)
    }

    private func teamColumn(_ team: Team, score: Int?, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(team.name).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            Text(score.map(String.init) ?? "-").font(.system(size: 40, weight: .bold).monospacedDigit())
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
            VStack {
                Text(batter.battingOrder.map { "\($0)번" } ?? "타자")
                    .font(.caption.bold())
                Text(batter.backNumber.map { "#\($0)" } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
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
