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

/// Today's slice of the weekly limit against a fixed daily allowance, so one
/// long day can't burn through the whole week. The endpoint only reports the
/// weekly total, so the day's usage is diffed out of the history.
struct DailyBudget: Equatable, Sendable {
    /// Weekly percentage points used since local midnight.
    var used: Double
    /// Weekly percentage points allowed per day.
    var budget: Double
    /// What the weekly limit itself still has room for.
    var weeklyLeft: Double

    /// Share of today's budget used: 100 = budget reached, above = over it.
    var percent: Double { budget > 0 ? used / budget * 100 : 0 }

    /// Points left today — never more than the weekly limit still allows.
    var remaining: Double { min(max(0, budget - used), weeklyLeft) }

    /// `remaining` as a share of today's budget (100 = untouched).
    var remainingPercent: Double { budget > 0 ? remaining / budget * 100 : 0 }

    /// `nil` while no daily budget is set.
    static func today(history: [HistoryPoint], snapshot: UsageSnapshot, mode: DailyBudgetMode,
                      now: Date = Date(), calendar: Calendar = .current) -> DailyBudget? {
        var series: [UsageForecast.Sample] = history.map { ($0.date, $0.weekly) }
        if series.last?.date ?? .distantPast < snapshot.fetchedAt {
            series.append((snapshot.fetchedAt, snapshot.weeklyPercent))
        }
        let used = usedToday(series, now: now, calendar: calendar)
        let budget: Double
        switch mode {
        case .off:
            return nil
        case .even(let days):
            budget = 100 / Double(max(1, days))
        case .flexible:
            budget = flexibleBudget(weekly: snapshot.weeklyPercent, usedToday: used,
                                    resetsAt: snapshot.weeklyResetsAt, now: now, calendar: calendar)
        }
        return DailyBudget(used: used, budget: budget,
                           weeklyLeft: max(0, 100 - snapshot.weeklyPercent))
    }

    /// What was left of the week this morning, spread over the days until the
    /// reset (today included, a partial last day counted as such — so on the
    /// reset day itself everything left is today's). Fixed for the whole day:
    /// it only moves when a new day starts.
    static func flexibleBudget(weekly: Double, usedToday: Double, resetsAt: Date?,
                               now: Date, calendar: Calendar = .current) -> Double {
        let midnight = calendar.startOfDay(for: now)
        // After a reset today, `weekly - usedToday` goes negative: the fresh
        // window is what's left.
        let leftThisMorning = 100 - max(0, weekly - usedToday)
        let days: Double
        if let resetsAt, resetsAt > now {
            days = max(1, resetsAt.timeIntervalSince(midnight) / 86400)
        } else {
            days = 7
        }
        return leftThisMorning / days
    }

    /// Midnight at the end of `now`'s day, when the budget starts over.
    static func endOfDay(_ now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    /// Weekly points used since the start of `now`'s day. The level at midnight
    /// is interpolated between the samples around it — the Mac is often asleep
    /// then, and a reading from days ago must not count wholly as today. A drop
    /// of more than 1pp is a weekly reset: the new window counts from zero.
    static func usedToday(_ series: [UsageForecast.Sample], now: Date,
                          calendar: Calendar = .current) -> Double {
        let midnight = calendar.startOfDay(for: now)
        let today = series.filter { $0.date >= midnight && $0.date <= now }
        guard let first = today.first else { return 0 }

        var level = first.percent
        if let before = series.last(where: { $0.date < midnight }) {
            if first.percent < before.percent - 1 {
                level = 0      // reset overnight: all of today's reading is new
            } else {
                let span = first.date.timeIntervalSince(before.date)
                let t = span > 0 ? midnight.timeIntervalSince(before.date) / span : 1
                level = before.percent + (first.percent - before.percent) * t
            }
        }

        var used = 0.0
        for sample in today {
            if sample.percent < level - 1 {
                used += sample.percent
                level = sample.percent
            } else {
                used += max(0, sample.percent - level)
                level = max(level, sample.percent)
            }
        }
        return used
    }

    /// Distinct values for settings previews.
    static let sample = DailyBudget(used: 9, budget: 100 / 7, weeklyLeft: 32)
}

/// A rolling history of usage points, persisted in the shared Keychain group.
enum HistoryStore {
    private static let account = "history"
    /// Two days, so the daily budget still finds the last reading before
    /// midnight on a day of frequent refreshes.
    static let retention: TimeInterval = 48 * 3600
    static let maxPoints = 400   // hard cap — 48h at a ~7-minute average

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
        points.removeAll { snapshot.fetchedAt.timeIntervalSince($0.date) > retention }
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
