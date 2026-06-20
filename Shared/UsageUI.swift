import SwiftUI

enum UsageFormat {
    /// "2h 30m" style remaining-until-reset string.
    static func resetString(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let secs = Int(date.timeIntervalSince(now))
        guard secs > 0 else { return String(localized: "now") }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func resetLabel(_ date: Date?, absolute: Bool = false, now: Date = Date()) -> String {
        if absolute, let date {
            return String(localized: "Resets at \(date.formatted(date: .omitted, time: .shortened))")
        }
        guard let s = resetString(date, now: now) else { return "—" }
        return String(localized: "Resets in \(s)")
    }

    /// Color for a usage percentage (0...100): green → orange → red.
    static func color(for percent: Double) -> Color {
        switch percent {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }
}

/// Circular progress ring with the percentage in the center.
struct UsageRing: View {
    let percent: Double          // 0...100
    var lineWidth: CGFloat = 8
    var showLabel: Bool = true

    private var fraction: Double { min(1, max(0, percent / 100)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(UsageFormat.color(for: percent),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showLabel {
                Text("\(Int(percent.rounded()))%")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(percent.rounded()))%")
    }
}

/// Horizontal bar with a title, percentage, and reset countdown.
struct UsageBar: View {
    let title: LocalizedStringKey
    let percent: Double
    let resetsAt: Date?
    var absoluteReset: Bool = false

    private var fraction: Double { min(1, max(0, percent / 100)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(UsageFormat.color(for: percent))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
            Text(UsageFormat.resetLabel(resetsAt, absolute: absoluteReset))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(percent.rounded()))%, \(UsageFormat.resetLabel(resetsAt, absolute: absoluteReset))")
    }
}
