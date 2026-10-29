import XCTest
@testable import HomefieldCore

final class SyncPlannerTests: XCTestCase {
    private func plan(
        remote: Int?,
        synced: Int?,
        changed: Bool = false,
        content: Bool = false
    ) -> SyncAction {
        SyncPlanner.plan(remoteRevision: remote, syncedRevision: synced, localChanged: changed, localHasContent: content)
    }

    /// 서버가 비어 있으면 이 기기 데이터를 올린다
    func testEmptyServerUploadsFirst() {
        XCTAssertEqual(plan(remote: nil, synced: nil), .uploadFirst)
        XCTAssertEqual(plan(remote: nil, synced: nil, content: true), .uploadFirst)
    }

    /// 새 기기에서 기존 계정으로 로그인하면 서버 데이터를 받는다 (첫 선물을 또 받지 않는다)
    func testFreshDeviceDownloads() {
        XCTAssertEqual(plan(remote: 5, synced: nil, changed: true, content: false), .download)
    }

    /// 이미 쓰던 기기에 서버 데이터도 있으면 묻는다
    func testBothSidesHaveDataAsksUser() {
        XCTAssertEqual(plan(remote: 5, synced: nil, content: true), .askUser)
    }

    func testUpToDateDoesNothing() {
        XCTAssertEqual(plan(remote: 5, synced: 5), .nothing)
    }

    func testLocalChangeUploads() {
        XCTAssertEqual(plan(remote: 5, synced: 5, changed: true, content: true), .upload)
    }

    /// 다른 기기가 먼저 저장했고 이 기기는 안 바뀌었으면 받는다
    func testServerNewerDownloads() {
        XCTAssertEqual(plan(remote: 7, synced: 5), .download)
    }

    /// 양쪽이 다 바뀌었으면 어느 한쪽이 조용히 사라지지 않게 묻는다
    func testBothChangedAsksUser() {
        XCTAssertEqual(plan(remote: 7, synced: 5, changed: true, content: true), .askUser)
    }
}
