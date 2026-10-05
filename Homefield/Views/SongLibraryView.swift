import HomefieldCore
import SwiftUI
import UniformTypeIdentifiers

struct SongLibraryView: View {
    @Environment(SongLibrary.self) private var library
    @Environment(AppSettings.self) private var settings
    @State private var showingBatchImport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rosterStatus
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(orderedTeams, id: \.self) { code in
                            NavigationLink(value: code) {
                                TeamCard(code: code, isFavorite: code == settings.favoriteTeamCode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background { ThemedBackground() }
            .navigationTitle("등장곡 · 응원가")
            .navigationDestination(for: String.self) { code in
                TeamSongsView(teamCode: code)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("한 번에 가져오기", systemImage: "square.and.arrow.down.on.square") {
                        showingBatchImport = true
                    }
                }
            }
            .sheet(isPresented: $showingBatchImport) {
                NavigationStack { BatchImportView() }
            }
            .refreshable { await library.refreshRosters(force: true) }
            .task { await library.refreshRosters() }
        }
    }

    /// 응원팀을 맨 앞에
    private var orderedTeams: [String] {
        let codes = library.teamCodes
        guard let favorite = settings.favoriteTeamCode, codes.contains(favorite) else { return codes }
        return [favorite] + codes.filter { $0 != favorite }
    }

    @ViewBuilder
    private var rosterStatus: some View {
        HStack(spacing: 8) {
            if library.isRefreshingRosters {
                ProgressView().controlSize(.small)
                Text("1군 명단 업데이트 중…")
            } else if let error = library.rosterError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error)
            } else if let updated = library.rostersUpdatedAt {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("1군 명단 \(updated.formatted(.relative(presentation: .named))) 업데이트 · 당겨서 새로고침")
            } else {
                Image(systemName: "arrow.down.circle")
                Text("당겨서 1군 명단 받기")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// 팀 카드: 팀 색 배지, 1군 인원, 곡 지정 현황
private struct TeamCard: View {
    @Environment(SongLibrary.self) private var library
    let code: String
    let isFavorite: Bool

    var body: some View {
        let theme = TeamTheme.forTeam(code)
        let roster = library.rosters[code]
        let players = roster?.players.map(\.name) ?? library.players(ofTeam: code).map(\.name)
        let withSongs = players.filter { name in
            let assignment = library.assignment(teamCode: code, name: name)
            return assignment.walkUp != nil || assignment.cheer != nil
        }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TeamBadge(code: code, size: 44)
                Spacer()
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.white.opacity(0.2), in: Circle())
                }
            }
            Text(library.teamName(for: code))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 10) {
                Label(roster.map { "1군 \($0.players.count)" } ?? "\(players.count)명", systemImage: "person.3.fill")
                Label("\(withSongs)", systemImage: "music.note")
            }
            .font(.caption.bold())
            .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                theme.gradient
                Image(systemName: "baseball")
                    .font(.system(size: 70))
                    .foregroundStyle(.white.opacity(0.08))
                    .offset(x: 14, y: 14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: theme.primary.opacity(0.3), radius: 8, y: 4)
    }
}

struct TeamSongsView: View {
    @Environment(SongLibrary.self) private var library
    let teamCode: String

    @State private var newPlayerName = ""

