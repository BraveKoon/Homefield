import SwiftUI

@main
@MainActor
struct HomefieldApp: App {
    @State private var settings: AppSettings
    @State private var library: SongLibrary
    @State private var director: AudioDirector
    @State private var attendance: AttendanceStore

    init() {
        let settings = AppSettings()
        let library = SongLibrary()
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _director = State(initialValue: AudioDirector(settings: settings, library: library))
        _attendance = State(initialValue: AttendanceStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .environment(director)
                .environment(attendance)
        }
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let theme = TeamTheme.forTeam(settings.favoriteTeamCode)
        TabView {
            GameListView()
                .tabItem { Label("경기", systemImage: "baseball") }
            AttendanceView()
                .tabItem { Label("직관", systemImage: "sportscourt") }
            SongLibraryView()
                .tabItem { Label("응원가", systemImage: "music.note.list") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .tint(theme.primary)
        .environment(\.teamTheme, theme)
        .animation(.default, value: settings.favoriteTeamCode)
    }
}
