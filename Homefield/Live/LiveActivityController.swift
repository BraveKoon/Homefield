import ActivityKit
import Foundation
import HomefieldCore
import WidgetKit

/// 잠금화면·다이내믹 아일랜드 실시간 중계(Live Activity)를 켜고 갱신한다
@MainActor
final class LiveActivityController {
    private var activity: Activity<GameActivityAttributes>?
    private var lastState: GameActivityAttributes.ContentState?

    var isRunning: Bool { activity != nil }

    func start(game: GameSummary, favoriteCode: String?, state: GameActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // 다른 경기의 남은 실시간 중계는 정리
        for other in Activity<GameActivityAttributes>.activities where other.attributes.gameId != game.id {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        if let existing = Activity<GameActivityAttributes>.activities.first(where: { $0.attributes.gameId == game.id }) {
            activity = existing
            update(state)
            return
        }
        let attributes = GameActivityAttributes(
            gameId: game.id,
            awayCode: game.away.code,
            awayName: game.away.name,
            homeCode: game.home.code,
            homeName: game.home.name,
            stadium: game.stadium,
            favoriteCode: [game.home.code, game.away.code].contains(favoriteCode ?? "") ? favoriteCode : nil
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: Self.staleDate()),
            pushType: nil
        )
        lastState = state
    }

    func update(_ state: GameActivityAttributes.ContentState) {
        guard let activity, state != lastState else { return }
        // 점수나 경기 상태가 바뀌면 홈 화면 위젯도 다시 그린다
        if let lastState, (lastState.awayScore, lastState.homeScore, lastState.isLive) != (state.awayScore, state.homeScore, state.isLive) {
            WidgetCenter.shared.reloadTimelines(ofKind: TeamGameWidgetKind.kind)
        }
        lastState = state
        Task { await activity.update(ActivityContent(state: state, staleDate: Self.staleDate())) }
    }

    /// 경기가 끝났으면 최종 점수를 5분 동안 보여 주고 내리고, 중간에 나가면 바로 지운다
    func end(_ state: GameActivityAttributes.ContentState?, finished: Bool) {
        guard let activity else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: TeamGameWidgetKind.kind)
        self.activity = nil
        lastState = nil
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = finished ? .after(Date().addingTimeInterval(5 * 60)) : .immediate
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// 15분 넘게 갱신이 없으면 시스템이 오래된 정보로 표시한다
    private static func staleDate() -> Date {
        Date().addingTimeInterval(15 * 60)
    }
}
