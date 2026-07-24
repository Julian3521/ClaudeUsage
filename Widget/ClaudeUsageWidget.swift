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
    /// Model rows hidden in the app's Display settings (widgets follow the same
    /// per-model choice; the widget's own toggle only switches the group off).
    var hiddenModels: Set<String> = []
    var showSpend = true

    /// Per-model windows this widget should show, in display order.
    var models: [ModelUsage] {
        guard showSecondary, let snapshot else { return [] }
        return snapshot.models.filter { !hiddenModels.contains($0.key) }
    }
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
                          history: HistoryStore.load(),
                          hiddenModels: settings.hiddenModels,
                          showSpend: settings.showSpend)
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
        // Which models to show is a global choice (Display settings); whether the
        // group appears at all stays per-widget.
        let settings = SettingsStore.load()
        return UsageEntry(date: Date(),
                          snapshot: snapshot,
                          loggedIn: TokenStore.load() != nil,
                          showSecondary: config.showSecondary,
                          resetFormat: config.resetDisplay,
                          history: HistoryStore.load(),
                          hiddenModels: settings.hiddenModels,
                          showSpend: settings.showSpend)
    }
}

// MARK: - Views

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    /// The one model that fits next to the session/weekly rings.
    private var leadModel: ModelUsage? { entry.models.first }

    private func runsOut(_ current: Double, _ value: @escaping (HistoryPoint) -> Double?) -> Date? {
        guard let fetchedAt = entry.snapshot?.fetchedAt else { return nil }
        return UsageForecast.runsOut(history: entry.history, current: current,
                                     currentAt: fetchedAt, value: value)
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
            if let model = leadModel {
                ringColumn("\(model.displayName)", percent: model.percent, resetsAt: model.resetsAt)
            }
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
                if let model = leadModel {
                    ringColumn("\(model.displayName)", percent: model.percent, resetsAt: model.resetsAt)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            Divider()

            UsageBar(title: "Current session (5h)",
                     percent: s.sessionPercent, resetsAt: s.sessionResetsAt,
                     resetFormat: entry.resetFormat, windowHours: 5,
                     runsOutAt: runsOut(s.sessionPercent) { $0.session })
            UsageBar(title: "Weekly · all models (7d)",
                     percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt,
                     resetFormat: entry.resetFormat, windowHours: 168,
                     runsOutAt: runsOut(s.weeklyPercent) { $0.weekly })
            // Cap the rows so the large widget can't overflow once several
            // models are reported; the lead model already has a ring above.
            ForEach(Array(entry.models.dropFirst().prefix(2))) { model in
                UsageBar(title: "Weekly · \(model.displayName) (7d)",
                         percent: model.percent, resetsAt: model.resetsAt,
                         resetFormat: entry.resetFormat)
            }
            if entry.showSecondary, entry.showSpend, let spend = s.spendText {
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
