import SwiftUI
import AppKit

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
        VStack(alignment: .leading, spacing: 14) {
            UsageBar(title: "Current session (5h)",
                     percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
            UsageBar(title: "Weekly · all models (7d)",
                     percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
            if AppSettings.shared.settings.showSecondary {
                if let opus = s.opusPercent {
                    UsageBar(title: "Weekly · Opus (7d)", percent: opus, resetsAt: s.opusResetsAt)
                }
                if let sonnet = s.sonnetPercent {
                    UsageBar(title: "Weekly · Sonnet (7d)", percent: sonnet, resetsAt: s.sonnetResetsAt)
                }
                if let spend = s.spendText {
                    HStack {
                        Text("Extra usage").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(spend).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Updated \(s.fetchedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    SettingsLink { Text("Settings…") }
                    Button("Copy raw response") { copyRaw() }
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
}
