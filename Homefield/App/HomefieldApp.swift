import SwiftUI

@main
@MainActor
struct HomefieldApp: App {
    @State private var settings: AppSettings
    @State private var library: SongLibrary
    @State private var director: AudioDirector
    @State private var attendance: AttendanceStore
    @State private var cards: CardStore

    init() {
        let settings = AppSettings()
        let library = SongLibrary()
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _director = State(initialValue: AudioDirector(settings: settings, library: library))
        _attendance = State(initialValue: AttendanceStore())
        _cards = State(initialValue: CardStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .environment(director)
                .environment(attendance)
                .environment(cards)
        }
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let theme = TeamTheme.forTeam(settings.favoriteTeamCode)
        // 첫 실행 화면은 시트로 띄우지 않고 화면 자체를 바꾼다.
        // Mac(Catalyst)에서는 시트를 띄우는 시점에 환경 값이 아직 없어 바로 죽는다.
        Group {
            if settings.hasCompletedOnboarding {
                tabs
            } else {
                OnboardingView()
            }
        }
        .tint(theme.primary)
        .environment(\.teamTheme, theme)
        .environment(\.isAutumn, settings.isAutumn)
        .animation(.appear, value: settings.favoriteTeamCode)
        .animation(.appear, value: settings.hasCompletedOnboarding)
    }

    private var tabs: some View {
        TabView {
            GameListView()
                .tabItem { Label("경기", systemImage: "baseball") }
            CardsView()
                .tabItem { Label("카드", systemImage: "rectangle.on.rectangle.angled") }
            AttendanceView()
                .tabItem { Label("직관", systemImage: "sportscourt") }
            SongLibraryView()
                .tabItem { Label("응원가", systemImage: "music.note.list") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
    }
}
