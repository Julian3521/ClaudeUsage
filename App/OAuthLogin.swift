import AppKit
import CryptoKit
import Foundation
import Network

/// Browser-based OAuth sign-in (PKCE + loopback redirect), mirroring the Claude
/// Code CLI flow. We open the user's real browser (so it has their claude.ai
/// session and passes any bot challenge) and catch the redirect on a localhost
/// listener — no copy/paste. Requires the `network.server` sandbox entitlement.
enum OAuthLogin {
    enum LoginError: LocalizedError {
        case timedOut, stateMismatch
        var errorDescription: String? {
            switch self {
            case .timedOut: return "Sign-in timed out. Please try again."
            case .stateMismatch: return "Sign-in could not be verified (state mismatch)."
            }
        }
    }

    static func signIn() async throws -> TokenSet {
        let verifier = randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = randomURLSafe(32)

        let server = LoopbackServer()
        let port = try await server.start()
        let redirectURI = "http://localhost:\(port)/callback"

        var comps = URLComponents(string: Config.authorizeURL)!
        comps.queryItems = [
            .init(name: "client_id", value: Config.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: Config.oauthScopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        let authURL = comps.url!
        await MainActor.run { NSWorkspace.shared.open(authURL) }

        guard let cb = await server.waitForCallback() else { throw LoginError.timedOut }
        guard cb.state == state else { throw LoginError.stateMismatch }
        return try await OAuthClient.exchange(code: cb.code, verifier: verifier,
                                              redirectURI: redirectURI, state: state)
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Minimal one-shot localhost HTTP listener that captures the OAuth redirect.
private final class LoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jb.ClaudeUsage.oauth-loopback")
    private var listener: NWListener?
    private var callback: CheckedContinuation<(code: String, state: String)?, Never>?
    private var finished = false
    private var startResumed = false   // guards the start() continuation (queue-serialized)

    /// Start listening on a free 127.0.0.1 port; returns the chosen port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do {
                    let params = NWParameters.tcp
                    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: params)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            if !self.startResumed, let port = listener.port?.rawValue {
                                self.startResumed = true; cont.resume(returning: port)
                            }
                        case let .failed(error):
                            if !self.startResumed { self.startResumed = true; cont.resume(throwing: error) }
                        default:
                            break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
                    listener.start(queue: self.queue)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Await the redirect (code+state), or nil after a 5-minute timeout.
    func waitForCallback() async -> (code: String, state: String)? {
        await withCheckedContinuation { cont in
            queue.async {
                if self.finished { cont.resume(returning: nil); return }
                self.callback = cont
                self.queue.asyncAfter(deadline: .now() + 300) { self.finish(nil) }
            }
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let result = Self.parse(requestLine: request)
            let html = """
            <html><head><meta charset="utf-8"></head>
            <body style="font-family:-apple-system,system-ui;text-align:center;padding:4em;color:#1d1d1f">
            <h2>✓ Signed in</h2><p>You can close this tab and return to Claude Usage.</p></body></html>
            """
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(html.utf8.count)\r
            Connection: close\r
            \r
            \(html)
            """
            conn.send(content: Data(response.utf8),
                      completion: .contentProcessed { _ in conn.cancel() })
            self.finish(result)
        }
    }

    private func finish(_ result: (code: String, state: String)?) {
        guard !finished else { return }
        finished = true
        callback?.resume(returning: result)
        callback = nil
        listener?.cancel()
        listener = nil
    }

    /// Pull code/state out of the first request line: `GET /callback?... HTTP/1.1`.
    private static func parse(requestLine request: String) -> (code: String, state: String)? {
        guard let line = request.split(separator: "\r\n").first,
              let pathPart = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://localhost\(pathPart)"),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { return nil }
        let state = comps.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        return (code, state)
    }
}
