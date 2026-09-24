import Foundation
import HomefieldCore
import Observation

enum SongSource: Codable, Hashable {
    case appleMusic(id: String, title: String, artist: String?)
    case localFile(fileName: String, title: String)

    var title: String {
        switch self {
        case .appleMusic(_, let title, _), .localFile(_, let title): title
        }
    }

    var subtitle: String {
        switch self {
        case .appleMusic(_, _, let artist): ["Apple Music", artist].compactMap { $0 }.joined(separator: " · ")
        case .localFile: "내 파일"
        }
    }
}

struct SongAssignment: Codable, Hashable {
    /// 등장곡
    var walkUp: SongSource?
    /// 선수 응원가
    var cheer: SongSource?
}

struct KnownPlayer: Codable, Hashable, Identifiable {
    var teamCode: String
    var name: String
    var backNumber: String?

    var id: String { SongLibrary.key(teamCode: teamCode, name: name) }
}

/// 선수별 등장곡/응원가 지정. 기기 안에만 저장된다.
///
/// 선수 키는 "팀코드|이름" 이라서 시즌이 바뀌어도(선수 코드가 없어도) 유지된다.
@MainActor
@Observable
final class SongLibrary {
    private(set) var assignments: [String: SongAssignment] = [:]
    /// 선수 응원가가 없을 때 쓰는 팀 응원가
    private(set) var teamCheers: [String: SongSource] = [:]
    private(set) var knownPlayers: [String: KnownPlayer] = [:]
    private(set) var teamNames: [String: String] = [:]

    private let storeURL: URL
    let songsDirectory: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = support.appendingPathComponent("song-library.json")
        songsDirectory = documents.appendingPathComponent("Songs", isDirectory: true)
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: songsDirectory, withIntermediateDirectories: true)
        load()
        for team in KBOTeams.all where teamNames[team.code] == nil {
            teamNames[team.code] = team.name
        }
    }

    nonisolated static func key(teamCode: String, name: String) -> String {
        "\(teamCode)|\(name)"
    }

    func assignment(teamCode: String, name: String) -> SongAssignment {
        assignments[Self.key(teamCode: teamCode, name: name)] ?? SongAssignment()
    }

    func assignment(for player: Player) -> SongAssignment {
        assignment(teamCode: player.teamCode, name: player.name)
    }

    func cheer(for player: Player) -> SongSource? {
        assignment(for: player).cheer ?? teamCheers[player.teamCode]
    }

    func teamName(for code: String) -> String {
        teamNames[code] ?? KBOTeams.name(for: code) ?? code
    }

    func players(ofTeam code: String) -> [KnownPlayer] {
        knownPlayers.values
            .filter { $0.teamCode == code }
            .sorted { $0.name < $1.name }
    }

    var teamCodes: [String] {
        Set(teamNames.keys).union(knownPlayers.values.map(\.teamCode))
            .sorted { teamName(for: $0) < teamName(for: $1) }
    }

    // MARK: 변경

    func setWalkUp(_ source: SongSource?, teamCode: String, name: String) {
        update(teamCode: teamCode, name: name) { $0.walkUp = source }
    }

    func setCheer(_ source: SongSource?, teamCode: String, name: String) {
        update(teamCode: teamCode, name: name) { $0.cheer = source }
    }

    func setTeamCheer(_ source: SongSource?, teamCode: String) {
        teamCheers[teamCode] = source
        save()
    }

    func register(team: Team) {
        guard teamNames[team.code] != team.name, !team.code.isEmpty else { return }
        teamNames[team.code] = team.name
        save()
    }

    func register(players: [Player]) {
        var changed = false
        for player in players where !player.teamCode.isEmpty {
            let known = KnownPlayer(teamCode: player.teamCode, name: player.name, backNumber: player.backNumber)
            if knownPlayers[known.id] != known {
                knownPlayers[known.id] = known
                changed = true
            }
        }
        if changed { save() }
    }

    func removePlayer(_ player: KnownPlayer) {
        knownPlayers[player.id] = nil
        assignments[player.id] = nil
        save()
    }

    /// 파일 앱에서 고른 음악 파일을 앱 안으로 복사한다
    func importFile(at url: URL) throws -> SongSource {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileName = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)"
        try FileManager.default.copyItem(at: url, to: songsDirectory.appendingPathComponent(fileName))
        return .localFile(fileName: fileName, title: url.deletingPathExtension().lastPathComponent)
    }

    func fileURL(for fileName: String) -> URL {
        songsDirectory.appendingPathComponent(fileName)
    }

    private func update(teamCode: String, name: String, _ change: (inout SongAssignment) -> Void) {
        let key = Self.key(teamCode: teamCode, name: name)
        var assignment = assignments[key] ?? SongAssignment()
        change(&assignment)
        assignments[key] = assignment
        if knownPlayers[key] == nil {
            knownPlayers[key] = KnownPlayer(teamCode: teamCode, name: name)
        }
        save()
    }

    // MARK: 저장

    private struct Stored: Codable {
        var assignments: [String: SongAssignment]
        var teamCheers: [String: SongSource]
        var knownPlayers: [String: KnownPlayer]
        var teamNames: [String: String]
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: storeURL),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }
        assignments = stored.assignments
        teamCheers = stored.teamCheers
        knownPlayers = stored.knownPlayers
        teamNames = stored.teamNames
    }

    private func save() {
        let stored = Stored(assignments: assignments, teamCheers: teamCheers, knownPlayers: knownPlayers, teamNames: teamNames)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
