import AppIntents
import Foundation

/// "Check Claude Usage" — exposes the current usage to Shortcuts, Spotlight and
/// Siri. Reads the shared snapshot, so it answers instantly without a fetch.
struct CheckClaudeUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Claude Usage"
    static let description = IntentDescription(
        "Reports your current Claude session (5h) and weekly (7d) usage.")
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
        let session = Int(s.sessionPercent.rounded())
        let weekly = Int(s.weeklyPercent.rounded())
        return .result(
            value: "Session \(session)%, weekly \(weekly)%",
            dialog: "Claude usage — session \(session) percent, weekly \(weekly) percent.")
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
