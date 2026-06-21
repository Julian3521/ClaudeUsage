import SwiftUI
import AppKit
import Charts

/// The panel shown when clicking the menu-bar item.
struct MenuContentView: View {
    let viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .foregroundStyle(.tint)
                Text("Claude Usage").font(.headline)
                Spacer()
            }

            Divider()

            if viewModel.isRateLimited {
                Label {
                    if let until = viewModel.rateLimitEndsAt, let s = UsageFormat.resetString(until) {
                        Text("Rate limited — next check in \(s)")
                    } else {
                        Text("Rate limited — retrying automatically")
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            switch viewModel.state {
            case .loggedOut:
                loggedOut
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            case let .loaded(snapshot):
                loaded(snapshot)
            case let .error(message):
                errorView(message)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - States

    private var loggedOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to see your session and weekly limits.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLink { Text("Sign in") }
                .buttonStyle(.borderedProminent)
        }
    }

    private func loaded(_ s: UsageSnapshot) -> some View {
        let settings = AppSettings.shared.settings
        let fmt = settings.resetDisplay
        return VStack(alignment: .leading, spacing: 14) {
            UsageBar(title: "Current session (5h)",
                     percent: s.sessionPercent, resetsAt: s.sessionResetsAt,
                     resetFormat: fmt)
            UsageBar(title: "Weekly · all models (7d)",
                     percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt,
                     resetFormat: fmt, windowHours: 168)
            if settings.showSecondary {
                if let opus = s.opusPercent {
                    UsageBar(title: "Weekly · Opus (7d)", percent: opus, resetsAt: s.opusResetsAt,
                             resetFormat: fmt, windowHours: 168)
                }
                if let sonnet = s.sonnetPercent {
                    UsageBar(title: "Weekly · Sonnet (7d)", percent: sonnet, resetsAt: s.sonnetResetsAt,
                             resetFormat: fmt, windowHours: 168)
                }
                if let opus = s.opusPercent, let sonnet = s.sonnetPercent, opus + sonnet > 0 {
                    ModelMixBar(opus: opus, sonnet: sonnet)
                }
                if let spend = s.spendText {
                    HStack {
                        Text("Extra usage").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(spend).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            sparkline
            Text("Updated \(s.fetchedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        let history = HistoryStore.load()
        if history.count >= 2 {
            // Scale the y-axis to the data (rounded up to a "nice" bound) instead of a
            // fixed 0–100, so low usage isn't squashed into a flat line at the bottom.
            let peak = history.flatMap { [$0.session, $0.weekly] }.max() ?? 0
            let top = max(5, (peak / 5).rounded(.up) * 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("History").font(.caption2).foregroundStyle(.secondary)
                    legendDot(.blue.opacity(0.6), "Session")
                    legendDot(.orange, "Weekly")
                    Spacer()
                    Text(verbatim: "↑ \(Int(peak.rounded()))%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(history) { point in
                        LineMark(x: .value("Time", point.date),
                                 y: .value("Usage", point.weekly),
                                 series: .value("Series", "weekly"))
                            .foregroundStyle(.orange)
                    }
                    ForEach(history) { point in
                        LineMark(x: .value("Time", point.date),
                                 y: .value("Usage", point.session),
                                 series: .value("Series", "session"))
                            .foregroundStyle(.blue.opacity(0.5))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...top)
                .frame(height: 40)
                .accessibilityLabel("Usage history, weekly and session over time")
            }
        }
    }

    private func legendDot(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await viewModel.refresh(force: true) } }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if viewModel.isLoggedIn {
                Button {
                    Task { await viewModel.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .keyboardShortcut("r")
            }

            Spacer()

            Menu {
                if viewModel.isLoggedIn {
                    Button {
                        Task { await viewModel.startSessionWindow() }
                    } label: { Label("Start session window now", systemImage: "bolt") }
                    Link(destination: Config.usagePageURL) {
                        Label("Open usage on claude.ai", systemImage: "arrow.up.right.square")
                    }
                    Divider()
                }

                SettingsLink { Label("Settings…", systemImage: "gearshape") }
                    .keyboardShortcut(",")
                Divider()
                Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

}
