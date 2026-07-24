import Foundation
import Security

// MARK: - Raw API response (tolerant decoding)

/// Top-level response of `GET /api/oauth/usage`.
/// The exact schema is undocumented; fields are decoded leniently and unknown
/// ones are ignored. Use the app's "Raw response" debug view to confirm names.
struct UsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    /// Every `seven_day_<model>` window the response carries (Opus, Sonnet,
    /// Fable, …). Decoded by prefix rather than by fixed keys, so a model
    /// Anthropic adds later shows up without an app update.
    let models: [ModelUsage]
    let spend: Spend?

    /// Prefix of the per-model weekly windows, e.g. `seven_day_fable`.
    private static let modelPrefix = "seven_day_"

    /// Any JSON key — lets us walk the object and pick up unknown model windows.
    private struct AnyKey: CodingKey {
        let stringValue: String
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.init(stringValue) }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        // `try?` so a null or unexpectedly shaped field degrades to nil rather
        // than failing the whole response.
        fiveHour = try? c.decode(UsageWindow.self, forKey: AnyKey("five_hour"))
        sevenDay = try? c.decode(UsageWindow.self, forKey: AnyKey("seven_day"))
        spend = try? c.decode(Spend.self, forKey: AnyKey("spend"))

        var found: [ModelUsage] = []
        for key in c.allKeys where key.stringValue.hasPrefix(Self.modelPrefix) {
            let name = String(key.stringValue.dropFirst(Self.modelPrefix.count))
            guard !name.isEmpty,
                  let window = try? c.decode(UsageWindow.self, forKey: key) else { continue }
            found.append(ModelUsage(key: name, percent: window.percentUsed,
                                    resetsAt: window.resetsAt))
        }
        models = ModelUsage.sorted(found)
    }

    /// Extra-usage / pay-as-you-go spend, in a currency (e.g. EUR).
    struct Spend: Decodable {
        let used: Money?
        let limit: Money?
        let enabled: Bool?

        struct Money: Decodable {
            let amountMinor: Double?
            let currency: String?
            let exponent: Int?

            enum CodingKeys: String, CodingKey {
                case amountMinor = "amount_minor"
                case currency, exponent
            }

            /// Value in major units (e.g. euros): amount_minor / 10^exponent.
            var value: Double? {
                guard let amountMinor else { return nil }
                return amountMinor / pow(10, Double(exponent ?? 2))
            }
        }
    }
}

/// One usage window (e.g. the 5-hour session or the 7-day weekly limit).
struct UsageWindow: Decodable {
    /// Percent used, normalized to 0...100.
    let percentUsed: Double
    /// When this window resets.
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `utilization` is a percentage 0...100 (e.g. 14.0 = 14%).
        let u = (try? c.decode(Double.self, forKey: .utilization)) ?? 0
        percentUsed = min(100, max(0, u))
        if let s = try? c.decode(String.self, forKey: .resetsAt) {
            resetsAt = UsageWindow.parseDate(s)
        } else {
            resetsAt = nil
        }
    }

    /// Parses ISO-8601 timestamps, tolerating the API's 6-digit (microsecond)
    /// fractional seconds, which Apple's parser otherwise rejects.
    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // Strip fractional seconds (e.g. ".913060") and retry.
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            return iso.date(from: s.replacingCharacters(in: r, with: ""))
        }
        return nil
    }
}

// MARK: - Per-model window

/// One weekly per-model window, keyed by the API's `seven_day_<key>` suffix
/// ("opus", "sonnet", "fable", …). Keeping the key generic means a new model
/// appears in the UI as soon as the endpoint reports it.
struct ModelUsage: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var percent: Double        // 0...100
    var resetsAt: Date?

    var id: String { key }

    /// Display order for the models we know about; anything else sorts after,
    /// alphabetically, so unknown keys still appear in a stable order.
    static let knownOrder = ["opus", "fable", "sonnet", "haiku"]

    /// "opus" → "Opus", "fable" → "Fable", "some_model" → "Some Model".
    var displayName: String {
        key.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func sorted(_ models: [ModelUsage]) -> [ModelUsage] {
        models.sorted { a, b in
            let ia = knownOrder.firstIndex(of: a.key) ?? knownOrder.count
            let ib = knownOrder.firstIndex(of: b.key) ?? knownOrder.count
            return ia == ib ? a.key < b.key : ia < ib
        }
    }
}

// MARK: - Snapshot shared with the widget

/// A compact, Codable snapshot persisted to the shared App Group so the widget
/// can render instantly and as a fallback when offline.
struct UsageSnapshot: Codable, Equatable {
    var sessionPercent: Double      // 5h window, 0...100
    var sessionResetsAt: Date?
    var weeklyPercent: Double       // 7d window, 0...100
    var weeklyResetsAt: Date?
    /// Per-model weekly windows (Opus, Sonnet, Fable, …), in display order.
    var models: [ModelUsage] = []
    var spendUsed: Double?          // extra-usage spend, major units
    var spendLimit: Double?
    var spendCurrency: String?
    var fetchedAt: Date

