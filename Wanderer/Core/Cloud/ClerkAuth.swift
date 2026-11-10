import Foundation
import Security

/// A Clerk session as this app needs it: the client token authenticates
/// Frontend API calls, the session id selects the session, and the JWT is what
/// the Worker verifies.
struct ClerkSession: Codable, Equatable {
    let clientToken: String
    let sessionID: String
    let userID: String
    let email: String?
    let jwt: String
    let expiresAt: Date?
}

enum ClerkAuthError: LocalizedError, Equatable {
    case notConfigured
    case invalidResponse
    case rejected(String)
    case verificationRequired(String)
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sign-in is not configured for this build."
        case .invalidResponse:
            return "Clerk returned a response Wanderer could not read."
        case .rejected(let message):
            return message
        case .verificationRequired(let message):
            return message
        case .storageFailed:
            return "Wanderer could not save the session on this device."
        }
    }
}

/// Talks to the Clerk Frontend API directly (the same public API the Clerk web
/// SDK uses) so the app needs no third-party SDK and no secret key.
///
/// Live verification against a real Clerk instance is still required; see
/// `docs/migration-plan.md`. Until then cloud mode stays opt-in.
actor ClerkAuthClient {
    private let frontendAPI: URL
    private let session: URLSessioning
    private let jsVersion = "5"

    init(frontendAPI: URL, session: URLSessioning = URLSession.shared) {
        self.frontendAPI = frontendAPI
        self.session = session
    }

    func signIn(email: String, password: String) async throws -> ClerkSession {
        let payload = try await post(
            "/v1/client/sign_ins",
            fields: ["identifier": email, "password": password]
        )
        guard let client = payload["client"] as? [String: Any],
              let clientToken = client["client_token"] as? String ?? client["last_active_client_token"] as? String,
              let sessionID = (payload["response"] as? [String: Any])?["created_session_id"] as? String
                ?? client["last_active_session_id"] as? String else {
            throw ClerkAuthError.invalidResponse
        }
        return try await mintToken(clientToken: clientToken, sessionID: sessionID, client: client)
    }

    func signUp(email: String, password: String) async throws -> ClerkSession {
        let payload = try await post(
            "/v1/client/sign_ups",
            fields: ["email_address": email, "password": password]
        )
        let response = payload["response"] as? [String: Any]
        let status = response?["status"] as? String ?? ""
        guard status == "complete" || status == "active" else {
            throw ClerkAuthError.verificationRequired(
                "Check your email to confirm the account, then sign in here."
            )
        }
        guard let client = payload["client"] as? [String: Any],
              let clientToken = client["client_token"] as? String,
              let sessionID = (response?["created_session_id"] as? String)
                ?? (client["last_active_session_id"] as? String) else {
            throw ClerkAuthError.invalidResponse
        }
        return try await mintToken(clientToken: clientToken, sessionID: sessionID, client: client)
    }

    func refresh(_ session: ClerkSession) async throws -> ClerkSession {
        guard let client = try? await get("/v1/client", bearer: session.clientToken)["client"] as? [String: Any] else {
            throw ClerkAuthError.invalidResponse
        }
        return try await mintToken(clientToken: session.clientToken, sessionID: session.sessionID, client: client)
    }

    private func mintToken(
        clientToken: String,
        sessionID: String,
        client: [String: Any]
    ) async throws -> ClerkSession {
        let payload = try await post(
            "/v1/client/sessions/\(sessionID)/tokens",
            fields: [:],
            bearer: clientToken
        )
        guard let jwt = payload["jwt"] as? String else { throw ClerkAuthError.invalidResponse }

        let user = client["sessions"] as? [[String: Any]]
        let sessionRow = user?.first(where: { ($0["id"] as? String) == sessionID })
        let userID = sessionRow?["user_id"] as? String ?? (client["user"] as? [String: Any])?["id"] as? String ?? ""
        let email = ((client["user"] as? [String: Any])?["email_addresses"] as? [[String: Any]])?
            .first?["email_address"] as? String
        let expiresAt = Self.jwtExpiry(jwt)
        return ClerkSession(
            clientToken: clientToken,
            sessionID: sessionID,
            userID: userID,
            email: email,
            jwt: jwt,
            expiresAt: expiresAt
        )
    }

    // MARK: - Transport

    private func get(_ path: String, bearer: String?) async throws -> [String: Any] {
        try await request(path, method: "GET", fields: [:], bearer: bearer)
    }

    private func post(
        _ path: String,
        fields: [String: String],
        bearer: String? = nil
    ) async throws -> [String: Any] {
        try await request(path, method: "POST", fields: fields, bearer: bearer)
    }

    private func request(
        _ path: String,
        method: String,
        fields: [String: String],
        bearer: String?
    ) async throws -> [String: Any] {
        guard var components = URLComponents(
            url: frontendAPI.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw ClerkAuthError.notConfigured }
        components.queryItems = [URLQueryItem(name: "_clerk_js_version", value: jsVersion)]
        guard let url = components.url else { throw ClerkAuthError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "authorization")
        }
        if method == "POST" {
            var form = URLComponents()
            form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = Self.errorMessage(in: object) ?? "Sign-in failed. Try again."
            throw ClerkAuthError.rejected(message)
        }
        return object
    }

    static func errorMessage(in object: [String: Any]) -> String? {
        guard let errors = object["errors"] as? [[String: Any]], let first = errors.first else {
            return nil
        }
        let text = first["long_message"] as? String
            ?? first["message"] as? String
        guard let text else { return nil }
        let code = first["code"] as? String ?? ""
        if code.contains("password") {
            return "That password doesn't match. Try again."
        }
        if code.contains("identifier") || code.contains("not_found") {
            return "No account uses that email yet."
        }
        if code.contains("session_exists") {
            return "You're already signed in on this device."
        }
        return text
    }

    static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let exp = object["exp"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }
}

/// Keychain-backed storage for the Clerk session.
struct ClerkSessionStore {
    private let service = "com.wanderer.ios.clerk"
    private let account = "session"

    func load() -> ClerkSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(ClerkSession.self, from: data)
    }

    func save(_ session: ClerkSession) throws {
        let data = try JSONEncoder().encode(session)
        SecItemDelete(baseQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw ClerkAuthError.storageFailed
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
