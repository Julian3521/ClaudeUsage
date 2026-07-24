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
        case timedOut, stateMismatch, cancelled, noRandomness
        case browserFailed(URL)
        case denied(String)
        var errorDescription: String? {
            switch self {
            case .timedOut: return "Sign-in timed out. Please try again."
            case .stateMismatch: return "Sign-in could not be verified (state mismatch)."
            case .cancelled: return "Sign-in cancelled."
            case .noRandomness: return "Could not generate secure random values for sign-in."
            case let .browserFailed(url): return "Could not open the browser for \(url.host ?? "sign-in")."
            case let .denied(reason): return "Claude declined the sign-in: \(reason)"
            }
        }
    }

    static func signIn() async throws -> TokenSet {
        let verifier = try randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = try randomURLSafe(32)

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
        guard await MainActor.run(body: { NSWorkspace.shared.open(authURL) }) else {
            server.cancel()
            throw LoginError.browserFailed(authURL)
        }

        // Cancelling the surrounding task (the user hits Cancel) tears the
        // listener down instead of leaving the port bound for five minutes.
        let callback = await withTaskCancellationHandler {
            await server.waitForCallback()
        } onCancel: {
            server.cancel()
        }

        switch callback {
        case let .success(code, callbackState):
            guard callbackState == state else { throw LoginError.stateMismatch }
            return try await OAuthClient.exchange(code: code, verifier: verifier,
                                                  redirectURI: redirectURI, state: state)
        case let .denied(reason):
            throw LoginError.denied(reason)
        case .cancelled:
            throw LoginError.cancelled
        case .timedOut:
            throw LoginError.timedOut
        }
    }

    /// Cryptographically random, URL-safe string. A failed `SecRandomCopyBytes`
    /// used to be ignored, leaving an all-zero buffer — i.e. a constant PKCE
    /// verifier and a constant `state`.
    private static func randomURLSafe(_ count: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw LoginError.noRandomness
        }
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

/// What the browser redirect turned out to be.
private enum LoopbackOutcome: Sendable {
    case success(code: String, state: String)
    case denied(String)          // the authorize page came back with ?error=…
    case cancelled
    case timedOut
}

/// Minimal localhost HTTP listener that captures the OAuth redirect. It keeps
/// listening until a request actually carries the callback, so a stray hit on
/// the port (browser preconnect, /favicon.ico, a local scanner) can no longer
/// end the sign-in.
private final class LoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jb.ClaudeUsage.oauth-loopback")
    private var listener: NWListener?
    private var callback: CheckedContinuation<LoopbackOutcome, Never>?
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
                            // Tear the listener down here — otherwise a failed
                            // start leaks a bound NWListener per attempt.
                            listener.cancel()
                            self.listener = nil
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

    /// Await the redirect, or `.timedOut` after 5 minutes.
    func waitForCallback() async -> LoopbackOutcome {
        await withCheckedContinuation { cont in
            queue.async {
                if self.finished { cont.resume(returning: .cancelled); return }
                self.callback = cont
                self.queue.asyncAfter(deadline: .now() + 300) { self.finish(.timedOut) }
            }
        }
    }

    /// Stop listening and release the port (task cancellation / browser failure).
    func cancel() {
        queue.async { self.finish(.cancelled) }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            switch Self.parse(requestLine: request) {
            case let .some(outcome):
                self.respond(conn, status: "200 OK", body: Self.page(for: outcome))
                self.finish(outcome)
            case .none:
                // Not the callback — answer and keep waiting for the real one.
                self.respond(conn, status: "404 Not Found", body: "Not found")
            }
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: String) {
        let html = """
        <html><head><meta charset="utf-8"></head>
        <body style="font-family:-apple-system,system-ui;text-align:center;padding:4em;color:#1d1d1f">
        \(body)</body></html>
        """
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        conn.send(content: Data(response.utf8),
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    /// The browser used to read "✓ Signed in" even when the user had declined.
    private static func page(for outcome: LoopbackOutcome) -> String {
        if case let .denied(reason) = outcome {
            return "<h2>Sign-in cancelled</h2><p>\(reason)</p>"
        }
        return "<h2>✓ Signed in</h2><p>You can close this tab and return to Claude Usage.</p>"
    }

    private func finish(_ outcome: LoopbackOutcome) {
        guard !finished else { return }
        finished = true
        callback?.resume(returning: outcome)
        callback = nil
        listener?.cancel()
        listener = nil
    }

    /// Reads the first request line (`GET /callback?... HTTP/1.1`). Returns nil
    /// for anything that isn't the OAuth callback, so the listener stays up.
    private static func parse(requestLine request: String) -> LoopbackOutcome? {
        guard let line = request.split(separator: "\r\n").first,
              let pathPart = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://localhost\(pathPart)")
        else { return nil }
        func item(_ name: String) -> String? {
            comps.queryItems?.first { $0.name == name }?.value
        }
        if let code = item("code") {
            return .success(code: code, state: item("state") ?? "")
        }
        // The authorize page redirects with ?error=access_denied when consent is
        // refused — report that instead of timing out five minutes later.
        if let error = item("error") {
            return .denied(item("error_description") ?? error)
        }
        return nil
    }
}
