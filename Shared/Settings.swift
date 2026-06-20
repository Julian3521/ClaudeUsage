import Foundation
import Security

/// Which usage limit drives the menu-bar readout.
enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case highest, session, weekly

    var label: String {
        switch self {
        case .highest: return "Highest of both"
        case .session: return "Session (5h)"
        case .weekly: return "Weekly (7d)"
        }
    }
}

/// How the menu-bar item presents the value.
enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case percent, bar, barAndPercent, iconOnly

    var label: String {
        switch self {
        case .percent: return "Percentage"
        case .bar: return "Progress bar"
        case .barAndPercent: return "Bar + percentage"
        case .iconOnly: return "Icon only"
        }
    }
}

struct Settings: Codable, Equatable, Sendable {
    var menuBarMetric: MenuBarMetric = .highest
    var menuBarStyle: MenuBarStyle = .barAndPercent
    var showOpus = true
}

/// Persisted in the shared Keychain group so the app and the widget agree.
enum SettingsStore {
    private static let account = "settings"

    static func load() -> Settings {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    static func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        let base = baseQuery()
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.keychainSettingsService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
