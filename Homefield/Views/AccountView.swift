import AuthenticationServices
import SwiftUI

/// 설정의 '계정' 구역: Apple 로그인과 기기 동기화
struct AccountSection: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            if account.isSignedIn {
                signedIn
            } else {
                SignInWithAppleButton(.signIn) { request in
                    account.prepare(request)
                } onCompletion: { result in
                    Task { await account.complete(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
                // 둘레 카드와 토글, 탭 막대처럼 둥글게 (기본 모서리는 각져 보인다)
                .clipShape(Capsule())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if case .failed(let message) = account.status {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("계정")
        } footer: {
            Text("로그인하면 카드·포인트·응원 라인업·응원팀·직관 기록·응원가 지정이 같은 Apple 계정의 다른 기기와 이어져요. 음악 파일은 저작권 때문에 올라가지 않고, Apple Music 곡 지정만 이어집니다. 로그인하지 않아도 모든 기능을 쓸 수 있어요.")
        }
    }

    @ViewBuilder
    private var signedIn: some View {
        SettingsLabel("Apple 계정으로 로그인됨", systemImage: "person.crop.circle.fill", color: .blue)
        HStack {
            Text("동기화")
            Spacer()
            statusText
        }
        if account.pendingChoice != nil {
            Button("어느 쪽 데이터를 쓸지 정하기") { account.isChoosing = true }
        }
        Button("지금 동기화") { Task { await account.sync() } }
            .disabled(account.status == .working || account.pendingChoice != nil)
        Button("로그아웃") { account.signOut() }
        Button("계정 삭제", role: .destructive) { account.confirmingDelete = true }
    }

    @ViewBuilder
    private var statusText: some View {
        switch account.status {
        case .working:
            ProgressView().controlSize(.small)
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.trailing)
        case .synced(let date):
            Text(date.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
        case .idle:
            if account.pendingChoice != nil {
                Text("선택 필요").foregroundStyle(.orange)
            } else if let date = account.lastSyncedAt {
                Text(date.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
            } else {
                Text("대기 중").foregroundStyle(.secondary)
            }
        }
    }
}

/// 어느 쪽 데이터를 쓸지 묻는 창과 계정 삭제 확인
struct AccountDialogs: ViewModifier {
    @Environment(AccountStore.self) private var account

    func body(content: Content) -> some View {
        @Bindable var account = account
        content
            .confirmationDialog(
                "이 기기와 계정의 데이터가 달라요",
                isPresented: $account.isChoosing,
                titleVisibility: .visible,
                presenting: account.pendingChoice
            ) { choice in
                Button("계정 데이터 쓰기 (\(choice.remote.summary))") {
                    Task { await account.resolve(useAccount: true) }
                }
                Button("이 기기 데이터 쓰기 (\(account.localSummary))", role: .destructive) {
                    Task { await account.resolve(useAccount: false) }
                }
                Button("나중에 정하기", role: .cancel) {}
            } message: { _ in
                Text("고르지 않은 쪽의 카드와 포인트는 사라져요.")
            }
            .alert("계정을 삭제할까요?", isPresented: $account.confirmingDelete) {
                Button("삭제", role: .destructive) { Task { await account.deleteAccount() } }
                Button("취소", role: .cancel) {}
            } message: {
                Text("서버에 저장된 데이터와 계정이 지워지고 로그아웃돼요. 이 기기의 카드와 설정은 그대로 남아요.")
            }
    }
}
