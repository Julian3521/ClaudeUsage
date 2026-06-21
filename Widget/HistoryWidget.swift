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
                histogram("Session (5h)", value: \.session, tint: .blue)
                histogram("Weekly (7d)", value: \.weekly, tint: .orange)
            }
        } else {
            label("Collecting data…", systemImage: "chart.bar")
        }
    }

    private func histogram(_ title: LocalizedStringKey,
                           value: KeyPath<HistoryPoint, Double>,
                           tint: Color) -> some View {
        let points = Array(entry.history.suffix(36))
        let marks = labelIndices(points.count)
        let top = yTop(points, value)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
                Spacer()
            }
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    BarMark(x: .value("i", index),
                            y: .value("Usage", point[keyPath: value]))
                        .foregroundStyle(tint)
                }
            }
            // Scale to the max in the shown period so variation is visible.
            .chartYScale(domain: 0...top)
            .chartYAxis { AxisMarks(values: [0, top]) }
            .chartXAxis {
                AxisMarks(values: marks) { mark in
                    AxisValueLabel {
                        if let i = mark.as(Int.self), let pos = marks.firstIndex(of: i) {
                            let back = marks.count - 1 - pos
                            Text(verbatim: back == 0 ? "0" : "-\(back)").font(.system(size: 8))
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Top of the y-axis: the period's max usage, rounded up (min 5).
    private func yTop(_ points: [HistoryPoint], _ value: KeyPath<HistoryPoint, Double>) -> Double {
        let maxValue = points.map { $0[keyPath: value] }.max() ?? 0
        return max(5, (maxValue / 5).rounded(.up) * 5)
    }

    /// Up to four evenly spaced indices to label on the x-axis (labeled -3…0).
    private func labelIndices(_ count: Int) -> [Int] {
        guard count > 1 else { return [0] }
        let step = max(1, (count - 1) / 3)
        return Array(stride(from: 0, through: count - 1, by: step))
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
