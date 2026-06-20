import Foundation
import CryptoKit

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

/// PKCE material for one login attempt.
struct PKCE {
    let verifier: String
    let challenge: String
    let state: String

    static func generate() -> PKCE {
        let verifier = randomURLSafe(byteCount: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = randomURLSafe(byteCount: 16)
        return PKCE(verifier: verifier, challenge: challenge, state: state)
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

enum OAuthClient {
    /// The URL to load in the login web view.
    static func authorizeURL(pkce: PKCE) -> URL {
        var comp = URLComponents(string: Config.authorizeURL)!
        comp.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "scope", value: Config.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return comp.url!
    }

    /// Exchange an authorization code for tokens.
    static func exchangeCode(_ rawCode: String, pkce: PKCE) async throws -> TokenSet {
        // Manual ("code=true") mode can return "code#state"; split if needed.
        let parts = rawCode.split(separator: "#", maxSplits: 1)
        let code = String(parts.first ?? "")
        let state = parts.count > 1 ? String(parts[1]) : pkce.state

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": Config.clientID,
            "redirect_uri": Config.redirectURI,
            "code_verifier": pkce.verifier,
        ]
        return try await postToken(body)
    }

    /// Use a refresh token to obtain a fresh access token.
    static func refresh(_ refreshToken: String) async throws -> TokenSet {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Config.clientID,
        ]
        var tokens = try await postToken(body)
        // Some servers omit the refresh token on refresh — keep the old one.
        if tokens.refreshToken == nil { tokens.refreshToken = refreshToken }
        return tokens
    }

    // MARK: - Private

    private static func postToken(_ body: [String: String]) async throws -> TokenSet {
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

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let access = token.accessToken else { throw OAuthError.noAccessToken }
        let expiresAt = token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return TokenSet(accessToken: access,
                        refreshToken: token.refreshToken,
                        expiresAt: expiresAt)
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

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
