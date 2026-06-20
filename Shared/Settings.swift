import Foundation
import Security

/// Which usage limit(s) drive the menu-bar readout.
enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case highest, session, weekly, both

    var label: String {
        switch self {
        case .highest: return "Highest of both"
        case .session: return "Session (5h)"
        case .weekly: return "Weekly (7d)"
        case .both: return "Session + weekly"
        }
    }

    /// The percentage value(s) to display for this metric (1 or 2).
    func values(_ s: UsageSnapshot) -> [Double] {
        switch self {
        case .session: return [s.sessionPercent]
        case .weekly: return [s.weeklyPercent]
        case .highest: return [max(s.sessionPercent, s.weeklyPercent)]
        case .both: return [s.sessionPercent, s.weeklyPercent]
        }
    }
}

struct Settings: Codable, Equatable, Sendable {
    var menuBarMetric: MenuBarMetric = .highest
    var menuBarShowBar = true
    var menuBarShowPercent = true
    var showSecondary = true          // Opus / Sonnet / spend rows
    var refreshMinutes = 20
    var notifyAtHighUsage = false
    var notifyThreshold = 90          // alert when any limit reaches this %

    /// Allowed refresh intervals (minutes).
    static let refreshOptions = [10, 20, 30, 60]
    /// Selectable alert thresholds (%).
    static let thresholdOptions = [70, 75, 80, 85, 90, 95]

    init() {}

    // Lenient decoding so older stored settings keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarMetric = (try? c.decode(MenuBarMetric.self, forKey: .menuBarMetric)) ?? .highest
        menuBarShowBar = (try? c.decode(Bool.self, forKey: .menuBarShowBar)) ?? true
        menuBarShowPercent = (try? c.decode(Bool.self, forKey: .menuBarShowPercent)) ?? true
        showSecondary = (try? c.decode(Bool.self, forKey: .showSecondary)) ?? true
        refreshMinutes = (try? c.decode(Int.self, forKey: .refreshMinutes)) ?? 20
        notifyAtHighUsage = (try? c.decode(Bool.self, forKey: .notifyAtHighUsage)) ?? false
        notifyThreshold = (try? c.decode(Int.self, forKey: .notifyThreshold)) ?? 90
    }
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
