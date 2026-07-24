import Foundation

enum OAuthError: LocalizedError {
    case badResponse(status: Int, body: String)
    case noAccessToken

    var errorDescription: String? {
        switch self {
        case let .badResponse(status, body):
            return "OAuth server returned \(status): \(body)"
        case .noAccessToken:
            return "Response did not contain an access token."
        }
    }
}

/// Serializes token refreshes across the whole app.
///
/// Anthropic rotates refresh tokens, so two callers refreshing the same token in
/// parallel — the poll timer and the auto-open task can easily collide — get one
/// success and one `invalid_grant`, which typically invalidates the whole token
/// family and signs the user out for good. Everyone shares one in-flight refresh
/// instead, and the two `TokenStore.save` calls can no longer race.
actor TokenRefresher {
    static let shared = TokenRefresher()

    private var inFlight: Task<TokenSet, Error>?

    /// Refreshes the tokens the caller saw as stale, or returns the newer set if
    /// somebody else already refreshed past them.
    func refresh(from stale: TokenSet) async throws -> TokenSet {
        if let current = TokenStore.load(),
           current.accessToken != stale.accessToken, !current.isExpired {
            return current      // another caller got there first
        }
        if let inFlight { return try await inFlight.value }

        guard let refreshToken = stale.refreshToken else { throw UsageError.notLoggedIn }
        let task = Task { try await OAuthClient.refresh(refreshToken) }
        inFlight = task
        defer { inFlight = nil }
        let refreshed = try await task.value
        TokenStore.save(refreshed)
        return refreshed
    }
}

extension TokenRefresher {
    /// Runs `body` with a valid access token: refreshes up front when the token
    /// has expired, and once more on a 401 before retrying. Every authenticated
    /// request goes through here so no call site can forget the refresh.
    static func authorized<T>(_ body: (String) async throws -> T) async throws -> T {
        guard let tokens = TokenStore.load() else { throw UsageError.notLoggedIn }
        let token = tokens.isExpired
            ? try await shared.refresh(from: tokens).accessToken
            : tokens.accessToken
        do {
            return try await body(token)
        } catch UsageError.http(401, _) {
            guard let current = TokenStore.load() else { throw UsageError.notLoggedIn }
            let refreshed = try await shared.refresh(from: current)
            return try await body(refreshed.accessToken)
        }
    }
}

/// OAuth against the token endpoint: code exchange (sign-in) and token refresh.
enum OAuthClient {
    /// Exchange an authorization code (+ PKCE verifier) for tokens.
    static func exchange(code: String, verifier: String,
                         redirectURI: String, state: String) async throws -> TokenSet {
        let token = try await post([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": Config.clientID,
            "code_verifier": verifier,
            "state": state,
        ])
        guard let access = token.accessToken else { throw OAuthError.noAccessToken }
        return TokenSet(accessToken: access,
                        refreshToken: token.refreshToken,
                        expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) })
    }

    static func refresh(_ refreshToken: String) async throws -> TokenSet {
        let token = try await post([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Config.clientID,
        ])
        guard let access = token.accessToken else { throw OAuthError.noAccessToken }
        let expiresAt = token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return TokenSet(accessToken: access,
                        refreshToken: token.refreshToken ?? refreshToken,
                        expiresAt: expiresAt)
    }

    private static func post(_ body: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: Config.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw OAuthError.badResponse(status: status,
                                         body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}
