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

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
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
    var fetchedAt: Date

    static func from(_ r: UsageResponse, fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            sessionPercent: r.fiveHour?.percentUsed ?? 0,
            sessionResetsAt: r.fiveHour?.resetsAt,
            weeklyPercent: r.sevenDay?.percentUsed ?? 0,
            weeklyResetsAt: r.sevenDay?.resetsAt,
            opusPercent: r.sevenDayOpus?.percentUsed,
            opusResetsAt: r.sevenDayOpus?.resetsAt,
            fetchedAt: fetchedAt
        )
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
        opusPercent: 45, opusResetsAt: Date().addingTimeInterval(5 * 3600), fetchedAt: Date()
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
