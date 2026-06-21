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
    /// Surfaced in the Account settings when a login attempt fails.
    var loginError: String?
    /// True when the last fetch failed.
    var lastFetchFailed = false
    /// While set and in the future, skip network polling (rate-limit backoff).
    private var rateLimitedUntil: Date?

    var isLoggedIn: Bool { TokenStore.load() != nil }
    /// Observable signed-in state (drives the Account settings UI).
    var isSignedIn: Bool { state != .loggedOut }

    /// Currently in a rate-limit backoff window (drives the menu-bar indicator).
    var isRateLimited: Bool {
        if let until = rateLimitedUntil { return Date() < until }
        return false
    }

    /// When the current rate-limit backoff ends (drives the menu countdown).
    var rateLimitEndsAt: Date? { isRateLimited ? rateLimitedUntil : nil }

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
        } catch {
            rawJSON = error.localizedDescription
            loginError = error.localizedDescription
            applyCooldown(error)
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
        // Honor a rate-limit backoff (manual refresh ignores it to let you retry).
        if !force, let until = rateLimitedUntil, Date() < until {
            if let snapshot = SnapshotStore.load() { state = .loaded(snapshot) }
            return
        }
        // Skip the network if we already have a recent snapshot.
        if !force, let snapshot = SnapshotStore.load(),
           Date().timeIntervalSince(snapshot.fetchedAt) < Config.minFetchInterval {
            state = .loaded(snapshot)
            return
        }
        if case .loaded = state {} else { state = .loading }
        do {
            try await load()
        } catch {
            rawJSON = error.localizedDescription
            if Self.isAuthFailure(error) {
                // Token expired/revoked: sign out so the menu prompts re-login.
                TokenStore.clear()
                lastFetchFailed = false
                state = .loggedOut
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
            lastFetchFailed = true
            applyCooldown(error)
            if let snapshot = SnapshotStore.load() {
                state = .loaded(snapshot)       // keep showing cached data
            } else {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// On a 429, pause polling. The endpoint sends no Retry-After and short
    /// retries keep it stuck, so back off a long 30 minutes by default.
    private func applyCooldown(_ error: Error) {
        if case let UsageError.rateLimited(retryAfter) = error {
            rateLimitedUntil = Date().addingTimeInterval(retryAfter ?? 1800)
        }
    }

    /// Fetches usage, updates state + the shared snapshot, and reloads the widget.
    private func load() async throws {
        let result = try await UsageAPI.fetch()
        lastFetchFailed = false
        rateLimitedUntil = nil
        rawJSON = result.rawJSON
        if let snapshot = SnapshotStore.load() {
            HistoryStore.append(snapshot)
            state = .loaded(snapshot)
            let settings = AppSettings.shared.settings
            if settings.notifyAtHighUsage {
                UsageNotifier.check(snapshot, threshold: Double(settings.notifyThreshold))
            }
            scheduleAutoOpen(snapshot)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Session windows

    @ObservationIgnored private var autoOpenTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledReset: Date?

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

    /// When enabled, schedule a tiny request ~1 minute after the current 5h
    /// window resets, so a fresh window opens immediately and keeps rolling.
    func scheduleAutoOpen(_ snapshot: UsageSnapshot) {
        guard AppSettings.shared.settings.autoOpenSession, isLoggedIn,
              let resetsAt = snapshot.sessionResetsAt else {
            autoOpenTask?.cancel(); autoOpenTask = nil; scheduledReset = nil
            return
        }
        guard scheduledReset != resetsAt else { return }   // already scheduled
        scheduledReset = resetsAt
        autoOpenTask?.cancel()
        let delay = max(0, resetsAt.timeIntervalSinceNow) + 60
        autoOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            _ = try? await SessionStarter.ping()
            await self?.refresh(force: true)
        }
    }

    /// True only for real auth failures (so we keep a valid token through a 429).
    static func isAuthFailure(_ error: Error) -> Bool {
        if case UsageError.notLoggedIn = error { return true }
        if case let UsageError.http(status, _) = error { return status == 401 || status == 403 }
        return false
    }
}
