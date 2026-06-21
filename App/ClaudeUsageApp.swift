import SwiftUI
import AppKit

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings scene (opened from the menu). The menu-bar item itself is an
        // AppKit NSStatusItem managed by the AppDelegate for reliable live updates.
        SwiftUI.Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(viewModel: .shared)

        Task { @MainActor in
            UsageViewModel.shared.onAppear()
            while !Task.isCancelled {
                let minutes = Double(max(1, AppSettings.shared.settings.refreshMinutes))
                try? await Task.sleep(for: .seconds(minutes * 60))
                await UsageViewModel.shared.refresh(force: true)
            }
        }
    }
}
