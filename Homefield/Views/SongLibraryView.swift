import HomefieldCore
import SwiftUI
import UniformTypeIdentifiers

struct SongLibraryView: View {
    @Environment(SongLibrary.self) private var library

    var body: some View {
        NavigationStack {
            List(library.teamCodes, id: \.self) { code in
                NavigationLink(value: code) {
                    HStack {
                        Text(library.teamName(for: code))
                        Spacer()
                        Text("\(library.players(ofTeam: code).count)명")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("등장곡 · 응원가")
            .navigationDestination(for: String.self) { code in
                TeamSongsView(teamCode: code)
            }
        }
    }
}

struct TeamSongsView: View {
    @Environment(SongLibrary.self) private var library
    let teamCode: String

    @State private var newPlayerName = ""
    @State private var pickingTeamCheer = false

    var body: some View {
        List {
            Section {
                SongSlotRow(
                    title: "팀 응원가",
                    systemImage: "megaphone.fill",
                    source: library.teamCheers[teamCode]
                ) { library.setTeamCheer($0, teamCode: teamCode) }
            } footer: {
                Text("선수 응원가가 없는 타자가 나오면 팀 응원가를 재생합니다.")
            }

            Section {
                ForEach(library.players(ofTeam: teamCode)) { player in
                    NavigationLink {
                        PlayerSongEditor(teamCode: teamCode, name: player.name)
                    } label: {
                        PlayerRow(player: player)
                    }
                }
                .onDelete { offsets in
                    let players = library.players(ofTeam: teamCode)
                    offsets.map { players[$0] }.forEach(library.removePlayer)
                }

                HStack {
                    TextField("선수 이름 추가", text: $newPlayerName)
                        .onSubmit(addPlayer)
                    Button("추가", action: addPlayer)
                        .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("선수")
            } footer: {
                Text("경기를 보면 라인업의 선수들이 자동으로 추가됩니다. 이름은 중계에 나오는 이름과 같아야 합니다.")
            }
        }
        .navigationTitle(library.teamName(for: teamCode))
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
    let player: KnownPlayer

    var body: some View {
        let assignment = library.assignment(teamCode: player.teamCode, name: player.name)
        HStack {
            if let number = player.backNumber {
                Text("#\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
            }
            Text(player.name)
            Spacer()
            Image(systemName: "figure.walk")
                .foregroundStyle(assignment.walkUp == nil ? Color.secondary.opacity(0.3) : Color.accentColor)
            Image(systemName: "megaphone")
                .foregroundStyle(assignment.cheer == nil ? Color.secondary.opacity(0.3) : Color.accentColor)
        }
    }
}

struct PlayerSongEditor: View {
    @Environment(SongLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let teamCode: String
    let name: String

    var body: some View {
        let assignment = library.assignment(teamCode: teamCode, name: name)
        List {
            Section {
                SongSlotRow(title: "등장곡", systemImage: "figure.walk", source: assignment.walkUp) {
                    library.setWalkUp($0, teamCode: teamCode, name: name)
                }
            } footer: {
                Text("타자가 타석에 들어서면 먼저 재생됩니다. 재생 시간은 설정에서 바꿀 수 있어요.")
            }
            Section {
                SongSlotRow(title: "응원가", systemImage: "megaphone", source: assignment.cheer) {
                    library.setCheer($0, teamCode: teamCode, name: name)
                }
            } footer: {
                Text("등장곡 다음에 타석이 끝날 때까지 반복 재생됩니다.")
            }
        }
        .navigationTitle("\(name) · \(library.teamName(for: teamCode))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("완료") { dismiss() }
            }
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
