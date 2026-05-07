import Foundation
import UserNotifications

// ── Meal reminders ────────────────────────────────────────────────────────────
// Centralised definition of Stride's 3 daily meal reminders, used by both the
// onboarding flow (one-tap enable-all) and the Settings → Notifications screen
// (per-reminder toggles + custom times). Times are local to the device.

enum MealReminders {

    struct Definition: Identifiable, Hashable {
        let id: String           // notification identifier + UserDefaults key prefix
        let title: String        // settings UI label
        let icon: String         // SF Symbol
        let defaultHour: Int     // local-time hour of the reminder
        let notifTitle: String   // user-facing notification title
        let notifBody: String    // user-facing notification body
    }

    static let all: [Definition] = [
        Definition(
            id: "meal_breakfast",
            title: "Breakfast reminder",
            icon: "sunrise.fill",
            defaultHour: 8,
            notifTitle: "Time for breakfast",
            notifBody: "Log your first meal and start the day on track."
        ),
        Definition(
            id: "meal_lunch",
            title: "Lunch reminder",
            icon: "sun.max.fill",
            defaultHour: 12,
            notifTitle: "Lunch time",
            notifBody: "Don't skip — log your lunch to stay on plan."
        ),
        Definition(
            id: "meal_dinner",
            title: "Dinner reminder",
            icon: "moon.stars.fill",
            defaultHour: 19,
            notifTitle: "Dinner check-in",
            notifBody: "Log your dinner and review today's progress."
        ),
    ]

    private static let center = UNUserNotificationCenter.current()

    /// Request permission and, on grant, schedule all three reminders at their
    /// default times (8am, 12pm, 7pm local). Used by the onboarding "enable
    /// notifications" CTA. Returns the resulting authorization status.
    @MainActor
    static func requestAndEnableAll() async -> UNAuthorizationStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                for def in all {
                    let time = Calendar.current.date(from: DateComponents(hour: def.defaultHour, minute: 0))
                              ?? Date()
                    schedule(def, at: time)
                }
            }
            return granted ? .authorized : .denied
        } catch {
            print("[MealReminders] requestAuthorization: \(error)")
            return .denied
        }
    }

    /// Schedule (or re-schedule) a single reminder at the given time.
    static func schedule(_ def: Definition, at date: Date) {
        UserDefaults.standard.set(true, forKey: enabledKey(def))
        UserDefaults.standard.set(date, forKey: timeKey(def))

        let content = UNMutableNotificationContent()
        content.title = def.notifTitle
        content.body  = def.notifBody
        content.sound = .default

        var comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: def.id, content: content, trigger: trigger)
        center.add(req)
    }

    /// Remove a single reminder.
    static func cancel(_ def: Definition) {
        UserDefaults.standard.set(false, forKey: enabledKey(def))
        center.removePendingNotificationRequests(withIdentifiers: [def.id])
    }

    static func isEnabled(_ def: Definition) -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey(def))
    }

    static func savedTime(_ def: Definition) -> Date {
        if let t = UserDefaults.standard.object(forKey: timeKey(def)) as? Date { return t }
        return Calendar.current.date(from: DateComponents(hour: def.defaultHour, minute: 0)) ?? Date()
    }

    private static func enabledKey(_ def: Definition) -> String { "notif_\(def.id)_on" }
    private static func timeKey(_ def: Definition) -> String    { "notif_\(def.id)_time" }
}
