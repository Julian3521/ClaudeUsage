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
