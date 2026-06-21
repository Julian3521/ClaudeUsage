import WidgetKit
import SwiftUI
import Charts

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let loggedIn: Bool
    let showSecondary: Bool
    let resetFormat: ResetFormat
    let history: [HistoryPoint]
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder, loggedIn: true,
                   showSecondary: true, resetFormat: .relative, history: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(entry(snapshot: SnapshotStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // The widget does NOT call the network itself — the menu-bar app is the
        // single fetcher (it writes the snapshot and reloads our timeline). This
        // avoids hammering the rate-limited usage endpoint from multiple processes.
        // The widget only re-reads the cached snapshot (the app does the throttled
        // network fetching), so refresh often to track the app closely.
        let next = Date().addingTimeInterval(Double(Config.minRefreshMinutes) * 60)
        completion(Timeline(entries: [entry(snapshot: SnapshotStore.load())],
                            policy: .after(next)))
    }

    private func entry(snapshot: UsageSnapshot?) -> UsageEntry {
        let settings = SettingsStore.load()
        return UsageEntry(date: Date(),
                          snapshot: snapshot,
                          loggedIn: TokenStore.load() != nil,
                          showSecondary: settings.showSecondary,
                          resetFormat: settings.resetDisplay,
                          history: HistoryStore.load())
    }
}

// MARK: - Widget

struct ClaudeUsageWidget: Widget {
    let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: ClaudeWidgetConfigIntent.self,
                               provider: ConfigurableUsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Config.usagePageURL)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your session and weekly limits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Like `UsageProvider`, but driven by the per-widget configuration intent so each
/// placed widget can choose its own options (right-click → Edit Widget).
struct ConfigurableUsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder, loggedIn: true,
                   showSecondary: true, resetFormat: .relative, history: [])
    }

    func snapshot(for configuration: ClaudeWidgetConfigIntent,
                  in context: Context) async -> UsageEntry {
        entry(SnapshotStore.load() ?? .placeholder, configuration)
    }

    func timeline(for configuration: ClaudeWidgetConfigIntent,
                  in context: Context) async -> Timeline<UsageEntry> {
        // The widget only re-reads the cached snapshot (the app does the throttled
        // network fetching), so refresh often to track the app closely.
        let next = Date().addingTimeInterval(Double(Config.minRefreshMinutes) * 60)
        return Timeline(entries: [entry(SnapshotStore.load(), configuration)], policy: .after(next))
    }

    private func entry(_ snapshot: UsageSnapshot?, _ config: ClaudeWidgetConfigIntent) -> UsageEntry {
        UsageEntry(date: Date(),
                   snapshot: snapshot,
                   loggedIn: TokenStore.load() != nil,
                   showSecondary: config.showSecondary,
                   resetFormat: config.resetDisplay,
                   history: HistoryStore.load())
    }
}

// MARK: - Views

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var opus: (Double, Date?)? {
        guard entry.showSecondary, let snapshot = entry.snapshot,
              let percent = snapshot.opusPercent else { return nil }
        return (percent, snapshot.opusResetsAt)
    }

    var body: some View {
        if !entry.loggedIn {
            signedOut
        } else if let s = entry.snapshot {
            switch family {
            case .systemSmall: smallView(s)
            case .systemMedium: mediumView(s)
            case .systemLarge: largeView(s)
            default: smallView(s)
            }
        } else {
            ProgressView()
        }
    }

    // Home-screen small: two compact bars.
    private func smallView(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Claude", systemImage: "gauge.with.dots.needle.67percent")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            UsageBar(title: "Session", percent: s.sessionPercent, resetsAt: s.sessionResetsAt,
                     resetFormat: entry.resetFormat)
            UsageBar(title: "Weekly", percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt,
                     resetFormat: entry.resetFormat)
        }
    }

    // Home-screen medium: rings, centered vertically.
    private func mediumView(_ s: UsageSnapshot) -> some View {
        HStack(spacing: 24) {
            ringColumn("Session", percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
            ringColumn("Weekly", percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
            if let opus { ringColumn("Opus", percent: opus.0, resetsAt: opus.1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ringColumn(_ title: LocalizedStringKey, percent: Double, resetsAt: Date?) -> some View {
        VStack(spacing: 5) {
            UsageRing(percent: percent, lineWidth: 7)
                .frame(width: 54, height: 54)
            Text(title).font(.caption2.weight(.medium))
            Text(UsageFormat.resetLabel(resetsAt, format: entry.resetFormat))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // Large: rings on top (with breathing room), bars below.
    private func largeView(_ s: UsageSnapshot) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 28) {
                ringColumn("Session", percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
                ringColumn("Weekly", percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
                if let opus { ringColumn("Opus", percent: opus.0, resetsAt: opus.1) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            Divider()

            UsageBar(title: "Current session (5h)",
                     percent: s.sessionPercent, resetsAt: s.sessionResetsAt,
                     resetFormat: entry.resetFormat)
            UsageBar(title: "Weekly · all models (7d)",
                     percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt,
                     resetFormat: entry.resetFormat)
            if entry.showSecondary, let sonnet = s.sonnetPercent {
                UsageBar(title: "Weekly · Sonnet (7d)",
                         percent: sonnet, resetsAt: s.sonnetResetsAt,
                         resetFormat: entry.resetFormat)
            }
            if entry.showSecondary, let spend = s.spendText {
                HStack {
                    Text("Extra usage").font(.caption.weight(.semibold))
                    Spacer()
                    Text(spend).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
            Text("Sign in from the app")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}
