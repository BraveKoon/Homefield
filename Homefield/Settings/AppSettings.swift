import Foundation
import HomefieldCore
import Observation

@MainActor
@Observable
final class AppSettings {
    enum SongScope: String, CaseIterable, Identifiable {
        case allTeams
        case favoriteTeam

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .allTeams: "양 팀 모두"
            case .favoriteTeam: "응원팀만"
            }
        }
    }

    /// TV 중계보다 데이터가 빠를 때 늦춰서 재생 (초)
    var broadcastDelay: Double { didSet { save() } }
    /// 등장곡을 재생할 시간 (초). 이후 응원가로 넘어간다.
    var walkUpDuration: Double { didSet { save() } }
    var pollInterval: Double { didSet { save() } }
    var announceBatter: Bool { didSet { save() } }
    var speechRate: Float { didSet { save() } }
    var enabledPlays: Set<PlayKind> { didSet { save() } }
    var customPhrases: [PlayKind: String] { didSet { save() } }
    var favoriteTeamCode: String? { didSet { save() } }
    var songScope: SongScope { didSet { save() } }
    var useDemo: Bool { didSet { save() } }
    /// 경기를 보는 동안 잠금화면·다이내믹 아일랜드에 실시간 중계
    var liveActivityEnabled: Bool { didSet { save() } }
    /// 첫 실행 응원팀 선택을 마쳤는지
    var hasCompletedOnboarding: Bool { didSet { save() } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        broadcastDelay = defaults.object(forKey: Keys.broadcastDelay) as? Double ?? 0
        walkUpDuration = defaults.object(forKey: Keys.walkUpDuration) as? Double ?? 15
        pollInterval = defaults.object(forKey: Keys.pollInterval) as? Double ?? 3
        announceBatter = defaults.object(forKey: Keys.announceBatter) as? Bool ?? true
        speechRate = defaults.object(forKey: Keys.speechRate) as? Float ?? 0.5
        let storedPlays = (defaults.stringArray(forKey: Keys.enabledPlays) ?? []).compactMap(PlayKind.init(rawValue:))
        enabledPlays = defaults.object(forKey: Keys.enabledPlays) == nil ? Set(PlayKind.allCases) : Set(storedPlays)
        let storedPhrases = defaults.dictionary(forKey: Keys.customPhrases) as? [String: String] ?? [:]
        customPhrases = Dictionary(uniqueKeysWithValues: storedPhrases.compactMap { key, value in
            PlayKind(rawValue: key).map { ($0, value) }
        })
        liveActivityEnabled = defaults.object(forKey: Keys.liveActivityEnabled) as? Bool ?? true
        let favorite = defaults.string(forKey: Keys.favoriteTeamCode)
        favoriteTeamCode = favorite
        songScope = defaults.string(forKey: Keys.songScope).flatMap(SongScope.init(rawValue:)) ?? .allTeams
        useDemo = defaults.object(forKey: Keys.useDemo) as? Bool ?? false
        // 예전 버전에서 이미 응원팀을 골랐다면 다시 묻지 않는다
        hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? (favorite != nil)
    }

    var composer: NarrationComposer {
        NarrationComposer(enabled: enabledPlays, phrases: customPhrases)
    }

    func makeProvider() -> any GameDataProvider {
        useDemo ? DemoGameProvider() : NaverSportsProvider()
    }

    func shouldPlaySongs(for player: Player) -> Bool {
        switch songScope {
        case .allTeams: true
        case .favoriteTeam: favoriteTeamCode == nil || favoriteTeamCode == player.teamCode
        }
    }

    private func save() {
        defaults.set(broadcastDelay, forKey: Keys.broadcastDelay)
        defaults.set(walkUpDuration, forKey: Keys.walkUpDuration)
        defaults.set(pollInterval, forKey: Keys.pollInterval)
        defaults.set(announceBatter, forKey: Keys.announceBatter)
        defaults.set(speechRate, forKey: Keys.speechRate)
        defaults.set(enabledPlays.map(\.rawValue), forKey: Keys.enabledPlays)
        defaults.set(Dictionary(uniqueKeysWithValues: customPhrases.map { ($0.key.rawValue, $0.value) }), forKey: Keys.customPhrases)
        defaults.set(favoriteTeamCode, forKey: Keys.favoriteTeamCode)
        defaults.set(songScope.rawValue, forKey: Keys.songScope)
        defaults.set(useDemo, forKey: Keys.useDemo)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        defaults.set(liveActivityEnabled, forKey: Keys.liveActivityEnabled)
    }

    private enum Keys {
        static let broadcastDelay = "broadcastDelay"
        static let walkUpDuration = "walkUpDuration"
        static let pollInterval = "pollInterval"
        static let announceBatter = "announceBatter"
        static let speechRate = "speechRate"
        static let enabledPlays = "enabledPlays"
        static let customPhrases = "customPhrases"
        static let favoriteTeamCode = "favoriteTeamCode"
        static let songScope = "songScope"
        static let useDemo = "useDemo"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let liveActivityEnabled = "liveActivityEnabled"
    }
}
