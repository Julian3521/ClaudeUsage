import SwiftUI
import AppKit

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let viewModel = UsageViewModel.shared
    // Owned via @State so the menu-bar label re-renders when settings change.
    @State private var appSettings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel, settings: appSettings.settings)
        }
        .menuBarExtraStyle(.window)

        Window("Sign in to Claude", id: "login") {
            LoginWindowView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 460)

        SwiftUI.Settings {
            SettingsView()
        }
    }
}

/// Drives the initial load and a periodic refresh of the menu-bar value at the
/// configured interval, independent of whether the user opens the menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            UsageViewModel.shared.onAppear()
            while !Task.isCancelled {
                let minutes = Double(max(5, AppSettings.shared.settings.refreshMinutes))
                try? await Task.sleep(for: .seconds(minutes * 60))
                await UsageViewModel.shared.refresh()
            }
        }
    }
}

/// The menu-bar status item. Observes the view model + settings so it updates live.
struct MenuBarLabel: View {
    let viewModel: UsageViewModel
    let settings: Settings

    var body: some View {
        HStack(spacing: 3) {
            if viewModel.lastFetchFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let snapshot = viewModel.snapshot {
                MenuBarContent(values: settings.menuBarMetric.values(snapshot),
                               showBar: settings.menuBarShowBar,
                               showPercent: settings.menuBarShowPercent)
            } else {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let title = String(localized: "Claude Usage")
        guard let s = viewModel.snapshot else { return title }
        return "\(title): \(Int(s.sessionPercent.rounded()))% / \(Int(s.weeklyPercent.rounded()))%"
    }
}
