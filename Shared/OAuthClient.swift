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

/// Token refresh against the OAuth token endpoint. (Login itself is done by
/// pasting an existing access token; see `UsageViewModel.loginWithToken`.)
enum OAuthClient {
    static func refresh(_ refreshToken: String) async throws -> TokenSet {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Config.clientID,
        ]
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
                        refreshToken: token.refreshToken ?? refreshToken,
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
