import Foundation

struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
}

enum SupabaseError: LocalizedError {
    case http(Int, String)
    /// 다른 기기가 먼저 저장했다
    case conflict
    case sessionExpired
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(let status, let message): "서버 오류 (\(status)): \(message)"
        case .conflict: "다른 기기가 먼저 저장했어요."
        case .sessionExpired: "로그인이 만료됐어요. 다시 로그인해 주세요."
        case .invalidResponse: "서버 응답을 읽지 못했어요."
        }
    }
}

/// Supabase 의 인증·표 저장을 HTTP 로 직접 부른다 (SDK 없이 필요한 것만).
struct SupabaseAPI {
    var baseURL = SupabaseConfig.url
    var anonKey = SupabaseConfig.anonKey
    var urlSession = URLSession.shared

    // MARK: 로그인

    /// Apple 이 준 identity token 을 앱 전용 세션으로 바꾼다
    func signIn(idToken: String, nonce: String) async throws -> SupabaseSession {
        let body = try JSONEncoder().encode(["provider": "apple", "id_token": idToken, "nonce": nonce])
        let result = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")], body: body)
        return try Self.session(from: result.data)
    }

    func refresh(refreshToken: String) async throws -> SupabaseSession {
        let body = try JSONEncoder().encode(["refresh_token": refreshToken])
        let result = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body)
        return try Self.session(from: result.data)
    }

    /// 서버의 계정과 저장된 데이터를 지운다
    func deleteAccount(session: SupabaseSession) async throws {
        try await send("POST", "rest/v1/rpc/delete_my_account", body: Data("{}".utf8), session: session)
    }

    // MARK: 저장된 데이터

    /// 서버에 저장된 내 데이터. 없으면 nil
    func fetchState<T: Decodable>(_ type: T.Type, session: SupabaseSession) async throws -> (revision: Int, value: T)? {
        let query = [
            URLQueryItem(name: "select", value: "revision,data"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
        ]
        let result = try await send("GET", "rest/v1/user_state", query: query, session: session)
        let rows = try JSONDecoder().decode([StateRow<T>].self, from: result.data)
        return rows.first.map { ($0.revision, $0.data) }
    }

    /// 처음 올린다 (번호 1). 이미 줄이 있으면 conflict
    func insertState<T: Encodable>(_ value: T, session: SupabaseSession) async throws {
        let body = try JSONEncoder().encode(InsertBody(user_id: session.userId, revision: 1, data: value))
        try await send("POST", "rest/v1/user_state", body: body, session: session, prefer: "return=minimal")
    }

    /// 서버 번호가 expectedRevision 일 때만 덮어쓴다. 다른 기기가 먼저 저장했으면 nil, 성공하면 새 번호
    func updateState<T: Encodable>(_ value: T, expectedRevision: Int, session: SupabaseSession) async throws -> Int? {
        let query = [
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
            URLQueryItem(name: "revision", value: "eq.\(expectedRevision)"),
            URLQueryItem(name: "select", value: "revision"),
        ]
        let body = try JSONEncoder().encode(UpdateBody(revision: expectedRevision + 1, data: value))
        let result = try await send("PATCH", "rest/v1/user_state", query: query, body: body, session: session, prefer: "return=representation")
        let rows = try JSONDecoder().decode([RevisionRow].self, from: result.data)
        return rows.isEmpty ? nil : expectedRevision + 1
    }

    // MARK: HTTP

    @discardableResult
    private func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        session: SupabaseSession? = nil,
        prefer: String? = nil
    ) async throws -> (data: Data, status: Int) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SupabaseError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SupabaseError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session?.accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data) }
        return (data, http.statusCode)
    }

    private static func error(status: Int, data: Data) -> SupabaseError {
        if status == 409 { return .conflict }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = ["message", "msg", "error_description", "error"]
            .compactMap { object?[$0] as? String }
            .first ?? String(data: data, encoding: .utf8) ?? ""
        return .http(status, message)
    }

    private static func session(from data: Data) throws -> SupabaseSession {
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SupabaseSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn),
            userId: token.user.id
        )
    }
}

private struct TokenResponse: Decodable {
    struct User: Decodable { let id: String }
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct StateRow<T: Decodable>: Decodable {
    let revision: Int
    let data: T
}

private struct RevisionRow: Decodable {
    let revision: Int
}

private struct InsertBody<T: Encodable>: Encodable {
    let user_id: String
    let revision: Int
    let data: T
}

private struct UpdateBody<T: Encodable>: Encodable {
    let revision: Int
    let data: T
}
