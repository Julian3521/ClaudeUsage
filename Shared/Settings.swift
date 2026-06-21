import AppIntents
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

/// How a reset time is shown in reset labels.
enum ResetFormat: String, Codable, CaseIterable, Sendable {
    case relative   // "Resets in 2d 3h"
    case weekday    // "Resets Sat 14:30"
    case date       // "Resets 25 Jun, 14:30"

    var label: String {
        switch self {
        case .relative: return "Countdown"
        case .weekday: return "Weekday + time"
        case .date: return "Date + time"
        }
    }
}

/// Lets `ResetFormat` appear as a picker when editing a widget.
extension ResetFormat: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Reset display" }
    static var caseDisplayRepresentations: [ResetFormat: DisplayRepresentation] {
        [.relative: "Countdown", .weekday: "Weekday + time", .date: "Date + time"]
    }
}

struct Settings: Codable, Equatable, Sendable {
    var menuBarMetric: MenuBarMetric = .highest
    var menuBarShowBar = true
    var menuBarShowPercent = true
    var showSecondary = true          // Opus / Sonnet / spend rows
    var refreshMinutes = 30
    var notifyAtHighUsage = false
    var notifyThreshold = 90          // alert when any limit reaches this %
    var resetDisplay: ResetFormat = .relative   // countdown / weekday / date
    var autoOpenSession = false       // auto-ping ~1 min after each 5h reset

    /// Allowed refresh intervals (minutes). The usage endpoint rate-limits hard,
    /// so 15 min is the lowest interval that reliably avoids 429s.
    static let refreshOptions = [15, 30, 60, 120]
    /// Selectable alert thresholds (%).
    static let thresholdOptions = [70, 75, 80, 85, 90, 95]

    init() {}

    enum CodingKeys: String, CodingKey {
        case menuBarMetric, menuBarShowBar, menuBarShowPercent, showSecondary
        case refreshMinutes, notifyAtHighUsage, notifyThreshold
        case resetDisplay, autoOpenSession
        case showAbsoluteReset   // legacy (Bool) — migrated to resetDisplay
    }

    // Lenient decoding so older stored settings keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarMetric = (try? c.decode(MenuBarMetric.self, forKey: .menuBarMetric)) ?? .highest
        menuBarShowBar = (try? c.decode(Bool.self, forKey: .menuBarShowBar)) ?? true
        menuBarShowPercent = (try? c.decode(Bool.self, forKey: .menuBarShowPercent)) ?? true
        showSecondary = (try? c.decode(Bool.self, forKey: .showSecondary)) ?? true
        let storedRefresh = (try? c.decode(Int.self, forKey: .refreshMinutes)) ?? 30
        refreshMinutes = Settings.refreshOptions.contains(storedRefresh) ? storedRefresh : 30
        notifyAtHighUsage = (try? c.decode(Bool.self, forKey: .notifyAtHighUsage)) ?? false
        notifyThreshold = (try? c.decode(Int.self, forKey: .notifyThreshold)) ?? 90
        if let fmt = try? c.decode(ResetFormat.self, forKey: .resetDisplay) {
            resetDisplay = fmt
        } else if (try? c.decode(Bool.self, forKey: .showAbsoluteReset)) == true {
            resetDisplay = .date     // migrate old "show as clock time" → date + time
        } else {
            resetDisplay = .relative
        }
        autoOpenSession = (try? c.decode(Bool.self, forKey: .autoOpenSession)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(menuBarMetric, forKey: .menuBarMetric)
        try c.encode(menuBarShowBar, forKey: .menuBarShowBar)
        try c.encode(menuBarShowPercent, forKey: .menuBarShowPercent)
        try c.encode(showSecondary, forKey: .showSecondary)
        try c.encode(refreshMinutes, forKey: .refreshMinutes)
        try c.encode(notifyAtHighUsage, forKey: .notifyAtHighUsage)
        try c.encode(notifyThreshold, forKey: .notifyThreshold)
        try c.encode(resetDisplay, forKey: .resetDisplay)
        try c.encode(autoOpenSession, forKey: .autoOpenSession)
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
