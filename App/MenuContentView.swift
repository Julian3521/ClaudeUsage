import SwiftUI
import AppKit
import Charts

/// The panel shown when clicking the menu-bar item.
struct MenuContentView: View {
    let viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .foregroundStyle(.tint)
                Text("Claude Usage").font(.headline)
                Spacer()
            }

            Divider()

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
            Button("Sign in") { openLogin() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func loaded(_ s: UsageSnapshot) -> some View {
        let settings = AppSettings.shared.settings
        let absolute = settings.showAbsoluteReset
        return VStack(alignment: .leading, spacing: 14) {
            UsageBar(title: "Current session (5h)",
                     percent: s.sessionPercent, resetsAt: s.sessionResetsAt, absoluteReset: absolute)
            UsageBar(title: "Weekly · all models (7d)",
                     percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt, absoluteReset: absolute)
            if settings.showSecondary {
                if let opus = s.opusPercent {
                    UsageBar(title: "Weekly · Opus (7d)", percent: opus, resetsAt: s.opusResetsAt, absoluteReset: absolute)
                }
                if let sonnet = s.sonnetPercent {
                    UsageBar(title: "Weekly · Sonnet (7d)", percent: sonnet, resetsAt: s.sonnetResetsAt, absoluteReset: absolute)
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
            VStack(alignment: .leading, spacing: 3) {
                Text("History").font(.caption2).foregroundStyle(.secondary)
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
                .chartYScale(domain: 0...100)
                .frame(height: 40)
                .accessibilityLabel("Usage history, weekly and session over time")
            }
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
        HStack(spacing: 8) {
            if viewModel.isLoggedIn {
                Button {
                    Task { await viewModel.refresh(force: true) }
                } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                    .keyboardShortcut("r")

                Menu {
                    Link("Open usage on claude.ai", destination: Config.usagePageURL)
                    SettingsLink { Text("Settings…") }
                    Button("Copy raw response") { copyRaw() }
                    Button("About Claude Usage") { showAbout() }
                    Button("Sign out", role: .destructive) { viewModel.logout() }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .frame(width: 40)
            }
            Spacer()
            Text("v\(Self.appVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("Quit") { NSApp.terminate(nil) }
                .font(.caption)
                .keyboardShortcut("q")
        }
    }

    private static let appVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    // MARK: - Actions

    private func openLogin() {
        viewModel.prepareLogin()
        openWindow(id: "login")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func copyRaw() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.rawJSON, forType: .string)
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: String(localized: "Not affiliated with Anthropic.")
                + "\ngithub.com/Julian3521/ClaudeUsage")
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
