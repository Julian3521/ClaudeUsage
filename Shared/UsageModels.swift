import Foundation
import Security

// MARK: - Raw API response (tolerant decoding)

/// Top-level response of `GET /api/oauth/usage`.
/// The exact schema is undocumented; fields are decoded leniently and unknown
/// ones are ignored. Use the app's "Raw response" debug view to confirm names.
struct UsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let spend: Spend?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case spend
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

// MARK: - Snapshot shared with the widget

/// A compact, Codable snapshot persisted to the shared App Group so the widget
/// can render instantly and as a fallback when offline.
struct UsageSnapshot: Codable, Equatable {
    var sessionPercent: Double      // 5h window, 0...100
    var sessionResetsAt: Date?
    var weeklyPercent: Double       // 7d window, 0...100
    var weeklyResetsAt: Date?
    var opusPercent: Double?        // 7d Opus window, optional
    var opusResetsAt: Date?
    var sonnetPercent: Double?      // 7d Sonnet window, optional
    var sonnetResetsAt: Date?
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
            opusPercent: r.sevenDayOpus?.percentUsed,
            opusResetsAt: r.sevenDayOpus?.resetsAt,
            sonnetPercent: r.sevenDaySonnet?.percentUsed,
            sonnetResetsAt: r.sevenDaySonnet?.resetsAt,
            spendUsed: r.spend?.used?.value,
            spendLimit: r.spend?.limit?.value,
            spendCurrency: r.spend?.limit?.currency ?? r.spend?.used?.currency,
            fetchedAt: fetchedAt
        )
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
        [sessionPercent, weeklyPercent, opusPercent ?? 0, sonnetPercent ?? 0].max() ?? 0
    }

    static let placeholder = UsageSnapshot(
        sessionPercent: 8, sessionResetsAt: Date().addingTimeInterval(2.5 * 3600),
        weeklyPercent: 12, weeklyResetsAt: Date().addingTimeInterval(7 * 3600 + 600),
        opusPercent: nil, opusResetsAt: nil, fetchedAt: Date()
    )

    /// Distinct values for settings previews.
    static let sample = UsageSnapshot(
        sessionPercent: 32, sessionResetsAt: Date().addingTimeInterval(2 * 3600),
        weeklyPercent: 68, weeklyResetsAt: Date().addingTimeInterval(5 * 3600),
        opusPercent: 45, opusResetsAt: Date().addingTimeInterval(5 * 3600),
        sonnetPercent: 12, sonnetResetsAt: Date().addingTimeInterval(5 * 3600),
        spendUsed: 0, spendLimit: 10, spendCurrency: "EUR", fetchedAt: Date()
    )
}

// MARK: - Snapshot persistence (shared Keychain)

/// Stored in the same shared Keychain group as the tokens so the widget can read
/// the last fetched usage instantly (and as an offline fallback). No App Group
/// capability required.
enum SnapshotStore {
    private static let account = "snapshot"

    static func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let base = baseQuery()
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> UsageSnapshot? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
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
