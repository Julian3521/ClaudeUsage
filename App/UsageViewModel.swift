import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class UsageViewModel {
    static let shared = UsageViewModel()

    nonisolated init() {}

    enum ViewState: Equatable {
        case loggedOut
        case loading
        case loaded(UsageSnapshot)
        case error(String)
    }

    var state: ViewState = .loggedOut
    var rawJSON = ""
    /// Toggled to true once a login succeeds, so the login window can close itself.
    var shouldDismissLogin = false
    /// Surfaced in the login window when a login attempt fails.
    var loginError: String?
    /// True when the last fetch failed (shown as a warning in the menu bar).
    var lastFetchFailed = false

    var isLoggedIn: Bool { TokenStore.load() != nil }

    /// The currently loaded snapshot, if any (used by the menu-bar label).
    var snapshot: UsageSnapshot? {
        if case let .loaded(s) = state { return s }
        return nil
    }

    func onAppear() {
        guard isLoggedIn else { state = .loggedOut; return }
        if let cached = SnapshotStore.load() { state = .loaded(cached) }
        Task { await refresh() }
    }

    // MARK: - Login

    /// Reset transient login state before showing the login window.
    func prepareLogin() {
        shouldDismissLogin = false
        loginError = nil
    }

    /// Log in by pasting an access token (e.g. the existing Claude Code token,
    /// which carries the `user:profile` scope the usage endpoint requires).
    func loginWithToken(_ raw: String) {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        loginError = nil
        TokenStore.save(TokenSet(accessToken: token, refreshToken: nil, expiresAt: nil))
        state = .loading
        Task { await fetchAfterLogin() }
    }

    private func fetchAfterLogin() async {
        do {
            try await load()
            shouldDismissLogin = true
        } catch {
            rawJSON = error.localizedDescription
            loginError = error.localizedDescription
            if Self.isAuthFailure(error) {
                TokenStore.clear()              // token actually invalid
                state = .loggedOut
            } else {
                state = .error(error.localizedDescription)  // keep token (e.g. 429)
            }
        }
    }

    func logout() {
        TokenStore.clear()
        rawJSON = ""
        state = .loggedOut
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Data

    func refresh(force: Bool = false) async {
        guard isLoggedIn else { state = .loggedOut; return }
        // Skip the network if we already have a recent snapshot (rate-limit guard).
        if !force, let snapshot = SnapshotStore.load(),
           Date().timeIntervalSince(snapshot.fetchedAt) < Config.minFetchInterval {
            state = .loaded(snapshot)
            return
        }
        if case .loaded = state {} else { state = .loading }
        do {
            try await load()
        } catch {
            lastFetchFailed = true
            rawJSON = error.localizedDescription
            if let snapshot = SnapshotStore.load() {
                state = .loaded(snapshot)       // keep showing cached data
            } else {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Fetches usage, updates state + the shared snapshot, and reloads the widget.
    private func load() async throws {
        let result = try await UsageAPI.fetch()
        lastFetchFailed = false
        rawJSON = result.rawJSON
        if let snapshot = SnapshotStore.load() {
            HistoryStore.append(snapshot)
            state = .loaded(snapshot)
            let settings = AppSettings.shared.settings
            if settings.notifyAtHighUsage {
                UsageNotifier.check(snapshot, threshold: Double(settings.notifyThreshold))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Session windows

    /// Manually anchor a new 5h window now (sends a tiny request).
    func startSessionWindow() async {
        do {
            try await SessionStarter.ping()
            await refresh(force: true)
        } catch {
            lastFetchFailed = true
            rawJSON = error.localizedDescription
        }
    }

    /// Once per day, after the configured hour, anchor a new window automatically.
    func maybeAutoStartWindow() async {
        let settings = AppSettings.shared.settings
        guard settings.autoStartWindow, isLoggedIn else { return }
        let calendar = Calendar.current
        let now = Date()
        guard calendar.component(.hour, from: now) >= settings.autoStartHour else { return }
        let today = calendar.startOfDay(for: now).timeIntervalSince1970
        let key = "autoStart.lastDay"
        guard UserDefaults.standard.double(forKey: key) < today else { return }
        UserDefaults.standard.set(today, forKey: key)
        try? await SessionStarter.ping()
        await refresh(force: true)
    }

    /// True only for real auth failures (so we keep a valid token through a 429).
    static func isAuthFailure(_ error: Error) -> Bool {
        if case UsageError.notLoggedIn = error { return true }
        if case let UsageError.http(status, _) = error { return status == 401 || status == 403 }
        return false
    }
}
