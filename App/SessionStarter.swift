import Foundation

/// Sends a tiny inference request to "anchor" a new 5-hour usage window, so the
/// rolling window starts (and later resets) at a time of your choosing rather
/// than whenever you first happen to use Claude. Uses minimal quota (1 token).
enum SessionStarter {
    @discardableResult
    static func ping() async throws -> Bool {
        guard let tokens = TokenStore.load() else { throw UsageError.notLoggedIn }

        var req = URLRequest(url: URL(string: Config.messagesURL)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Config.oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20

        let body: [String: Any] = [
            "model": Config.pingModel,
            "max_tokens": 1,
            "system": Config.claudeCodeSystemPrompt,
            "messages": [["role": "user", "content": "hi"]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UsageError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return true
    }
}
