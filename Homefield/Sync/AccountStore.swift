import AuthenticationServices
import CryptoKit
import Foundation
import HomefieldCore
import Observation

/// Apple 로그인 계정과 기기 사이 동기화.
/// 로그인은 선택이다. 로그인하지 않으면 지금처럼 기기 안에서만 쓴다.
@MainActor
@Observable
final class AccountStore {
    enum Status: Equatable {
        case idle
        case working
        case synced(Date)
        case failed(String)
    }

    /// 이 기기와 계정 데이터가 달라서 사용자가 고를 때
    struct Choice {
        let remote: SyncSnapshot
        let revision: Int
    }

    private(set) var session: SupabaseSession?
    private(set) var status: Status = .idle
    private(set) var pendingChoice: Choice?
    /// 어느 쪽을 쓸지 묻는 창을 띄울지
    var isChoosing = false
    var confirmingDelete = false

    var isSignedIn: Bool { session != nil }
    var lastSyncedAt: Date? { syncState?.syncedAt }
    var localSummary: String { makeSnapshot().summary }

    @ObservationIgnored private let api = SupabaseAPI()
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let cards: CardStore
    @ObservationIgnored private let attendance: AttendanceStore
    @ObservationIgnored private let library: SongLibrary
    @ObservationIgnored private let stateURL: URL

    /// 이 기기가 계정과 마지막으로 맞춘 모습
    @ObservationIgnored private var syncState: SyncState?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var needsAnotherRound = false
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var currentNonce: String?

    private struct SyncState: Codable {
        var userId: String
        var revision: Int
        var snapshot: SyncSnapshot
        var syncedAt: Date
    }

    init(
        settings: AppSettings,
        cards: CardStore,
        attendance: AttendanceStore,
        library: SongLibrary,
        fileManager: FileManager = .default
    ) {
        self.settings = settings
        self.cards = cards
        self.attendance = attendance
        self.library = library
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        stateURL = support.appendingPathComponent("sync-state.json")
        // 데모 빌드는 로그인·동기화를 하지 않는다 (키체인에 일반 빌드의 로그인이 남아 있어도 쓰지 않는다)
        session = BuildFlavor.isDemo ? nil : SessionKeychain.load()
        syncState = BuildFlavor.isDemo ? nil : (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) }

