import Foundation
import HomefieldCore

/// 파일 이름 규칙으로 여러 곡과 선수 정보 JSON 을 한 번에 가져온 결과
struct BatchImportReport {
    struct Line: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    var assigned: [Line] = []
    var profiles: [Line] = []
    var skipped: [Line] = []

    var isEmpty: Bool { assigned.isEmpty && profiles.isEmpty && skipped.isEmpty }
}

extension SongLibrary {
    /// 고른 파일·폴더를 모두 훑어서
    /// - `팀_선수_등장곡.mp3` 형식의 음악 파일은 해당 선수에게 지정하고
    /// - `.json` 파일은 선수 정보(응원 동작, 변천사, 팀 이력)로 읽는다.
    func importBatch(_ urls: [URL]) -> BatchImportReport {
        var report = BatchImportReport()
        var claimed = Set<String>()

        for root in urls {
            let accessing = root.startAccessingSecurityScopedResource()
            defer { if accessing { root.stopAccessingSecurityScopedResource() } }

            for file in Self.files(in: root) {
                let name = file.lastPathComponent
                if file.pathExtension.lowercased() == "json" {
                    importProfiles(from: file, into: &report)
                } else if SongFileNameParser.isAudio(name) {
                    importSong(file, claimed: &claimed, into: &report)
                } else {
                    report.skipped.append(.init(title: name, detail: "음악 파일(mp3, m4a 등)이나 .json 이 아닙니다"))
                }
            }
        }
        return report
    }

    private func importSong(_ file: URL, claimed: inout Set<String>, into report: inout BatchImportReport) {
        let fileName = file.lastPathComponent
        guard let parsed = SongFileNameParser.parse(fileName) else {
            report.skipped.append(.init(
                title: fileName,
                detail: "이름 규칙과 다릅니다. 예: SS_구자욱_등장곡.mp3, SS_팀응원가.mp3"
            ))
            return
        }

        let team = teamName(for: parsed.teamCode)
        let target = "\(parsed.teamCode)|\(parsed.playerName ?? "")|\(parsed.kind.rawValue)"
        let label: String = switch parsed.kind {
        case .walkUp: "등장곡"
        case .cheer: "응원가"
        case .teamCheer: "팀 응원가"
        }
        let who = parsed.playerName.map { "\(team) \($0)" } ?? team

        guard claimed.insert(target).inserted else {
            report.skipped.append(.init(title: fileName, detail: "\(who) \(label) 파일이 이미 있어서 건너뜀"))
            return
        }

        do {
            let title = parsed.playerName.map { "\($0) \(label)" } ?? "\(team) \(label)"
            let source = try importFile(at: file, title: title)
            switch parsed.kind {
            case .walkUp:
                setWalkUp(source, teamCode: parsed.teamCode, name: parsed.playerName ?? "")
            case .cheer:
                setCheer(source, teamCode: parsed.teamCode, name: parsed.playerName ?? "")
            case .teamCheer:
                setTeamCheer(source, teamCode: parsed.teamCode)
            }
            report.assigned.append(.init(title: who, detail: label))
        } catch {
            report.skipped.append(.init(title: fileName, detail: "복사 실패: \(error.localizedDescription)"))
        }
    }

    private func importProfiles(from file: URL, into report: inout BatchImportReport) {
        let fileName = file.lastPathComponent
        do {
            let data = try Data(contentsOf: file)
            let decoded = try PlayerProfilesFile.decode(data)
            for entry in decoded.players {
                var profile = self.profile(teamCode: entry.teamCode, name: entry.name)
                profile.merge(entry.profile)
                setProfile(profile, teamCode: entry.teamCode, name: entry.name)
                report.profiles.append(.init(
                    title: "\(teamName(for: entry.teamCode)) \(entry.name)",
                    detail: Self.profileSummary(entry.profile)
                ))
            }
        } catch {
            report.skipped.append(.init(title: fileName, detail: "선수 정보 JSON 을 읽지 못했습니다: \(Self.describe(error))"))
        }
    }

    /// 폴더면 안의 파일을 모두(하위 폴더 포함), 파일이면 그 파일 하나
    private static func files(in url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var files: [URL] = []
        while let next = enumerator?.nextObject() as? URL {
            if (try? next.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(next)
            }
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func profileSummary(_ profile: PlayerProfile) -> String {
        var parts: [String] = []
        if !profile.moves.isEmpty { parts.append("응원 동작 \(profile.moves.count)단계") }
        if !profile.cheerHistory.isEmpty { parts.append("변천사 \(profile.cheerHistory.count)개") }
        if !profile.teamHistory.isEmpty { parts.append("팀 이력 \(profile.teamHistory.count)개") }
        if !(profile.chant ?? "").isEmpty { parts.append("구호") }
        return parts.isEmpty ? "추가된 정보 없음" : parts.joined(separator: " · ")
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context):
            return context.debugDescription
        case .keyNotFound(let key, _):
            return "'\(key.stringValue)' 항목이 없습니다"
        @unknown default:
            return error.localizedDescription
        }
    }
}
