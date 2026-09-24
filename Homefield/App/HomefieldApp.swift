import SwiftUI

@main
@MainActor
struct HomefieldApp: App {
    @State private var settings: AppSettings
    @State private var library: SongLibrary
    @State private var director: AudioDirector

    init() {
        let settings = AppSettings()
        let library = SongLibrary()
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _director = State(initialValue: AudioDirector(settings: settings, library: library))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .environment(director)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            GameListView()
                .tabItem { Label("경기", systemImage: "baseball") }
            SongLibraryView()
                .tabItem { Label("응원가", systemImage: "music.note.list") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
    }
}
