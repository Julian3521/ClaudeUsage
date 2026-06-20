import Foundation
import WidgetKit

@MainActor
final class UsageViewModel: ObservableObject {
    static let shared = UsageViewModel()

    enum ViewState: Equatable {
        case loggedOut
        case loading
        case loaded(UsageSnapshot)
        case error(String)
    }

    @Published var state: ViewState = .loggedOut
    @Published var rawJSON: String = ""
    /// Toggled to true once a login succeeds, so the login window can close itself.
    @Published var shouldDismissLogin = false
    /// Surfaced in the login window when a login attempt fails.
    @Published var loginError: String?

    /// PKCE material for the in-flight login attempt.
    private(set) var pkce: PKCE?

    var isLoggedIn: Bool { TokenStore.load() != nil }

    /// Short text for the menu bar, e.g. "8%".
    var menuBarTitle: String {
        if case let .loaded(s) = state {
            return "\(Int(s.sessionPercent.rounded()))%"
        }
        return isLoggedIn ? "…" : ""
    }

    func onAppear() {
        if isLoggedIn {
            if let cached = SnapshotStore.load() { state = .loaded(cached) }
            Task { await refresh() }
        } else {
            state = .loggedOut
        }
    }

    // MARK: - Login

    func startLogin() {
        pkce = PKCE.generate()
        shouldDismissLogin = false
        loginError = nil
    }

    var authorizeURL: URL? {
        pkce.map { OAuthClient.authorizeURL(pkce: $0) }
    }

    /// Log in by pasting a token from `claude setup-token`. Most reliable path:
    /// the token is minted by the official CLI for the user's subscription.
    func loginWithToken(_ raw: String) {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        loginError = nil
        TokenStore.save(TokenSet(accessToken: token, refreshToken: nil, expiresAt: nil))
        pkce = nil
        state = .loading
        Task {
            do {
                let result = try await UsageAPI.fetch()
                rawJSON = result.rawJSON
                if let snap = SnapshotStore.load() { state = .loaded(snap) }
                WidgetCenter.shared.reloadAllTimelines()
                shouldDismissLogin = true
            } catch {
                rawJSON = error.localizedDescription
                loginError = error.localizedDescription
                if Self.isAuthFailure(error) {
                    TokenStore.clear()          // token actually invalid
                    state = .loggedOut
                } else {
                    state = .error(error.localizedDescription)  // keep token (e.g. 429)
                }
            }
        }
    }

    /// True only for real auth failures (so we keep a valid token through a 429).
    static func isAuthFailure(_ error: Error) -> Bool {
        if case UsageError.notLoggedIn = error { return true }
        if case let UsageError.http(status, _) = error { return status == 401 || status == 403 }
        return false
    }

    /// Called when the web view (or manual paste) yields an authorization code.
    func completeLogin(rawCode: String) {
        guard let pkce else { return }
        state = .loading
        Task {
            do {
                let tokens = try await OAuthClient.exchangeCode(rawCode, pkce: pkce)
                TokenStore.save(tokens)
                self.pkce = nil
                shouldDismissLogin = true
                await refresh()
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func logout() {
        TokenStore.clear()
        pkce = nil
        rawJSON = ""
        state = .loggedOut
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Data

    func refresh() async {
        guard isLoggedIn else { state = .loggedOut; return }
        if case .loaded = state {} else { state = .loading }
        do {
            let result = try await UsageAPI.fetch()
            rawJSON = result.rawJSON
            if let snap = SnapshotStore.load() { state = .loaded(snap) }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            rawJSON = error.localizedDescription
            if let snap = SnapshotStore.load() {
                state = .loaded(snap)   // keep showing cached data
            } else {
                state = .error(error.localizedDescription)
            }
        }
    }
}
