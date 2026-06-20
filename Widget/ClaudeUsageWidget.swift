import WidgetKit
import SwiftUI

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let loggedIn: Bool
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder, loggedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = SnapshotStore.load() ?? .placeholder
        completion(UsageEntry(date: Date(), snapshot: snapshot,
                              loggedIn: TokenStore.load() != nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // The widget does NOT call the network itself — the menu-bar app is the
        // single fetcher (it writes the snapshot and reloads our timeline). This
        // avoids hammering the usage endpoint (which rate-limits) from multiple
        // widget processes in addition to the app.
        let next = Date().addingTimeInterval(Config.widgetRefreshInterval)
        let entry = UsageEntry(date: Date(),
                               snapshot: SnapshotStore.load(),
                               loggedIn: TokenStore.load() != nil)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct ClaudeUsageWidget: Widget {
    let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Dein Session- und Wochenlimit auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

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
            UsageBar(title: "Session", percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
            UsageBar(title: "Woche", percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
        }
    }

    // Home-screen medium: two rings, like the app.
    private func mediumView(_ s: UsageSnapshot) -> some View {
        HStack(spacing: 24) {
            ringColumn("Session", percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
            ringColumn("Woche", percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
            if let opus = s.opusPercent {
                ringColumn("Opus", percent: opus, resetsAt: s.opusResetsAt)
            }
        }
    }

    private func ringColumn(_ title: String, percent: Double, resetsAt: Date?) -> some View {
        VStack(spacing: 6) {
            UsageRing(percent: percent, lineWidth: 8)
                .frame(width: 64, height: 64)
            Text(title).font(.caption2.weight(.medium))
            Text(UsageFormat.resetLabel(resetsAt))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // Large: rings on top, bars below.
    private func largeView(_ s: UsageSnapshot) -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("Claude Usage", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 24) {
                ringColumn("Session", percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
                ringColumn("Woche", percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
                if let opus = s.opusPercent {
                    ringColumn("Opus", percent: opus, resetsAt: s.opusResetsAt)
                }
            }
            Spacer(minLength: 0)
            UsageBar(title: "Current session (5h)",
                     percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
            UsageBar(title: "Weekly · all models (7d)",
                     percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
            Text("In der App anmelden")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}
