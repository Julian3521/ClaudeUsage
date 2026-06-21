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
                histogram("Session (5h)", value: \.session, unit: .hour, tint: .blue)
                histogram("Weekly (7d)", value: \.weekly, unit: .day, tint: .orange)
            }
        } else {
            label("Collecting data…", systemImage: "chart.bar")
        }
    }

    private enum Unit { case hour, day }

    private func histogram(_ title: LocalizedStringKey,
                           value: KeyPath<HistoryPoint, Double>,
                           unit: Unit,
                           tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
                Spacer()
            }
            let points = Array(entry.history.suffix(36))
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    BarMark(x: .value("i", index),
                            y: .value("Usage", point[keyPath: value]))
                        .foregroundStyle(tint)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 100]) }
            .chartXAxis {
                AxisMarks(values: labelIndices(points.count)) { mark in
                    AxisValueLabel {
                        if let i = mark.as(Int.self), points.indices.contains(i) {
                            Text(verbatim: relativeLabel(points[i].date, unit: unit))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Up to four evenly spaced indices to label on the x-axis.
    private func labelIndices(_ count: Int) -> [Int] {
        guard count > 1 else { return [0] }
        let step = max(1, (count - 1) / 3)
        return Array(stride(from: 0, through: count - 1, by: step))
    }

    private func relativeLabel(_ date: Date, unit: Unit) -> String {
        let seconds = entry.date.timeIntervalSince(date)
        let suffix = unit == .day ? "d" : "h"
        let n = Int((seconds / (unit == .day ? 86400 : 3600)).rounded())
        return n <= 0 ? "0\(suffix)" : "-\(n)\(suffix)"
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
