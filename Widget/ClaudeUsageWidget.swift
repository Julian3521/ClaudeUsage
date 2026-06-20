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
        let next = Date().addingTimeInterval(Config.widgetRefreshInterval)

        guard TokenStore.load() != nil else {
            let entry = UsageEntry(date: Date(), snapshot: nil, loggedIn: false)
            completion(Timeline(entries: [entry], policy: .after(next)))
            return
        }

        Task {
            // Refresh from the network; fall back to the cached snapshot on failure.
            _ = try? await UsageAPI.fetch()
            let snapshot = SnapshotStore.load()
            let entry = UsageEntry(date: Date(), snapshot: snapshot, loggedIn: true)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
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
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular])
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
            case .accessoryCircular: circularView(s)
            case .accessoryRectangular: rectangularView(s)
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

    // Lock-screen circular: session gauge.
    private func circularView(_ s: UsageSnapshot) -> some View {
        Gauge(value: min(1, s.sessionPercent / 100)) {
            Text("S")
        } currentValueLabel: {
            Text("\(Int(s.sessionPercent.rounded()))")
        }
        .gaugeStyle(.accessoryCircular)
    }

    // Lock-screen rectangular: both limits.
    private func rectangularView(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude Usage").font(.headline)
            Text("Session \(Int(s.sessionPercent.rounded()))% · \(UsageFormat.resetString(s.sessionResetsAt) ?? "—")")
            Text("Woche \(Int(s.weeklyPercent.rounded()))% · \(UsageFormat.resetString(s.weeklyResetsAt) ?? "—")")
        }
        .font(.caption2)
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