        settings.onChange = { [weak self] in self?.localDidChange() }
        cards.onChange = { [weak self] in self?.localDidChange() }
        attendance.onChange = { [weak self] in self?.localDidChange() }
        library.onChange = { [weak self] in self?.localDidChange() }
    }

    // MARK: Apple 로그인

    /// 'Apple로 로그인' 버튼을 누르는 순간: 이름·이메일은 받지 않는다 (계정은 Apple 이 주는 사용자 ID 로 구분한다)
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            status = .failed("Apple 로그인을 하지 못했어요. (\(error.localizedDescription))")
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                status = .failed("Apple 로그인 정보를 읽지 못했어요.")
                return
            }
            status = .working
            do {
                let newSession = try await api.signIn(idToken: token, nonce: nonce)
                setSession(newSession)
                await sync()
            } catch {
                status = .failed(Self.message(for: error))
            }
        }
    }

    /// 로그아웃. 이 기기의 카드와 설정은 그대로 남는다.
    func signOut() {
        setSession(nil)
        syncState = nil
        try? FileManager.default.removeItem(at: stateURL)
        pendingChoice = nil
        isChoosing = false
        status = .idle
    }

    /// 서버의 계정과 데이터를 지우고 로그아웃한다. 이 기기의 카드와 설정은 그대로 남는다.
    func deleteAccount() async {
        status = .working
        do {
            let current = try await validSession()
            try await api.deleteAccount(session: current)
            signOut()
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    // MARK: 동기화

    /// 앱을 열 때, 앞으로 올 때, 로그인 직후, '지금 동기화' 를 눌렀을 때
    func sync() async {
        guard !BuildFlavor.isDemo, session != nil, pendingChoice == nil else { return }
        guard !isSyncing else {
            needsAnotherRound = true
            return
        }
        isSyncing = true
        status = .working
        do {
            try await run(allowRetry: true)
            if pendingChoice == nil { status = .synced(Date()) } else { status = .idle }
        } catch {
            status = .failed(Self.message(for: error))
        }
        isSyncing = false
        if needsAnotherRound {
            needsAnotherRound = false
            await sync()
        }
    }

    /// 이 기기 데이터가 바뀌면 잠깐 모아 두었다가 올린다
    func localDidChange() {
        guard !BuildFlavor.isDemo, session != nil, !isApplying else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// 데이터가 서로 다를 때 사용자가 고른 쪽으로 맞춘다
    func resolve(useAccount: Bool) async {
        guard let choice = pendingChoice, let userId = session?.userId else { return }
        pendingChoice = nil
        isChoosing = false
        if useAccount {
            apply(choice.remote)
            record(userId: userId, revision: choice.revision, snapshot: choice.remote)
            status = .synced(Date())
            return
        }
        status = .working
        do {
            let current = try await validSession()
            let local = makeSnapshot()
            if let revision = try await api.updateState(local, expectedRevision: choice.revision, session: current) {
                record(userId: userId, revision: revision, snapshot: local)
                status = .synced(Date())
            } else {
                // 그 사이 다른 기기가 또 저장했다
                await sync()
            }
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    private func run(allowRetry: Bool) async throws {
        let current = try await validSession()
        let remote = try await api.fetchState(SyncSnapshot.self, session: current)
        let local = makeSnapshot()
        let state = syncState.flatMap { $0.userId == current.userId ? $0 : nil }
        let action = SyncPlanner.plan(
            remoteRevision: remote?.revision,
            syncedRevision: state?.revision,
            localChanged: local != state?.snapshot,
            localHasContent: local.hasUserContent
        )

        switch action {
        case .nothing:
            break
        case .uploadFirst:
            do {
                try await api.insertState(local, session: current)
                record(userId: current.userId, revision: 1, snapshot: local)
            } catch SupabaseError.conflict where allowRetry {
                try await run(allowRetry: false)
            }
        case .upload:
            guard let state else { return }
            if let revision = try await api.updateState(local, expectedRevision: state.revision, session: current) {
                record(userId: current.userId, revision: revision, snapshot: local)
            } else if allowRetry {
                try await run(allowRetry: false)
            }
        case .download:
            guard let remote else { return }
            apply(remote.value)
            record(userId: current.userId, revision: remote.revision, snapshot: remote.value)
        case .askUser:
            guard let remote else { return }
            pendingChoice = Choice(remote: remote.value, revision: remote.revision)
            isChoosing = true
        }
    }

    // MARK: 데이터 ↔ 기기

    private func makeSnapshot() -> SyncSnapshot {
        var assignments: [String: SongAssignment] = [:]
        for (key, assignment) in library.assignments {
            let walkUp = SyncSnapshot.syncable(assignment.walkUp)
            let cheer = SyncSnapshot.syncable(assignment.cheer)
            if walkUp != nil || cheer != nil {
                assignments[key] = SongAssignment(walkUp: walkUp, cheer: cheer)
            }
        }
        // 비교가 늘 같은 결과가 나오게 순서를 고정한다
        let checkIns = attendance.checkIns.sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
        return SyncSnapshot(
            cards: cards.collection,
            favoriteTeamCode: settings.favoriteTeamCode,
            autumnMode: settings.autumnMode.rawValue,
            checkIns: checkIns,
            assignments: assignments,
            teamCheers: library.teamCheers.compactMapValues { SyncSnapshot.syncable($0) }
        )
    }

    private func apply(_ snapshot: SyncSnapshot) {
        isApplying = true
        defer { isApplying = false }
        cards.replace(with: snapshot.cards)
        attendance.replace(checkIns: snapshot.checkIns)
        library.applySynced(assignments: snapshot.assignments, teamCheers: snapshot.teamCheers)
        settings.favoriteTeamCode = snapshot.favoriteTeamCode
        if let mode = snapshot.autumnMode.flatMap(AutumnBaseball.Mode.init(rawValue:)) {
            settings.autumnMode = mode
        }
    }

    // MARK: 세션·저장

    private func setSession(_ newSession: SupabaseSession?) {
        session = newSession
        SessionKeychain.save(newSession)
    }

    /// 만료가 다가오면 새로 받는다. 네트워크가 안 되는 것만으로는 로그아웃하지 않는다.
    private func validSession() async throws -> SupabaseSession {
        guard let current = session else { throw SupabaseError.sessionExpired }
        guard current.expiresAt.timeIntervalSinceNow < 60 else { return current }
        do {
            let refreshed = try await api.refresh(refreshToken: current.refreshToken)
            setSession(refreshed)
            return refreshed
        } catch SupabaseError.http(let code, _) where code == 400 || code == 401 {
            signOut()
            throw SupabaseError.sessionExpired
        }
    }

    private func record(userId: String, revision: Int, snapshot: SyncSnapshot) {
        let state = SyncState(userId: userId, revision: revision, snapshot: snapshot, syncedAt: Date())
        syncState = state
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private static func message(for error: Error) -> String {
        if error is URLError { return "인터넷에 연결하지 못했어요. 잠시 후 다시 시도해 주세요." }
        return error.localizedDescription
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).compactMap { _ in characters.randomElement(using: &generator) })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
