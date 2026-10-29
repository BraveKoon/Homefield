import Foundation
import HomefieldCore

/// 계정에 올라가는 내 데이터 한 벌.
/// 카드·포인트·응원 라인업, 응원팀·가을 테마, 직관 기록, 선수별 응원가 지정.
/// 음악 파일은 저작권 때문에 올리지 않는다 (Apple Music 곡 지정만 이어진다).
struct SyncSnapshot: Codable, Equatable {
    var version = 1
    var cards: CardCollection
    var favoriteTeamCode: String?
    var autumnMode: String?
    var checkIns: [CheckIn]
    var assignments: [String: SongAssignment]
    var teamCheers: [String: SongSource]

    /// 사용자가 쌓은 것이 있는지 (첫 선물과 매일 접속 포인트만 있는 새 기기는 아니다)
    var hasUserContent: Bool {
        !cards.counts.isEmpty || !checkIns.isEmpty || !assignments.isEmpty || !teamCheers.isEmpty
    }

    /// 어느 쪽 데이터를 쓸지 고를 때 보여 주는 한 줄
    var summary: String {
        "카드 \(cards.owned.count)장 · \(cards.wallet.points)P · 직관 \(checkIns.count)회"
    }

    /// 기기에 있는 음악 파일 지정은 다른 기기에서 쓸 수 없어서 올리지 않는다
    static func syncable(_ source: SongSource?) -> SongSource? {
        if case .appleMusic? = source { return source }
        return nil
    }
}