    static func from(_ r: UsageResponse, fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            sessionPercent: r.fiveHour?.percentUsed ?? 0,
            sessionResetsAt: r.fiveHour?.resetsAt,
            weeklyPercent: r.sevenDay?.percentUsed ?? 0,
            weeklyResetsAt: r.sevenDay?.resetsAt,
            models: r.models,
            spendUsed: r.spend?.used?.value,
            spendLimit: r.spend?.limit?.value,
            spendCurrency: r.spend?.limit?.currency ?? r.spend?.used?.currency,
            fetchedAt: fetchedAt
        )
    }

    func model(_ key: String) -> ModelUsage? { models.first { $0.key == key } }

    /// The model rows to show, honouring the per-model toggles in Settings.
    func visibleModels(_ settings: Settings) -> [ModelUsage] {
        settings.showSecondary ? models.filter { settings.showsModel($0.key) } : []
    }

    /// Formatted spend, e.g. "€0.00 / €10.00", when a limit is present.
    var spendText: String? {
        guard let limit = spendLimit, limit > 0 else { return nil }
        let symbol = Self.currencySymbol(spendCurrency)
        let used = spendUsed ?? 0
        return String(format: "%@%.2f / %@%.2f", symbol, used, symbol, limit)
    }

    private static func currencySymbol(_ code: String?) -> String {
        switch code?.uppercased() {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        default: return code.map { "\($0) " } ?? ""
        }
    }

    /// Highest of all known percentages — used for the high-usage notification.
    var maxPercent: Double {
        ([sessionPercent, weeklyPercent] + models.map(\.percent)).max() ?? 0
    }

    static let placeholder = UsageSnapshot(
        sessionPercent: 8, sessionResetsAt: Date().addingTimeInterval(2.5 * 3600),
        weeklyPercent: 12, weeklyResetsAt: Date().addingTimeInterval(7 * 3600 + 600),
        fetchedAt: Date()
    )

    /// Distinct values for settings previews.
    static let sample = UsageSnapshot(
        sessionPercent: 32, sessionResetsAt: Date().addingTimeInterval(2 * 3600),
        weeklyPercent: 68, weeklyResetsAt: Date().addingTimeInterval(5 * 3600),
        models: [
            ModelUsage(key: "opus", percent: 45, resetsAt: Date().addingTimeInterval(5 * 3600)),
            ModelUsage(key: "fable", percent: 27, resetsAt: Date().addingTimeInterval(5 * 3600)),
            ModelUsage(key: "sonnet", percent: 12, resetsAt: Date().addingTimeInterval(5 * 3600)),
        ],
        spendUsed: 0, spendLimit: 10, spendCurrency: "EUR", fetchedAt: Date()
    )
}

// Codable lives in an extension so the memberwise initializer stays available.
extension UsageSnapshot {
    enum CodingKeys: String, CodingKey {
        case sessionPercent, sessionResetsAt, weeklyPercent, weeklyResetsAt
        case models, spendUsed, spendLimit, spendCurrency, fetchedAt
        case opusPercent, opusResetsAt      // legacy — folded into `models`
        case sonnetPercent, sonnetResetsAt  // legacy
    }

    /// Lenient, so a snapshot cached by an older build still renders instantly
    /// on first launch after an update (before the next fetch replaces it).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionPercent = (try? c.decode(Double.self, forKey: .sessionPercent)) ?? 0
        sessionResetsAt = try? c.decode(Date.self, forKey: .sessionResetsAt)
        weeklyPercent = (try? c.decode(Double.self, forKey: .weeklyPercent)) ?? 0
        weeklyResetsAt = try? c.decode(Date.self, forKey: .weeklyResetsAt)
        if let stored = try? c.decode([ModelUsage].self, forKey: .models) {
            models = ModelUsage.sorted(stored)
        } else {
            var legacy: [ModelUsage] = []
            if let p = try? c.decode(Double.self, forKey: .opusPercent) {
                legacy.append(ModelUsage(key: "opus", percent: p,
                                         resetsAt: try? c.decode(Date.self, forKey: .opusResetsAt)))
            }
            if let p = try? c.decode(Double.self, forKey: .sonnetPercent) {
                legacy.append(ModelUsage(key: "sonnet", percent: p,
                                         resetsAt: try? c.decode(Date.self, forKey: .sonnetResetsAt)))
            }
            models = ModelUsage.sorted(legacy)
        }
        spendUsed = try? c.decode(Double.self, forKey: .spendUsed)
        spendLimit = try? c.decode(Double.self, forKey: .spendLimit)
        spendCurrency = try? c.decode(String.self, forKey: .spendCurrency)
        fetchedAt = (try? c.decode(Date.self, forKey: .fetchedAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionPercent, forKey: .sessionPercent)
        try c.encodeIfPresent(sessionResetsAt, forKey: .sessionResetsAt)
        try c.encode(weeklyPercent, forKey: .weeklyPercent)
        try c.encodeIfPresent(weeklyResetsAt, forKey: .weeklyResetsAt)
        try c.encode(models, forKey: .models)
        try c.encodeIfPresent(spendUsed, forKey: .spendUsed)
        try c.encodeIfPresent(spendLimit, forKey: .spendLimit)
        try c.encodeIfPresent(spendCurrency, forKey: .spendCurrency)
        try c.encode(fetchedAt, forKey: .fetchedAt)
    }
}

// MARK: - Snapshot persistence (shared Keychain)

/// Stored in the same shared Keychain group as the tokens so the widget can read
/// the last fetched usage instantly (and as an offline fallback). No App Group
/// capability required.
enum SnapshotStore {
    private static let account = "snapshot"

    static func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        Keychain.save(data, query: baseQuery())
    }

    static func load() -> UsageSnapshot? {
        guard let data = Keychain.load(baseQuery()) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.keychainSnapshotService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
