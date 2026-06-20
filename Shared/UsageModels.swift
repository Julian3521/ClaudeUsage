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
        case remaining
        case used
        case limit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // utilization may be a fraction (0...1) or a percent (0...100).
        if let u = try? c.decode(Double.self, forKey: .utilization) {
            percentUsed = u <= 1.0 ? u * 100.0 : u
        } else if let used = try? c.decode(Double.self, forKey: .used),
                  let limit = try? c.decode(Double.self, forKey: .limit), limit > 0 {
            percentUsed = min(100.0, used / limit * 100.0)
        } else if let remaining = try? c.decode(Double.self, forKey: .remaining),
                  remaining <= 1.0 {
            percentUsed = (1.0 - remaining) * 100.0
        } else {
            percentUsed = 0
        }

        resetsAt = UsageWindow.decodeDate(from: c, key: .resetsAt)
    }

    private static func decodeDate(from c: KeyedDecodingContainer<CodingKeys>,
                                   key: CodingKeys) -> Date? {
        if let s = try? c.decode(String.self, forKey: key) {
            return ISO8601DateFormatter.flexible.date(from: s)
                ?? ISO8601DateFormatter().date(from: s)
        }
        if let t = try? c.decode(Double.self, forKey: key) {
            // Heuristic: seconds vs milliseconds since epoch.
            return Date(timeIntervalSince1970: t > 4_000_000_000 ? t / 1000 : t)
        }
        return nil
    }
}

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
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
        ]
    }
}
