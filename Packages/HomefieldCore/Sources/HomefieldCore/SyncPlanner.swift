import Foundation

/// 계정 동기화에서 이번에 할 일
public enum SyncAction: Equatable, Sendable {
    /// 할 일 없음 (서버와 같고 이 기기도 안 바뀜)
    case nothing
    /// 서버에 아직 아무것도 없다: 이 기기 데이터를 처음 올린다
    case uploadFirst
    /// 서버 데이터를 받아서 이 기기에 덮어쓴다
    case download
    /// 이 기기가 바뀌었고 서버는 그대로다: 올린다
    case upload
    /// 이 기기와 서버가 서로 다르다: 어느 쪽을 쓸지 사용자가 정한다
    case askUser
}

/// 서버(계정)와 이 기기 데이터를 어떻게 맞출지 정한다. 서버에는 저장할 때마다 1씩 오르는 번호(revision)가 있다.
public enum SyncPlanner {
    /// - Parameters:
    ///   - remoteRevision: 서버에 있는 번호. 서버에 줄이 없으면 nil
    ///   - syncedRevision: 이 기기가 이 계정에서 마지막으로 맞춘 번호. 이 계정과 처음이면 nil
    ///   - localChanged: 마지막으로 맞춘 뒤 이 기기 데이터가 바뀌었는지
    ///   - localHasContent: 이 기기에 사용자가 쌓은 것(카드, 직관 기록, 응원가 지정)이 있는지.
    ///     첫 선물과 매일 접속 포인트만 있는 새 기기는 없는 것으로 본다.
    public static func plan(
        remoteRevision: Int?,
        syncedRevision: Int?,
        localChanged: Bool,
        localHasContent: Bool
    ) -> SyncAction {
        guard let remoteRevision else { return .uploadFirst }
        guard let syncedRevision else {
            // 이 계정을 이 기기에서 처음 연결한다
            return localHasContent ? .askUser : .download
        }
        if syncedRevision == remoteRevision {
            return localChanged ? .upload : .nothing
        }
        // 다른 기기가 먼저 저장했다
        return localChanged ? .askUser : .download
    }
}
