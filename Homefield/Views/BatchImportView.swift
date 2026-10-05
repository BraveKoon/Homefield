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
}
