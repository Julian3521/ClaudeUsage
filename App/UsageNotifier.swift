import Foundation
import UserNotifications

/// Posts a local notification when a usage limit crosses the threshold, once per
/// crossing (re-arms after the limit drops back below it).
enum UsageNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func check(_ snapshot: UsageSnapshot, threshold: Double) {
        evaluate("session", String(localized: "Session"), snapshot.sessionPercent, threshold)
        evaluate("weekly", String(localized: "Weekly"), snapshot.weeklyPercent, threshold)
        for model in snapshot.models {
            evaluate(model.key, model.displayName, model.percent, threshold)
        }
    }

    /// Once per day, when today's usage reaches the daily budget.
    static func checkDaily(_ daily: DailyBudget, now: Date = Date()) {
        guard daily.used >= daily.budget else { return }
        let flagKey = "notified.dailyBudget"
        let day = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: flagKey) != day else { return }
        defaults.set(day, forKey: flagKey)
        let used = "\(Int(daily.used.rounded()))%"
        let budget = "\(Int(daily.budget.rounded()))%"
        post(title: String(localized: "Daily budget used up"),
             body: String(localized: "Used today: \(used) of the weekly limit (budget \(budget))"))
    }

    private static func evaluate(_ key: String, _ name: String,
                                 _ percent: Double, _ threshold: Double) {
        let flagKey = "notified.\(key)"
        let defaults = UserDefaults.standard
        if percent >= threshold {
            guard !defaults.bool(forKey: flagKey) else { return }
            defaults.set(true, forKey: flagKey)
            post(title: String(localized: "Usage limit almost reached"),
                 body: "\(name) · \(Int(percent.rounded()))%")
        } else {
            defaults.set(false, forKey: flagKey)
        }
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
