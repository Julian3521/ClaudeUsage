import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater. The app auto-checks the GitHub
/// appcast in the background; the menu offers a manual "Check for Updates…".
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true begins background checks using the SUFeedURL /
        // SUPublicEDKey from Info.plist.
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// Bring the (menu-bar) app forward and run a user-initiated update check.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
