import MusicKit
import SwiftUI

struct AppleMusicSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (SongSource) -> Void

    @State private var query = ""
    @State private var songs: MusicItemCollection<Song> = []
    @State private var status = MusicAuthorization.currentStatus
    @State private var errorMessage: String?

    var body: some View {
        List {
            if status != .authorized {
                Section {
                    Button("Apple Music 접근 허용") {
                        Task { status = await MusicAuthorization.request() }
                    }
                } footer: {
                    Text("Apple Music 곡을 재생하려면 권한과 Apple Music 구독이 필요합니다.")
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(songs) { song in
                Button {
                    onPick(.appleMusic(id: song.id.rawValue, title: song.title, artist: song.artistName))
                } label: {
                    HStack {
                        if let artwork = song.artwork {
                            ArtworkImage(artwork, width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        VStack(alignment: .leading) {
                            Text(song.title).foregroundStyle(.primary)
                            Text(song.artistName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "곡 이름, 가수, 선수 응원가…")
        .task(id: query) { await search() }
        .navigationTitle("Apple Music")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, status == .authorized else {
            songs = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350)) // 타이핑 디바운스
        guard !Task.isCancelled else { return }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
            request.limit = 25
            songs = try await request.response().songs
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
