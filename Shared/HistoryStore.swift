import Foundation
import Security

/// One recorded data point for the usage sparkline.
struct HistoryPoint: Codable, Equatable, Sendable, Identifiable {
    var date: Date
    var session: Double
    var weekly: Double
    /// Per-model utilization at that moment, keyed like `ModelUsage.key`, so the
    /// forecast can tell which model's limit binds first.
    var models: [String: Double] = [:]
    var id: Date { date }
}

// Codable in an extension keeps the memberwise init; decoding is lenient so
// points recorded before `models` existed still load.
extension HistoryPoint {
    enum CodingKeys: String, CodingKey { case date, session, weekly, models }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        session = (try? c.decode(Double.self, forKey: .session)) ?? 0
        weekly = (try? c.decode(Double.self, forKey: .weekly)) ?? 0
        models = (try? c.decode([String: Double].self, forKey: .models)) ?? [:]
    }
}

/// Projects when a usage window will hit 100%, from the trend since it last
/// reset. Deliberately conservative: no projection from thin data, from a flat
/// or falling trend, or across a reset — a wrong "you're fine" is worse than no
/// answer at all.
enum UsageForecast {
    /// One sample: when it was taken and the utilization at that point.
    typealias Sample = (date: Date, percent: Double)

    /// Samples must span at least this much time before a slope means anything.
    static let minimumSpan: TimeInterval = 20 * 60

    /// Convenience over the stored history: builds the series for one metric and
    /// tops it up with the live snapshot value.
    static func runsOut(history: [HistoryPoint], current: Double, currentAt: Date,
                        value: (HistoryPoint) -> Double?) -> Date? {
        var series: [Sample] = history.compactMap { point in
            value(point).map { (point.date, $0) }
        }
        if series.last?.date ?? .distantPast < currentAt {
            series.append((currentAt, current))
        }
        return runsOut(series)
    }

    static func runsOut(_ series: [Sample]) -> Date? {
        let window = currentWindow(series)
        guard window.count >= 2,
              let first = window.first, let last = window.last,
              last.percent < 100,
              last.date.timeIntervalSince(first.date) >= minimumSpan,
              let perSecond = slope(window), perSecond > 0
        else { return nil }
        let seconds = (100 - last.percent) / perSecond
        guard seconds.isFinite, seconds > 0 else { return nil }
        return last.date.addingTimeInterval(seconds)
    }

    /// Everything after the last reset — utilization only grows within a window,
    /// so a drop marks a new one. 1pp of slack absorbs rounding noise.
    private static func currentWindow(_ series: [Sample]) -> [Sample] {
        var start = series.startIndex
        for i in series.indices.dropFirst() where series[i].percent < series[i - 1].percent - 1 {
            start = i
        }
        return Array(series[start...])
    }

    /// Least-squares slope in percentage points per second.
    private static func slope(_ series: [Sample]) -> Double? {
        let base = series[0].date.timeIntervalSinceReferenceDate
        let xs = series.map { $0.date.timeIntervalSinceReferenceDate - base }
        let ys = series.map(\.percent)
        let n = Double(series.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var numerator = 0.0, denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
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
        points.append(HistoryPoint(
            date: snapshot.fetchedAt,
            session: snapshot.sessionPercent,
            weekly: snapshot.weeklyPercent,
            models: Dictionary(snapshot.models.map { ($0.key, $0.percent) },
                               uniquingKeysWith: { a, _ in a })))
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
