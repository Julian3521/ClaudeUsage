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

/// The menu-bar status item. Observes the view model + settings so it updates live.
struct MenuBarLabel: View {
    let viewModel: UsageViewModel

    private let icon = "gauge.with.dots.needle.bottom.50percent"

    var body: some View {
        let percent = viewModel.menuBarPercent
        switch AppSettings.shared.settings.menuBarStyle {
        case .iconOnly:
            Image(systemName: icon)
        case .percent:
            if let percent { Text("\(Int(percent.rounded()))%") }
            else { Image(systemName: icon) }
        case .bar:
            if let percent { MenuBarGauge(percent: percent) }
            else { Image(systemName: icon) }
        case .barAndPercent:
            if let percent {
                HStack(spacing: 4) {
                    MenuBarGauge(percent: percent)
                    Text("\(Int(percent.rounded()))%")
                }
            } else {
                Image(systemName: icon)
            }
        }
    }
}

/// A compact progress bar sized for the menu bar (rendered monochrome there).
struct MenuBarGauge: View {
    let percent: Double

    var body: some View {
        let fraction = min(1, max(0, percent / 100))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.3))
                Capsule().fill(.primary).frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(width: 24, height: 6)
    }
}
