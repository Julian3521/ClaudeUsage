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
    }

    var authorizeURL: URL? {
        pkce.map { OAuthClient.authorizeURL(pkce: $0) }
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
