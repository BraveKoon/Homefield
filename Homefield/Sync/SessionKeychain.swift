import Foundation
import Security

/// 로그인 세션(토큰)은 키체인에 둔다. 앱을 지우면 같이 지워진다.
enum SessionKeychain {
    private static let service = "com.bravekoon.homefield.session"
    private static let account = "supabase"

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> SupabaseSession? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    /// nil 이면 지운다
    static func save(_ session: SupabaseSession?) {
        SecItemDelete(base as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
