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
    /// 팀 이력, 메모
    private(set) var profiles: [String: PlayerProfile] = [:]
    /// 이 앱으로 본 경기에서 쌓인 타석 기록
    private(set) var watched: [String: BattingLine] = [:]
    /// 데이터 제공자의 선수 코드 → 선수 키 (이적 감지용)
    private var providerIds: [String: String] = [:]
    /// 선수 키 → 사진 파일 이름
    private(set) var photos: [String: String] = [:]
    /// 제공자 선수 코드 → 시즌 공식 기록 (중계에서 받은 최신 값)
    private(set) var officialStats: [String: SeasonStats] = [:]
    /// 팀 코드 → 1군 엔트리 (팀마다 가장 최근 경기 기준)
    private(set) var rosters: [String: TeamRoster] = [:]
    private(set) var rostersUpdatedAt: Date?
    private(set) var isRefreshingRosters = false
    private(set) var rosterError: String?
    /// 선수 코드 → KBO 공식 경력 (팀 이력)
    private(set) var careers: [String: KBOPlayerCareer] = [:]

    private let storeURL: URL
    let songsDirectory: URL
    let photosDirectory: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = support.appendingPathComponent("song-library.json")
        songsDirectory = documents.appendingPathComponent("Songs", isDirectory: true)
        photosDirectory = documents.appendingPathComponent("Photos", isDirectory: true)
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: songsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
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

    func profile(teamCode: String, name: String) -> PlayerProfile {
        profiles[Self.key(teamCode: teamCode, name: name)] ?? PlayerProfile()
    }

    func photoURL(teamCode: String, name: String) -> URL? {
        photos[Self.key(teamCode: teamCode, name: name)].map { photosDirectory.appendingPathComponent($0) }
    }

    /// 사진 데이터를 저장한다 (JPEG/PNG/HEIC 등 이미지 데이터). nil 이면 지운다.
    func setPhoto(_ data: Data?, fileExtension: String = "jpg", teamCode: String, name: String) throws {
        let key = Self.key(teamCode: teamCode, name: name)
        if let old = photos[key] {
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(old))
            photos[key] = nil
        }
        if let data {
            let fileName = "\(UUID().uuidString).\(fileExtension)"
            try data.write(to: photosDirectory.appendingPathComponent(fileName), options: .atomic)
            photos[key] = fileName
            if knownPlayers[key] == nil {
                knownPlayers[key] = KnownPlayer(teamCode: teamCode, name: name)
            }
        }
        save()
    }

    /// 선수 키 → 데이터 제공자의 선수 코드 (네이버·KBO 공통)
    func providerID(teamCode: String, name: String) -> String? {
        let key = Self.key(teamCode: teamCode, name: name)
        return providerIds.first { $0.value == key }?.key
    }

    func career(teamCode: String, name: String) -> KBOPlayerCareer? {
        providerID(teamCode: teamCode, name: name).flatMap { careers[$0] }
    }

    /// KBO 공식 기록에서 연도별 소속 팀을 받는다 (7일에 한 번)
    func loadCareer(teamCode: String, name: String) async {
        guard let id = providerID(teamCode: teamCode, name: name) else { return }
        if let cached = careers[id], Date().timeIntervalSince(cached.fetchedAt) < 7 * 24 * 60 * 60 { return }
        let rosterPlayer = rosters[teamCode]?.players.first(where: { $0.id == id })
        let isPitcher = officialStats[id]?.kind == .pitcher
            || TeamRoster.Group(position: rosterPlayer?.position) == .pitcher
        guard let career = try? await KBOPlayerService().career(playerId: id, isPitcher: isPitcher) else { return }
        careers[id] = career
        save()
    }

    /// 선수의 시즌 공식 기록 (중계에서 한 번이라도 받은 적이 있으면)
    func seasonStats(teamCode: String, name: String) -> SeasonStats? {
        let key = Self.key(teamCode: teamCode, name: name)
        return providerIds.lazy
            .filter { $0.value == key }
            .compactMap { self.officialStats[$0.key] }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func record(seasonStats stats: [SeasonStats]) {
        var changed = false
        for item in stats where officialStats[item.playerId].map({ !$0.sameNumbers(as: item) }) ?? true {
            officialStats[item.playerId] = item
            changed = true
        }
        if changed { save() }
    }

    func watchedLine(teamCode: String, name: String) -> BattingLine {
        watched[Self.key(teamCode: teamCode, name: name)] ?? BattingLine()
    }

    func teamName(for code: String) -> String {
        teamNames[code] ?? KBOTeams.name(for: code) ?? code
    }

    func players(ofTeam code: String) -> [KnownPlayer] {
        knownPlayers.values
            .filter { $0.teamCode == code }
            .sorted { $0.name < $1.name }
    }

    /// KBO 10개 구단만 (데모 팀 제외)
    var teamCodes: [String] {
        KBOTeams.all.map(\.code).sorted { teamName(for: $0) < teamName(for: $1) }
    }

    nonisolated static func isKBOTeam(_ code: String) -> Bool {
        KBOTeams.all.contains { $0.code == code }
    }

    /// 곡·사진·응원 정보 중 하나라도 직접 넣은 선수
    func hasUserData(_ player: KnownPlayer) -> Bool {
        let assignment = assignments[player.id]
        return assignment?.walkUp != nil || assignment?.cheer != nil
            || !(profiles[player.id]?.isEmpty ?? true) || photos[player.id] != nil
    }

    /// 1군 엔트리 밖이지만 직접 넣은 정보가 있는 선수 (2군·말소·이적 등)
    func offRosterPlayers(ofTeam code: String) -> [KnownPlayer] {
        let roster = rosters[code]
        return players(ofTeam: code).filter { player in
            !(roster?.contains(name: player.name) ?? false) && (roster == nil || hasUserData(player))
        }
    }

    // MARK: 1군 엔트리

    /// 각 팀 최근 경기 엔트리로 1군 명단을 새로 받고, 팀별 시즌 기록도 함께 받는다
    func refreshRosters(force: Bool = false) async {
        if isRefreshingRosters { return }
        if !force, let rostersUpdatedAt, Date().timeIntervalSince(rostersUpdatedAt) < 3 * 60 * 60 { return }
        isRefreshingRosters = true
        defer { isRefreshingRosters = false }

        let provider = NaverSportsProvider()
        let collected = await RosterCollector(provider: provider).collect()
        guard !collected.isEmpty else {
            rosterError = "1군 명단을 받지 못했습니다. 네트워크를 확인해 주세요."
            return
        }
        rosterError = nil
        for (code, roster) in collected {
            rosters[code] = roster
            register(players: roster.players)
        }
        rostersUpdatedAt = Date()
        save()

        let season = Calendar(identifier: .gregorian).component(.year, from: Date())
        await withTaskGroup(of: [SeasonStats].self) { group in
            for code in collected.keys {
                group.addTask { (try? await provider.teamSeasonStats(teamCode: code, season: season)) ?? [] }
            }
            for await stats in group {
                record(seasonStats: stats)
            }
        }
    }

    // MARK: 변경

    func setWalkUp(_ source: SongSource?, teamCode: String, name: String) {
        update(teamCode: teamCode, name: name) { $0.walkUp = source }
    }

    func setCheer(_ source: SongSource?, teamCode: String, name: String) {
        update(teamCode: teamCode, name: name) { $0.cheer = source }
    }

    func setTeamCheer(_ source: SongSource?, teamCode: String) {
        let old = teamCheers[teamCode]
        teamCheers[teamCode] = source
        deleteIfUnused(old)
        save()
    }

    func setProfile(_ profile: PlayerProfile, teamCode: String, name: String) {
        let key = Self.key(teamCode: teamCode, name: name)
        profiles[key] = profile.isEmpty ? nil : profile
        if knownPlayers[key] == nil {
            knownPlayers[key] = KnownPlayer(teamCode: teamCode, name: name)
        }
        save()
    }

    func recordPlateAppearance(_ kind: PlayKind, for player: Player) {
        let key = Self.key(teamCode: player.teamCode, name: player.name)
        var line = watched[key] ?? BattingLine()
        line.record(kind)
        watched[key] = line
        save()
    }

    func resetWatched(teamCode: String, name: String) {
        watched[Self.key(teamCode: teamCode, name: name)] = nil
        save()
    }

    func register(team: Team) {
        guard Self.isKBOTeam(team.code), teamNames[team.code] != team.name else { return }
        teamNames[team.code] = team.name
        save()
    }

    func register(players: [Player]) {
        var changed = false
        for player in players where Self.isKBOTeam(player.teamCode) {
            let id = Self.key(teamCode: player.teamCode, name: player.name)
            let known = KnownPlayer(
                teamCode: player.teamCode,
                name: player.name,
                backNumber: player.backNumber ?? knownPlayers[id]?.backNumber
            )
            if knownPlayers[known.id] != known {
                knownPlayers[known.id] = known
                changed = true
            }
            // 같은 선수 코드가 다른 팀으로 나오면 이적으로 보고 팀 이력에 남긴다
            if let providerId = providerID(of: player) {
                if let previousKey = providerIds[providerId], previousKey != known.id,
                   let previous = knownPlayers[previousKey], previous.teamCode != player.teamCode {
                    recordTransfer(from: previous, to: known)
                }
                if providerIds[providerId] != known.id {
                    providerIds[providerId] = known.id
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    /// 제공자가 준 진짜 선수 코드만 (없으면 "팀코드-이름" 으로 만들어진 id)
    private func providerID(of player: Player) -> String? {
        player.id.hasPrefix("\(player.teamCode)-") ? nil : player.id
    }

    private func recordTransfer(from previous: KnownPlayer, to current: KnownPlayer) {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let newTeam = teamName(for: current.teamCode)
        let old = profiles[previous.id] ?? PlayerProfile()
        var profile = profiles[current.id] ?? PlayerProfile()
        if profile.teamHistory.isEmpty {
            profile.teamHistory = old.teamHistory.isEmpty
                ? [TimelineEntry(period: "~\(year)", text: teamName(for: previous.teamCode))]
                : old.teamHistory
        }
        if profile.teamHistory.last?.text.contains(newTeam) != true {
            profile.teamHistory.append(TimelineEntry(period: "\(year)~", text: "\(newTeam) (이적)"))
        }
        profiles[current.id] = profile
    }

    func removePlayer(_ player: KnownPlayer) {
        let old = assignments[player.id]
        knownPlayers[player.id] = nil
        assignments[player.id] = nil
        profiles[player.id] = nil
        watched[player.id] = nil
        if let photo = photos.removeValue(forKey: player.id) {
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(photo))
        }
        deleteIfUnused(old?.walkUp)
        deleteIfUnused(old?.cheer)
        save()
    }

    /// 파일 앱에서 고른 음악 파일을 앱 안으로 복사한다
    func importFile(at url: URL, title: String? = nil) throws -> SongSource {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileName = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)"
        try FileManager.default.copyItem(at: url, to: songsDirectory.appendingPathComponent(fileName))
        return .localFile(fileName: fileName, title: title ?? url.deletingPathExtension().lastPathComponent)
    }

    /// 더 이상 어디에도 지정되지 않은 가져온 파일은 지운다
    private func deleteIfUnused(_ source: SongSource?) {
        guard let source, case .localFile(let fileName, _) = source else { return }
        let inUse = teamCheers.values.contains(source)
            || assignments.values.contains { $0.walkUp == source || $0.cheer == source }
        if !inUse {
            try? FileManager.default.removeItem(at: fileURL(for: fileName))
        }
    }

    func fileURL(for fileName: String) -> URL {
        songsDirectory.appendingPathComponent(fileName)
    }

    private func update(teamCode: String, name: String, _ change: (inout SongAssignment) -> Void) {
        let key = Self.key(teamCode: teamCode, name: name)
        let old = assignments[key] ?? SongAssignment()
        var assignment = old
        change(&assignment)
        assignments[key] = assignment
        if knownPlayers[key] == nil {
            knownPlayers[key] = KnownPlayer(teamCode: teamCode, name: name)
        }
        if old.walkUp != assignment.walkUp { deleteIfUnused(old.walkUp) }
        if old.cheer != assignment.cheer { deleteIfUnused(old.cheer) }
        save()
    }

    // MARK: 저장

    private struct Stored: Codable {
        var assignments: [String: SongAssignment]
        var teamCheers: [String: SongSource]
        var knownPlayers: [String: KnownPlayer]
        var teamNames: [String: String]
        // 나중에 추가된 항목은 예전 저장 파일에 없으므로 optional
        var profiles: [String: PlayerProfile]?
        var watched: [String: BattingLine]?
        var providerIds: [String: String]?
        var photos: [String: String]?
        var officialStats: [String: SeasonStats]?
        var rosters: [String: TeamRoster]?
        var rostersUpdatedAt: Date?
        var careers: [String: KBOPlayerCareer]?
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
        profiles = stored.profiles ?? [:]
        watched = stored.watched ?? [:]
        providerIds = stored.providerIds ?? [:]
        photos = stored.photos ?? [:]
        officialStats = stored.officialStats ?? [:]
        rosters = stored.rosters ?? [:]
        rostersUpdatedAt = stored.rostersUpdatedAt
        careers = stored.careers ?? [:]
        // 예전 버전에서 쌓인 데모 팀 선수는 직접 넣은 정보가 없으면 정리
        for (key, player) in knownPlayers where !Self.isKBOTeam(player.teamCode) && !hasUserData(player) {
            knownPlayers[key] = nil
        }
        for code in teamNames.keys where !Self.isKBOTeam(code) {
            teamNames[code] = nil
        }
    }

    private func save() {
        let stored = Stored(
            assignments: assignments,
            teamCheers: teamCheers,
            knownPlayers: knownPlayers,
            teamNames: teamNames,
            profiles: profiles,
            watched: watched,
            providerIds: providerIds,
            photos: photos,
            officialStats: officialStats,
            rosters: rosters,
            rostersUpdatedAt: rostersUpdatedAt,
            careers: careers
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
