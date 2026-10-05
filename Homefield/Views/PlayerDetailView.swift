import HomefieldCore
import PhotosUI
import SwiftUI
import UIKit

/// 선수 정보: 기록, 등장곡·응원가, 응원 동작, 응원가 변천사, 팀 이력
struct PlayerDetailView: View {
    @Environment(SongLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let teamCode: String
    let name: String
    /// 라이브 화면에서 열었을 때 오늘 경기 기록
    var today: BattingLine? = nil
    var showsDoneButton = false

    @State private var editing = false
    @State private var confirmingReset = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?

    var body: some View {
        let assignment = library.assignment(teamCode: teamCode, name: name)
        let profile = library.profile(teamCode: teamCode, name: name)
        let watched = library.watchedLine(teamCode: teamCode, name: name)
        let known = library.knownPlayers[SongLibrary.key(teamCode: teamCode, name: name)]

        List {
            Section {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        PlayerAvatar(teamCode: teamCode, name: name, size: 72)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.multicolor)
                                    .background(Circle().fill(.background))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("선수 사진 바꾸기")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.title.bold())
                        Text(library.teamName(for: teamCode))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let number = known?.backNumber {
                        Text("#\(number)")
                            .font(.title2.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                    }
                }
                if library.photoURL(teamCode: teamCode, name: name) != nil {
                    Button("사진 지우기", role: .destructive) {
                        try? library.setPhoto(nil, teamCode: teamCode, name: name)
                    }
                    .font(.footnote)
                }
                if let photoError {
                    Text(photoError).font(.caption).foregroundStyle(.red)
                }
            }

            if let stats = library.seasonStats(teamCode: teamCode, name: name) {
                SeasonStatsSection(stats: stats, teamCode: teamCode)
            }

            recordSection(today: today, watched: watched)

            Section("등장곡 · 응원가") {
                SongSlotRow(title: "등장곡", systemImage: "figure.walk", source: assignment.walkUp) {
                    library.setWalkUp($0, teamCode: teamCode, name: name)
                }
                SongSlotRow(title: "응원가", systemImage: "megaphone", source: assignment.cheer) {
                    library.setCheer($0, teamCode: teamCode, name: name)
                }
            }

            Section("응원 동작") {
                if profile.moves.isEmpty {
                    emptyRow("응원가에 맞춰 하는 동작을 순서대로 적어 두세요.")
                } else {
                    ForEach(Array(profile.moves.enumerated()), id: \.offset) { index, move in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.accentColor, in: Circle())
                            Text(move)
                        }
                    }
                }
                if let chant = profile.chant, !chant.isEmpty {
                    Label(chant, systemImage: "quote.bubble")
                }
            }

            Section("응원가 변천사") {
                timeline(profile.cheerHistory, empty: "응원가가 언제 어떻게 바뀌었는지 기록해 두세요.")
            }

            Section {
                timeline(profile.teamHistory, empty: "거쳐 온 팀을 기록해 두세요.")
            } header: {
                Text("팀 이력")
            } footer: {
                Text("중계 데이터에서 같은 선수가 다른 팀으로 나오면 이적으로 자동 기록됩니다.")
            }

            if let memo = profile.memo, !memo.isEmpty {
                Section("메모") { Text(memo) }
            }
        }
        .themedBackground()
        .environment(\.teamTheme, TeamTheme.forTeam(teamCode))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("편집") { editing = true }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await savePhoto(item) }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                PlayerProfileEditor(teamCode: teamCode, name: name, original: profile)
            }
        }
        .confirmationDialog("관전 기록을 지울까요?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("관전 기록 지우기", role: .destructive) {
                library.resetWatched(teamCode: teamCode, name: name)
            }
        }
    }

    /// 고른 사진을 400px 로 줄여 JPEG 로 저장
    private func savePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                photoError = "사진을 읽지 못했습니다"
                return
            }
            let side: CGFloat = 400
            let scale = min(1, side / max(image.size.width, image.size.height))
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: target).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            try library.setPhoto(resized.jpegData(compressionQuality: 0.85), teamCode: teamCode, name: name)
            photoError = nil
        } catch {
            photoError = "사진 저장 실패: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func recordSection(today: BattingLine?, watched: BattingLine) -> some View {
        Section {
            if let today, !today.isEmpty {
                recordRow(title: "오늘", line: today)
            }
            if watched.isEmpty {
                emptyRow("홈구장으로 경기를 보면 이 선수의 타석 결과가 쌓입니다.")
            } else {
                recordRow(title: "관전 누적", line: watched)
                Button("관전 기록 지우기", role: .destructive) { confirmingReset = true }
                    .font(.footnote)
            }
        } header: {
            Text("관전 기록")
        } footer: {
            Text("이 앱으로 본 경기에서 집계한 기록입니다. 시즌 공식 기록과 다를 수 있습니다.")
        }
    }

    private func recordRow(title: String, line: BattingLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text("타율 \(line.averageText)")
                    .font(.headline.monospacedDigit())
            }
            Text(line.summary)
                .foregroundStyle(.secondary)
            Text(line.results.suffix(20).map(\.emoji).joined(separator: " "))
                .font(.caption)
                .lineLimit(2)
                .accessibilityLabel(line.results.suffix(20).map(\.displayName).joined(separator: ", "))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func timeline(_ entries: [TimelineEntry], empty: String) -> some View {
        if entries.isEmpty {
            emptyRow(empty)
        } else {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.period)
                        .font(.callout.monospacedDigit().bold())
                        .frame(minWidth: 72, alignment: .leading)
                    Text(entry.text)
                }
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// 선수 정보 편집
struct PlayerProfileEditor: View {
    @Environment(SongLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let teamCode: String
    let name: String

    private struct Line: Identifiable {
        let id = UUID()
        var text: String
    }

    @State private var moves: [Line]
    @State private var chant: String
    @State private var cheerHistory: [TimelineEntry]
    @State private var teamHistory: [TimelineEntry]
    @State private var memo: String

    init(teamCode: String, name: String, original: PlayerProfile) {
        self.teamCode = teamCode
        self.name = name
        _moves = State(initialValue: original.moves.map { Line(text: $0) })
        _chant = State(initialValue: original.chant ?? "")
        _cheerHistory = State(initialValue: original.cheerHistory)
        _teamHistory = State(initialValue: original.teamHistory)
        _memo = State(initialValue: original.memo ?? "")
    }

    var body: some View {
        Form {
            Section {
                ForEach($moves) { $move in
                    TextField("동작 설명", text: $move.text, axis: .vertical)
                }
                .onDelete { moves.remove(atOffsets: $0) }
                .onMove { moves.move(fromOffsets: $0, toOffset: $1) }
                Button("동작 추가", systemImage: "plus") { moves.append(Line(text: "")) }
            } header: {
                Text("응원 동작 (순서대로)")
            } footer: {
                Text("예: 양손 들고 박수 두 번 → 오른손 앞으로 뻗으며 \"안타!\"")
            }

            Section("응원 구호") {
                TextField("예: 구자욱 안타!", text: $chant, axis: .vertical)
            }

            timelineSection("응원가 변천사", entries: $cheerHistory, periodHint: "2019", textHint: "어떤 응원가였는지")
            timelineSection("팀 이력", entries: $teamHistory, periodHint: "2012–2019", textHint: "팀 이름")

            Section("메모") {
                TextField("자유롭게 적어 두세요", text: $memo, axis: .vertical)
            }
        }
        .navigationTitle("\(name) 정보 편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    save()
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
    }

    private func timelineSection(
        _ title: String,
        entries: Binding<[TimelineEntry]>,
        periodHint: String,
        textHint: String
    ) -> some View {
        Section(title) {
            ForEach(entries) { $entry in
                HStack {
                    TextField(periodHint, text: $entry.period)
                        .frame(maxWidth: 110)
                        .font(.callout.monospacedDigit())
                    TextField(textHint, text: $entry.text, axis: .vertical)
                }
            }
            .onDelete { entries.wrappedValue.remove(atOffsets: $0) }
            .onMove { entries.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
            Button("추가", systemImage: "plus") {
                entries.wrappedValue.append(TimelineEntry(period: "", text: ""))
            }
        }
    }

    private func save() {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        func cleanTimeline(_ entries: [TimelineEntry]) -> [TimelineEntry] {
            entries
                .map { TimelineEntry(period: clean($0.period), text: clean($0.text)) }
                .filter { !$0.period.isEmpty || !$0.text.isEmpty }
        }
        let profile = PlayerProfile(
            moves: moves.map { clean($0.text) }.filter { !$0.isEmpty },
            chant: clean(chant).isEmpty ? nil : clean(chant),
            cheerHistory: cleanTimeline(cheerHistory),
            teamHistory: cleanTimeline(teamHistory),
            memo: clean(memo).isEmpty ? nil : clean(memo)
        )
        library.setProfile(profile, teamCode: teamCode, name: name)
    }
}

/// 네이버 중계에 함께 오는 이번 시즌 공식 기록
private struct SeasonStatsSection: View {
    let stats: SeasonStats
    let teamCode: String

    var body: some View {
        let theme = TeamTheme.forTeam(teamCode)
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                ForEach(stats.displayItems) { item in
                    VStack(spacing: 2) {
                        Text(item.value)
                            .font(.title3.monospacedDigit().bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(item.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("\(Calendar.current.component(.year, from: stats.updatedAt)) 시즌 공식 기록 (\(stats.kind == .batter ? "타자" : "투수"))")
        } footer: {
            Text("네이버 스포츠 문자중계 기준 · \(stats.updatedAt.formatted(date: .abbreviated, time: .shortened)) 업데이트")
        }
    }
}
