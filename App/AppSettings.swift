import Foundation
import Observation
import ServiceManagement
import WidgetKit

/// Observable, persisted user settings. `settings` is shared with the widget via
/// the Keychain; `launchAtLogin` is app-only (backed by ServiceManagement).
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var settings = SettingsStore.load() {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled) {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = oldValue   // revert if the system call failed
            }
        }
    }

    nonisolated init() {}
}
