import SwiftUI

enum UsageFormat {
    /// "2d 3h" / "2h 30m" style remaining-until-reset string.
    static func resetString(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let secs = Int(date.timeIntervalSince(now))
        guard secs > 0 else { return String(localized: "now") }
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// "Runs out today 14:30" — same day wording as the reset labels.
    static func runsOutLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return String(localized: "Runs out today \(time)") }
        if Calendar.current.isDateInTomorrow(date) { return String(localized: "Runs out tomorrow \(time)") }
        return String(localized: "Runs out \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
    }

    static func resetLabel(_ date: Date?, format: ResetFormat = .relative, now: Date = Date()) -> String {
        switch format {
        case .relative:
            guard let s = resetString(date, now: now) else { return "—" }
            return String(localized: "Resets in \(s)")
        case .weekday:
            return dayLabel(date) { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        case .date:
            return dayLabel(date) { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) }
        }
    }

    /// Uses "today"/"tomorrow" when the reset falls on those days (so e.g. a reset
    /// today and one next week don't both just read "Sun"); otherwise `fallback`.
    private static func dayLabel(_ date: Date?, fallback: (Date) -> String) -> String {
        guard let date else { return "—" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return String(localized: "Resets today \(time)") }
        if Calendar.current.isDateInTomorrow(date) { return String(localized: "Resets tomorrow \(time)") }
        return String(localized: "Resets \(fallback(date))")
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

/// Horizontal bar with a title, percentage, and reset countdown. When
/// `windowHours` is set, it also draws an "on-pace" marker (where usage would be
/// if spent evenly across the window) and a caption showing over/under pace.
struct UsageBar: View {
    let title: LocalizedStringKey
    let percent: Double
    let resetsAt: Date?
    var resetFormat: ResetFormat = .relative
    var windowHours: Double? = nil
    /// Projected moment this window hits 100%. Replaces the pace caption — but
    /// only when you're burning faster than an even pace: below that line the
    /// calm "11% to spare" is the more useful reading, and a projection built
    /// from a slow trend would only be alarmist noise.
    var runsOutAt: Date? = nil

    /// Percentage points off an even burn before we call it over/under pace.
    private static let paceTolerance = 5.0

    /// Points ahead of (positive) or behind (negative) an even burn.
    private var paceDelta: Double? {
        paceFraction.map { (fraction - $0) * 100 }
    }

    /// Shown only when over pace and the limit would land before the reset.
    private var forecast: Date? {
        guard let runsOutAt, let delta = paceDelta, delta >= Self.paceTolerance
        else { return nil }
        guard let resetsAt else { return runsOutAt }
        return runsOutAt < resetsAt ? runsOutAt : nil
    }

    private var fraction: Double { min(1, max(0, percent / 100)) }

    /// Fraction of the window elapsed (0...1) — the even-pace position.
    private var paceFraction: Double? {
        guard let windowHours, let resetsAt, windowHours > 0 else { return nil }
        let length = windowHours * 3600
        let start = resetsAt.addingTimeInterval(-length)
        return min(1, max(0, Date().timeIntervalSince(start) / length))
    }

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
                    if let pace = paceFraction {
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 2, height: 12)
                            .offset(x: min(geo.size.width - 2, geo.size.width * pace))
                            .help("Marker = even usage across the window")
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 6) {
                Text(UsageFormat.resetLabel(resetsAt, format: resetFormat))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                paceCaption.font(.caption2.weight(.medium))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(percent.rounded()))%, \(UsageFormat.resetLabel(resetsAt, format: resetFormat))"
            + (forecast.map { ", \(UsageFormat.runsOutLabel($0))" } ?? ""))
    }

    @ViewBuilder
    private var paceCaption: some View {
        if let forecast {
            Text(verbatim: UsageFormat.runsOutLabel(forecast))
                .foregroundStyle(percent >= 85 ? .red : .orange)
        } else if let paceDelta {
            let delta = Int(paceDelta.rounded())
            if Double(delta) >= Self.paceTolerance {
                (Text(verbatim: "\(delta)% ") + Text("over pace")).foregroundStyle(.orange)
            } else if Double(delta) <= -Self.paceTolerance {
                (Text(verbatim: "\(-delta)% ") + Text("to spare")).foregroundStyle(.green)
            } else {
                Text("on pace").foregroundStyle(.secondary)
            }
        }
    }
}

extension ModelUsage {
    /// Stable colour per model, so the mix bar and its legend always agree.
    var tint: Color {
        switch key {
        case "opus": return .purple
        case "sonnet": return .teal
        case "fable": return .pink
        case "haiku": return .mint
        default: return .gray
        }
    }
}