    var body: some View {
        let roster = library.rosters[teamCode]
        List {
            Section {
                HStack(spacing: 14) {
                    TeamBadge(code: teamCode, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.teamName(for: teamCode)).font(.title2.bold())
                        if let roster {
                            Text("1군 \(roster.players.count)명 · \(rosterDateText(roster)) 경기 엔트리 기준")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("1군 명단을 아직 받지 못했어요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                SongSlotRow(
                    title: "팀 응원가",
                    systemImage: "megaphone.fill",
                    source: library.teamCheers[teamCode]
                ) { library.setTeamCheer($0, teamCode: teamCode) }
            } footer: {
                Text("선수 응원가가 없는 타자가 나오면 팀 응원가를 재생합니다.")
            }

            if let roster {
                ForEach(roster.grouped, id: \.group) { group in
                    Section("\(group.group.displayName) \(group.players.count)") {
                        ForEach(group.players) { player in
                            playerLink(KnownPlayer(
                                teamCode: teamCode,
                                name: player.name,
                                backNumber: player.backNumber ?? library.knownPlayers[SongLibrary.key(teamCode: teamCode, name: player.name)]?.backNumber
                            ))
                        }
                    }
                }
            }

            let others = library.offRosterPlayers(ofTeam: teamCode)
            if !others.isEmpty {
                Section {
                    ForEach(others) { player in
                        playerLink(player)
                    }
                    .onDelete { offsets in
                        offsets.map { others[$0] }.forEach(library.removePlayer)
                    }
                } header: {
                    Text(roster == nil ? "선수" : "1군 엔트리 밖")
                } footer: {
                    if roster != nil {
                        Text("말소·2군·이적 등으로 지금 1군에 없는 선수 중 곡이나 정보를 넣어 둔 선수입니다. 1군에 다시 등록되면 위로 올라갑니다.")
                    }
                }
            }

            Section {
                HStack {
                    TextField("선수 이름 직접 추가", text: $newPlayerName)
                        .onSubmit(addPlayer)
                    Button("추가", action: addPlayer)
                        .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("1군 명단은 각 팀의 가장 최근 경기 엔트리로 자동으로 바뀝니다. 이름은 중계에 나오는 이름과 같아야 합니다.")
            }
        }
        .themedBackground()
        .environment(\.teamTheme, TeamTheme.forTeam(teamCode))
        .navigationTitle(library.teamName(for: teamCode))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await library.refreshRosters(force: true) }
    }

    private func playerLink(_ player: KnownPlayer) -> some View {
        NavigationLink {
            PlayerDetailView(teamCode: teamCode, name: player.name)
        } label: {
            PlayerRow(player: player)
        }
    }

    private func rosterDateText(_ roster: TeamRoster) -> String {
        (roster.gameDate ?? roster.updatedAt).formatted(.dateTime.month().day())
    }

    private func addPlayer() {
        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        library.register(players: [Player(id: "\(teamCode)-\(name)", name: name, teamCode: teamCode)])
        newPlayerName = ""
    }
}

private struct PlayerRow: View {
    @Environment(SongLibrary.self) private var library
    @Environment(\.teamTheme) private var theme
    let player: KnownPlayer

    var body: some View {
        let assignment = library.assignment(teamCode: player.teamCode, name: player.name)
        HStack(spacing: 10) {
            PlayerAvatar(teamCode: player.teamCode, name: player.name, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name).font(.body.weight(.semibold))
                    if let number = player.backNumber {
                        Text("#\(number)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let summary = statsSummary {
                    Text(summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !library.profile(teamCode: player.teamCode, name: player.name).isEmpty {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "figure.walk")
                .foregroundStyle(assignment.walkUp == nil ? Color.secondary.opacity(0.3) : theme.primary)
            Image(systemName: "megaphone")
                .foregroundStyle(assignment.cheer == nil ? Color.secondary.opacity(0.3) : theme.primary)
        }
    }

    /// "타율 .338 · 40홈런" / "평균자책 4.30 · 14승 7패"
    private var statsSummary: String? {
        guard let stats = library.seasonStats(teamCode: player.teamCode, name: player.name) else { return nil }
        let items = Dictionary(stats.displayItems.map { ($0.label, $0.value) }, uniquingKeysWith: { first, _ in first })
        switch stats.kind {
        case .batter:
            return [items["타율"].map { "타율 \($0)" }, items["홈런"].map { "\($0)홈런" }, items["타점"].map { "\($0)타점" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .pitcher:
            return [items["평균자책"].map { "평균자책 \($0)" }, items["승"].flatMap { w in items["패"].map { "\(w)승 \($0)패" } }, items["세이브"].flatMap { $0 == "0" ? nil : "\($0)세" }]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// 곡 하나를 지정하는 줄: Apple Music 검색 / 파일 가져오기 / 미리듣기 / 지우기
struct SongSlotRow: View {
    @Environment(SongLibrary.self) private var library
    @Environment(AudioDirector.self) private var director
    let title: String
    let systemImage: String
    let source: SongSource?
    let onChange: (SongSource?) -> Void

    @State private var searching = false
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            if let source {
                VStack(alignment: .leading) {
                    Text(source.title)
                    Text(source.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("지정되지 않음").foregroundStyle(.secondary)
            }
            HStack {
                Menu {
                    Button("Apple Music에서 찾기", systemImage: "music.note") { searching = true }
                    Button("파일에서 가져오기", systemImage: "folder") { importing = true }
                } label: {
                    Label(source == nil ? "지정" : "변경", systemImage: "plus.circle")
                }
                if let source {
                    Button("미리듣기", systemImage: "play.circle") { director.preview(source) }
                    Button("정지", systemImage: "stop.circle") { director.stopAll() }
                    Spacer()
                    Button("지우기", systemImage: "trash", role: .destructive) { onChange(nil) }
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.title3)
            if let importError {
                Text(importError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $searching) {
            NavigationStack {
                AppleMusicSearchView { picked in
                    onChange(picked)
                    searching = false
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            do {
                onChange(try library.importFile(at: result.get()))
                importError = nil
            } catch {
                importError = "가져오기 실패: \(error.localizedDescription)"
            }
        }
    }
}
