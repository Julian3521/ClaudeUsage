import AppIntents
import Foundation
import Security

/// Which usage limit(s) drive the menu-bar readout.
enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case highest, session, weekly, both, today

    var label: String {
        switch self {
        case .highest: return "Highest of both"
        case .session: return "Session (5h)"
        case .weekly: return "Weekly (7d)"
        case .both: return "Session + weekly"
        case .today: return "Today (daily budget)"
        }
    }

    /// Only meaningful on plans with a 5-hour window.
    var needsSession: Bool { self == .session || self == .both }

    /// The percentage value(s) to display for this metric (1 or 2). `.today`
    /// shows the share of today's budget used, and the weekly value while no
    /// daily budget is set; the session ones fall back to weekly on plans
    /// without a 5-hour window.
    func values(_ s: UsageSnapshot, today: DailyBudget? = nil) -> [Double] {
        switch self {
        case .session: return [s.hasSession ? s.sessionPercent : s.weeklyPercent]
        case .weekly: return [s.weeklyPercent]
        case .highest: return [max(s.sessionPercent, s.weeklyPercent)]
        case .both: return s.hasSession ? [s.sessionPercent, s.weeklyPercent] : [s.weeklyPercent]
        case .today: return [today?.percent ?? s.weeklyPercent]
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

/// How the menu-bar readout draws each value.
enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case bar          // horizontal progress bar
    case ring         // circular progress ring (percentage can sit inside it)
    case combinedRing // one ring with session (blue) + weekly (orange) overlaid
    case none         // text only

    var label: String {
        switch self {
        case .bar: return "Bar"
        case .ring: return "Ring"
        case .combinedRing: return "Combined ring"
        case .none: return "Text only"
        }
    }
}

/// How the weekly limit is split into a daily allowance.
enum DailyBudgetMode: Hashable, Codable, Sendable {
    case off
    /// The weekly limit ÷ `days`, the same every day.
    case even(days: Int)
    /// What's left of the week ÷ the days until it resets, so a quiet day
    /// leaves more for the ones after it.
    case flexible
}

struct Settings: Codable, Equatable, Sendable {
    var menuBarMetric: MenuBarMetric = .highest
    var menuBarStyle: MenuBarStyle = .bar
    var menuBarShowPercent = true
    var showSecondary = true          // master switch for the per-model + spend rows
    /// Per-model rows switched off individually (keys as reported by the API,
    /// e.g. "opus", "fable"). Storing what's *hidden* means a model Anthropic
    /// adds later shows up by default instead of silently staying off.
    var hiddenModels: Set<String> = []
    var showSpend = true              // extra-usage (€) row
    var refreshMinutes = 30
    var notifyAtHighUsage = false
    var notifyThreshold = 90          // alert when any limit reaches this %
    var resetDisplay: ResetFormat = .relative   // countdown / weekday / date
    var autoOpenSession = false       // auto-ping ~1 min after each 5h reset
    var dailyBudget: DailyBudgetMode = .off
    var notifyDailyBudget = true      // alert at 80% and when the day's budget is used up

    /// Allowed refresh intervals (minutes). The usage endpoint rate-limits hard,
    /// so 15 min is the lowest interval that reliably avoids 429s.
    static let refreshOptions = [15, 30, 60, 120]
    /// Selectable alert thresholds (%).
    static let thresholdOptions = [70, 75, 80, 85, 90, 95]
    /// Selectable even splits, as the days the weekly limit is spread over:
    /// 7 → 14% a day, 5 → 20% for a five-day week, …
    static let dailyBudgetDays = [10, 7, 6, 5, 4]

    init() {}

    /// Whether the weekly row for `key` ("opus", "fable", …) is shown.
    func showsModel(_ key: String) -> Bool { showSecondary && !hiddenModels.contains(key) }

    enum CodingKeys: String, CodingKey {
        case menuBarMetric, menuBarStyle, menuBarShowPercent, showSecondary
        case hiddenModels, showSpend
        case refreshMinutes, notifyAtHighUsage, notifyThreshold
        case resetDisplay, autoOpenSession
        case dailyBudget, notifyDailyBudget
        case menuBarShowBar      // legacy (Bool) — migrated to menuBarStyle
        case showAbsoluteReset   // legacy (Bool) — migrated to resetDisplay
    }

    // Lenient decoding so older stored settings keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarMetric = (try? c.decode(MenuBarMetric.self, forKey: .menuBarMetric)) ?? .highest
        if let style = try? c.decode(MenuBarStyle.self, forKey: .menuBarStyle) {
            menuBarStyle = style
        } else {   // migrate the old "show bar" toggle
            menuBarStyle = ((try? c.decode(Bool.self, forKey: .menuBarShowBar)) ?? true) ? .bar : .none
        }
        menuBarShowPercent = (try? c.decode(Bool.self, forKey: .menuBarShowPercent)) ?? true
        showSecondary = (try? c.decode(Bool.self, forKey: .showSecondary)) ?? true
        hiddenModels = (try? c.decode(Set<String>.self, forKey: .hiddenModels)) ?? []
        showSpend = (try? c.decode(Bool.self, forKey: .showSpend)) ?? true
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
        switch try? c.decode(DailyBudgetMode.self, forKey: .dailyBudget) {
        case .even(let days) where Settings.dailyBudgetDays.contains(days): dailyBudget = .even(days: days)
        case .flexible: dailyBudget = .flexible
        default: dailyBudget = .off
        }
        notifyDailyBudget = (try? c.decode(Bool.self, forKey: .notifyDailyBudget)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(menuBarMetric, forKey: .menuBarMetric)
        try c.encode(menuBarStyle, forKey: .menuBarStyle)
        try c.encode(menuBarShowPercent, forKey: .menuBarShowPercent)
        try c.encode(showSecondary, forKey: .showSecondary)
        try c.encode(hiddenModels, forKey: .hiddenModels)
        try c.encode(showSpend, forKey: .showSpend)
        try c.encode(refreshMinutes, forKey: .refreshMinutes)
        try c.encode(notifyAtHighUsage, forKey: .notifyAtHighUsage)
        try c.encode(notifyThreshold, forKey: .notifyThreshold)
        try c.encode(resetDisplay, forKey: .resetDisplay)
        try c.encode(autoOpenSession, forKey: .autoOpenSession)
        try c.encode(dailyBudget, forKey: .dailyBudget)
        try c.encode(notifyDailyBudget, forKey: .notifyDailyBudget)
    }
}

/// Persisted in the shared Keychain group so the app and the widget agree.
enum SettingsStore {
    private static let account = "settings"

    static func load() -> Settings {
        guard let data = Keychain.load(baseQuery()),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    static func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        Keychain.save(data, query: baseQuery())
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
