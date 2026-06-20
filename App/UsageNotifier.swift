import Foundation
import UserNotifications

/// Posts a local notification when a usage limit crosses the threshold, once per
/// crossing (re-arms after the limit drops back below it).
enum UsageNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func check(_ snapshot: UsageSnapshot, threshold: Double) {
        evaluate("session", "Session", snapshot.sessionPercent, threshold)
        evaluate("weekly", "Weekly", snapshot.weeklyPercent, threshold)
        if let opus = snapshot.opusPercent { evaluate("opus", "Opus", opus, threshold) }
        if let sonnet = snapshot.sonnetPercent { evaluate("sonnet", "Sonnet", sonnet, threshold) }
    }

    private static func evaluate(_ key: String, _ name: String.LocalizationValue,
                                 _ percent: Double, _ threshold: Double) {
        let flagKey = "notified.\(key)"
        let defaults = UserDefaults.standard
        if percent >= threshold {
            guard !defaults.bool(forKey: flagKey) else { return }
            defaults.set(true, forKey: flagKey)
            post(title: String(localized: "Usage limit almost reached"),
                 body: "\(String(localized: name)) · \(Int(percent.rounded()))%")
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
