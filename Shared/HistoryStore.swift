import Foundation
import Security

/// One recorded data point for the usage sparkline.
struct HistoryPoint: Codable, Equatable, Sendable, Identifiable {
    var date: Date
    var session: Double
    var weekly: Double
    var id: Date { date }
}

/// A rolling history of usage points, persisted in the shared Keychain group.
enum HistoryStore {
    private static let account = "history"
    static let maxPoints = 96   // ~32h at a 20-minute interval

    static func load() -> [HistoryPoint] {
        guard let data = Keychain.load(baseQuery()),
              let points = try? JSONDecoder().decode([HistoryPoint].self, from: data)
        else { return [] }
        return points
    }

    static func append(_ snapshot: UsageSnapshot) {
        var points = load()
        points.append(HistoryPoint(date: snapshot.fetchedAt,
                                   session: snapshot.sessionPercent,
                                   weekly: snapshot.weeklyPercent))
        if points.count > maxPoints { points.removeFirst(points.count - maxPoints) }
        save(points)
    }

    private static func save(_ points: [HistoryPoint]) {
        guard let data = try? JSONEncoder().encode(points) else { return }
        Keychain.save(data, query: baseQuery())
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.keychainHistoryService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
