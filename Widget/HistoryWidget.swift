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
            VStack(spacing: 8) {
                histogram("Session (5h)", value: \.session,
                          current: entry.snapshot?.sessionPercent, tint: .blue)
                histogram("Weekly (7d)", value: \.weekly,
                          current: entry.snapshot?.weeklyPercent, tint: .orange)
            }
        } else {
            label("Collecting data…", systemImage: "chart.bar")
        }
    }

    private func histogram(_ title: LocalizedStringKey,
                           value: KeyPath<HistoryPoint, Double>,
                           current: Double?,
                           tint: Color) -> some View {
        let points = Array(entry.history.suffix(28))
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
                Spacer()
                if let current {
                    Text("\(Int(current.rounded()))%")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Chart(points) { point in
                BarMark(x: .value("Time", point.date),
                        y: .value("Usage", point[keyPath: value]),
                        width: .ratio(0.6))
                    .foregroundStyle(tint.gradient)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { mark in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = mark.as(Date.self) {
                            let hours = Int((date.timeIntervalSince(entry.date) / 3600).rounded())
                            Text("\(hours)h").font(.system(size: 8))
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func label(_ text: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title2)
            Text(text).font(.caption2).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
