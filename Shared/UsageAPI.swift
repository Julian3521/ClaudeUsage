import Foundation

enum UsageError: LocalizedError {
    case notLoggedIn
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Not logged in."
        case let .http(status, body):
            return "Usage request failed (\(status)): \(body)"
        }
    }
}

enum UsageAPI {
    struct Result {
        let response: UsageResponse
        let rawJSON: String
    }

    /// Fetches usage, transparently refreshing the access token if needed.
    /// Persists any refreshed tokens and the resulting snapshot.
    @discardableResult
    static func fetch() async throws -> Result {
        guard var tokens = TokenStore.load() else { throw UsageError.notLoggedIn }

        // Proactively refresh if expired.
        if tokens.isExpired, let rt = tokens.refreshToken {
            tokens = try await OAuthClient.refresh(rt)
            TokenStore.save(tokens)
        }

        do {
            return try await request(with: tokens.accessToken)
        } catch UsageError.http(401, _) {
            // Reactive refresh + one retry.
            guard let rt = tokens.refreshToken else { throw UsageError.notLoggedIn }
            let refreshed = try await OAuthClient.refresh(rt)
            TokenStore.save(refreshed)
            return try await request(with: refreshed.accessToken)
        }
    }

    private static func request(with accessToken: String) async throws -> Result {
        var req = URLRequest(url: URL(string: Config.usageURL)!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Config.oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(status) else {
            throw UsageError.http(status: status, body: raw)
        }

        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        let snapshot = UsageSnapshot.from(decoded, fetchedAt: Date())
        SnapshotStore.save(snapshot)
        return Result(response: decoded, rawJSON: prettyPrinted(data) ?? raw)
    }

    private static func prettyPrinted(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                       options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}
