import HomefieldCore
import SwiftUI
import UniformTypeIdentifiers

/// 파일 이름 규칙으로 등장곡·응원가를 한 번에 가져오기
struct BatchImportView: View {
    @Environment(SongLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var picking = false
    @State private var working = false
    @State private var report: BatchImportReport?
    @State private var pickError: String?

    var body: some View {
        List {
            if let report {
                reportSections(report)
            } else {
                guideSections
            }
        }
        .themedBackground()
        .navigationTitle("한 번에 가져오기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(report == nil ? "닫기" : "완료") { dismiss() }
            }
        }
        .overlay {
            if working {
                ProgressView("가져오는 중…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.folder, .audio, .image, .json],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                run(urls)
            case .failure(let error):
                pickError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var guideSections: some View {
        Section {
            Button {
                picking = true
            } label: {
                Label("폴더 또는 파일 선택", systemImage: "folder.badge.plus")
                    .font(.headline)
            }
            if let pickError {
                Text(pickError).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("폴더를 고르면 안의 파일(하위 폴더 포함)을 모두 가져옵니다. zip 파일은 파일 앱에서 눌러 먼저 압축을 풀어 주세요.")
        }

        Section {
            example("SS_구자욱_등장곡.mp3", "삼성 구자욱 등장곡")
            example("SS_구자욱_응원가.m4a", "삼성 구자욱 응원가")
            example("SS_팀응원가.mp3", "삼성 팀 응원가")
            example("SS_구자욱.jpg", "삼성 구자욱 사진 (SS_구자욱_사진.jpg 도 가능)")
            example("삼성_구자욱_등장곡.mp3", "팀은 이름으로 써도 돼요")
        } header: {
            Text("파일 이름 규칙")
        } footer: {
            Text("팀_선수이름_등장곡 · 응원가 · 사진. 팀은 코드(LG, HT, SS, OB, LT, SK, HH, NC, KT, WO)나 이름(기아, 키움, SSG 등)으로 쓸 수 있습니다. 선수 이름은 중계에 나오는 이름과 같아야 합니다.")
        }

        Section {
            DisclosureGroup("JSON 형식 보기") {
                Text(Self.jsonTemplate)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                ShareLink(item: Self.jsonTemplate, preview: SharePreview("선수정보 예시.json")) {
                    Label("예시 복사·공유", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("선수 정보 (선택)")
        } footer: {
            Text("같은 폴더에 .json 파일을 넣으면 응원 동작, 응원 구호, 응원가 변천사, 팀 이력도 함께 가져옵니다.")
        }

        ProfileTemplateSection()

        Section {
            Text("가져온 음악은 이 기기 안에만 저장되고 다른 곳으로 보내지 않습니다. 직접 가진 음원만 개인 용도로 사용해 주세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reportSections(_ report: BatchImportReport) -> some View {
        Section("지정됨 \(report.assigned.count)곡") {
            if report.assigned.isEmpty {
                Text("지정된 곡이 없습니다").foregroundStyle(.secondary)
            }
            ForEach(report.assigned) { line in
                reportRow(line, systemImage: "checkmark.circle.fill", color: .green)
            }
        }
        if !report.profiles.isEmpty {
            Section("선수 정보 \(report.profiles.count)명") {
                ForEach(report.profiles) { line in
                    reportRow(line, systemImage: "text.book.closed.fill", color: .blue)
                }
            }
        }
        if !report.skipped.isEmpty {
            Section("건너뜀 \(report.skipped.count)개") {
                ForEach(report.skipped) { line in
                    reportRow(line, systemImage: "exclamationmark.triangle.fill", color: .orange)
                }
            }
        }
        Section {
            Button("더 가져오기", systemImage: "folder.badge.plus") { picking = true }
        }
    }

    private func reportRow(_ line: BatchImportReport.Line, systemImage: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: systemImage).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(line.title)
                Text(line.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func example(_ fileName: String, _ meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fileName).font(.callout.monospaced())
            Text(meaning).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func run(_ urls: [URL]) {
        working = true
        Task {
            // 진행 표시가 먼저 그려지도록 한 틱 양보
            await Task.yield()
            report = library.importBatch(urls)
            working = false
        }
    }

    static let jsonTemplate = """
    {
      "players": [
        {
          "team": "SS",
          "name": "선수이름",
          "moves": [
            "첫 번째 동작",
            "두 번째 동작"
          ],
          "chant": "짧은 응원 구호",
          "cheerHistory": [
            { "period": "2019", "text": "응원가 설명" }
          ],
          "teamHistory": [
            { "period": "2015–2020", "text": "이전 팀" },
            { "period": "2021–", "text": "현재 팀" }
          ],
          "memo": ""
        }
      ]
    }
    """
}

/// 1군 명단으로 선수 정보 JSON 양식을 만들어 공유한다 (채워서 다시 가져오기)
private struct ProfileTemplateSection: View {
    @Environment(SongLibrary.self) private var library
    @Environment(AppSettings.self) private var settings
    @State private var teamCode: String?
    @State private var fileURL: URL?
    @State private var error: String?

    var body: some View {
        Section {
            Picker("팀", selection: $teamCode) {
                ForEach(library.teamCodes, id: \.self) { code in
                    Text(library.teamName(for: code)).tag(Optional(code))
                }
            }
            Button("양식 만들기", systemImage: "doc.badge.plus", action: makeTemplate)
                .disabled(teamCode == nil)
            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("\(fileURL.lastPathComponent) 공유·저장", systemImage: "square.and.arrow.up")
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("선수 정보 양식")
        } footer: {
            Text("팀의 1군 선수 이름이 채워진 JSON 파일을 만듭니다. 응원 동작·구호·응원가 변천사·팀 이력을 채워서 '폴더 또는 파일 선택'으로 다시 가져오면 한꺼번에 들어갑니다. 이미 입력한 내용은 양식에 그대로 들어 있습니다.")
        }
        .onAppear {
            if teamCode == nil { teamCode = settings.favoriteTeamCode ?? library.teamCodes.first }
        }
        .onChange(of: teamCode) { _, _ in fileURL = nil }
    }

    private func makeTemplate() {
        guard let teamCode else { return }
        let names = library.rosters[teamCode]?.grouped.flatMap { $0.players.map(\.name) }
            ?? library.players(ofTeam: teamCode).map(\.name)
        let rows = names.map { name in
            (teamCode: teamCode, name: name, profile: library.profile(teamCode: teamCode, name: name))
        }
        do {
            let data = try PlayerProfilesFile.template(rows)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(TeamTheme.shortName(for: teamCode))_선수정보.json")
            try data.write(to: url, options: .atomic)
            fileURL = url
            error = names.isEmpty ? "이 팀 선수 명단이 아직 없어요. 응원가 탭에서 당겨서 1군 명단을 받아 주세요." : nil
        } catch {
            self.error = "양식을 만들지 못했습니다: \(error.localizedDescription)"
        }
    }
}
