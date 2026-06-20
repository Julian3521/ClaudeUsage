import Foundation
import Observation
import WidgetKit

/// Observable, persisted user settings, shared with the widget via the Keychain.
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

    nonisolated init() {}
}
