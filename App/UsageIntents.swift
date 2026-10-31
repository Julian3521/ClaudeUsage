import AppIntents
import Foundation

/// "Check Claude Usage" — exposes the current usage to Shortcuts, Spotlight and
/// Siri. Reads the shared snapshot, so it answers instantly without a fetch.
struct CheckClaudeUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Claude Usage"
    static let description = IntentDescription(
        "Reports your current Claude usage: today's budget, session (5h) and weekly (7d).")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard TokenStore.load() != nil else {
            return .result(value: "Not signed in",
                           dialog: "You're not signed in to Claude Usage.")
        }
        guard let s = SnapshotStore.load() else {
            return .result(value: "No data yet",
                           dialog: "No usage data yet — open Claude Usage once.")
        }
        var parts: [String] = []
        if let daily = DailyBudget.today(history: HistoryStore.load(), snapshot: s,
                                         mode: SettingsStore.load().dailyBudget) {
            parts.append("today \(Int(daily.used.rounded()))% of \(Int(daily.budget.rounded()))%")
        }
        if s.hasSession { parts.append("session \(Int(s.sessionPercent.rounded()))%") }
        parts.append("weekly \(Int(s.weeklyPercent.rounded()))%")
        let summary = parts.joined(separator: ", ")
        // The snapshot can be hours old (Mac asleep, rate-limit backoff). Saying
        // so is better than reporting a stale number as the current one.
        let age = Date().timeIntervalSince(s.fetchedAt)
        let asOf = age > Double(Config.minRefreshMinutes) * 60
            ? " as of \(s.fetchedAt.formatted(date: .omitted, time: .shortened))"
            : ""
        return .result(
            value: summary.prefix(1).uppercased() + summary.dropFirst() + asOf,
            dialog: "Claude usage — \(summary)\(asOf).")
    }
}

/// Registers Siri/Spotlight phrases. Phrases must each contain the app name.
struct ClaudeUsageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckClaudeUsageIntent(),
            phrases: [
                "Check \(.applicationName)",
                "What's my \(.applicationName)",
                "\(.applicationName) status",
                "Wie viel \(.applicationName) habe ich noch",
            ],
            shortTitle: "Check Usage",
            systemImageName: "gauge.with.dots.needle.bottom.50percent"
        )
    }
}
