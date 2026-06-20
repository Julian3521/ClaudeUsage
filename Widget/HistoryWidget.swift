import WidgetKit
import SwiftUI
import Charts

/// A second widget: bar-chart histograms of the 5-hour and weekly utilization
/// over time (full bar = 100%).
struct ClaudeUsageHistoryWidget: Widget {
    let kind = "ClaudeUsageHistoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            HistoryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Config.usagePageURL)
        }
        .configurationDisplayName("Claude Usage History")
        .description("Utilization of the 5-hour and weekly windows over time.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct HistoryWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if !entry.loggedIn {
            label("Sign in from the app", systemImage: "person.crop.circle.badge.exclamationmark")
        } else if entry.history.count >= 2 {
            VStack(spacing: 12) {
                histogram("Session (5h)", value: \.session)
                histogram("Weekly (7d)", value: \.weekly)
            }
        } else {
            label("Collecting data…", systemImage: "chart.bar")
        }
    }

    private func histogram(_ title: LocalizedStringKey,
                           value: KeyPath<HistoryPoint, Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold))
            Chart(entry.history) { point in
                BarMark(x: .value("Time", point.date),
                        y: .value("Usage", point[keyPath: value]))
                    .foregroundStyle(UsageFormat.color(for: point[keyPath: value]))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
        }
    }

    private func label(_ text: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title2)
            Text(text).font(.caption2).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}
