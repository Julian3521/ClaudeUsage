import SwiftUI
import AppKit

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let viewModel = UsageViewModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Window("Bei Claude anmelden", id: "login") {
            LoginWindowView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 660)
    }
}

/// Drives the initial load and a periodic refresh of the menu-bar value,
/// independent of whether the user opens the menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in UsageViewModel.shared.onAppear() }
        timer = Timer.scheduledTimer(withTimeInterval: Config.widgetRefreshInterval,
                                     repeats: true) { _ in
            Task { @MainActor in await UsageViewModel.shared.refresh() }
        }
    }
}

/// The menu-bar status item label. Observes the view model so it updates live.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let title = viewModel.menuBarTitle
        if title.isEmpty {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
        } else {
            Label(title, systemImage: "gauge.with.dots.needle.bottom.50percent")
        }
    }
}
