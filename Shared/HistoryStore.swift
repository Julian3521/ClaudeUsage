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
    /// Weekly percentage points allowed today.
    var budget: Double
    /// What the weekly limit itself still has room for.
    var weeklyLeft: Double
    /// Points earlier days went over and today pays for — already taken off
    /// `budget`.
    var carried: Double = 0

    /// Share of today's budget used: 100 = budget reached, above = over it. A
    /// day whose whole budget went to earlier overruns starts used up.
    var percent: Double { budget > 0 ? used / budget * 100 : 100 }

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
        var carried = 0.0
        switch mode {
        case .off:
            return nil
        case .even(let days):
            let perDay = 100 / Double(max(1, days))
            carried = carriedOver(series, perDay: perDay, resetsAt: snapshot.weeklyResetsAt,
                                  now: now, calendar: calendar)
            budget = max(0, perDay - carried)
        case .flexible:
            budget = flexibleBudget(weekly: snapshot.weeklyPercent, usedToday: used,
                                    resetsAt: snapshot.weeklyResetsAt, now: now, calendar: calendar)
        }
        return DailyBudget(used: used, budget: budget,
                           weeklyLeft: max(0, 100 - snapshot.weeklyPercent), carried: carried)
    }

    /// What earlier days of this week went over a fixed allowance and today
    /// still owes. An overrun comes off the next day, and whatever that day
    /// can't absorb off the one after; a day under its allowance pays the debt
    /// back. Savings aren't carried — a day never gets more than `perDay`. A
    /// weekly reset clears the debt.
    static func carriedOver(_ series: [UsageForecast.Sample], perDay: Double, resetsAt: Date?,
                            now: Date, calendar: Calendar = .current) -> Double {
        guard let resetsAt, resetsAt > now else { return 0 }
        let midnight = calendar.startOfDay(for: now)
        var dayStart = resetsAt.addingTimeInterval(-7 * 86400)   // when this week began
        var owed = 0.0
        while dayStart < midnight {
            let dayEnd = min(endOfDay(dayStart, calendar: calendar), midnight)
            owed = max(0, owed + used(series, from: dayStart, to: dayEnd) - perDay)
            dayStart = dayEnd
        }
        return owed
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

    /// Weekly points used since the start of `now`'s day.
    static func usedToday(_ series: [UsageForecast.Sample], now: Date,
                          calendar: Calendar = .current) -> Double {
        used(series, from: calendar.startOfDay(for: now), to: now)
    }

    /// Weekly points used between `start` and `end`. The levels at both ends
    /// are interpolated between the samples around them — the Mac is often
    /// asleep at midnight, and a reading from days ago must not count wholly
    /// as one day's. Without a sample before `start`, counting begins at the
    /// first one inside. A drop of more than 1pp is a weekly reset: the new
    /// window counts from zero.
    static func used(_ series: [UsageForecast.Sample], from start: Date, to end: Date) -> Double {
        let inside = series.filter { $0.date >= start && $0.date <= end }
        var levels = inside.map(\.percent)

        var level: Double
        if let before = series.last(where: { $0.date < start }),
           let after = series.first(where: { $0.date >= start }) {
            // Reset in between: all of the new reading falls in the range.
            level = after.percent < before.percent - 1 ? 0 : interpolate(before, after, at: start)
        } else if let first = inside.first {
            level = first.percent
        } else {
            return 0
        }
        if let last = series.last(where: { $0.date <= end }),
           let after = series.first(where: { $0.date > end }),
           after.percent >= last.percent - 1 {
            levels.append(interpolate(last, after, at: end))
        }

        var used = 0.0
        for percent in levels {
            if percent < level - 1 {
                used += percent
                level = percent
            } else {
                used += max(0, percent - level)
                level = max(level, percent)
            }
        }
        return used
    }

    private static func interpolate(_ a: UsageForecast.Sample, _ b: UsageForecast.Sample,
                                    at date: Date) -> Double {
        let span = b.date.timeIntervalSince(a.date)
        let t = span > 0 ? date.timeIntervalSince(a.date) / span : 1
        return a.percent + (b.percent - a.percent) * t
    }

    /// Distinct values for settings previews.
    static let sample = DailyBudget(used: 9, budget: 100 / 7, weeklyLeft: 32)
}

/// A rolling history of usage points, persisted in the shared Keychain group.
enum HistoryStore {
    private static let account = "history"
    /// The week plus a day, so a fixed daily budget can trace overruns back to
    /// the week's first morning.
    static let retention: TimeInterval = 8 * 86400
    /// Newer points are all kept (charts, forecasts); older ones are thinned
    /// to one an hour — enough to find the level at each midnight.
    static let fullDetail: TimeInterval = 48 * 3600
    static let maxPoints = 600   // hard cap — 48h at ~7 minutes plus six days hourly

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
        save(trimmed(points, now: snapshot.fetchedAt))
    }

    /// Drops points past `retention`, thins those past `fullDetail` to one an
    /// hour, and caps the rest.
    static func trimmed(_ points: [HistoryPoint], now: Date) -> [HistoryPoint] {
        var kept: [HistoryPoint] = []
        for point in points where now.timeIntervalSince(point.date) <= retention {
            if now.timeIntervalSince(point.date) > fullDetail, let last = kept.last,
               point.date.timeIntervalSince(last.date) < 3600 { continue }
            kept.append(point)
        }
        return Array(kept.suffix(maxPoints))
    }

    /// The part of the history the charts show.
    static func recent(_ points: [HistoryPoint], now: Date = Date()) -> [HistoryPoint] {
        points.filter { now.timeIntervalSince($0.date) <= fullDetail }
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
