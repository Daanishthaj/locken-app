import Foundation
@preconcurrency import UserNotifications

/// Habit reminders as local notifications. Instead of one repeating alarm, each habit gets one-off
/// notifications for its next due days (up to 7), rebuilt whenever habits change. So a habit that's
/// already done today doesn't nudge, and turning Reminders off in Settings clears them all.
/// macOS only asks for notification permission the first time someone sets a reminder.
@MainActor
enum HabitReminders {
    private static let prefix = "habit-"
    private static let delegate = ForegroundPresenter()

    /// Shows habit reminders as banners even while Locken is the front app.
    static func install() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Asks for permission if it hasn't been asked yet. Returns whether notifications are allowed.
    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    static func reschedule(for store: HabitStore) {
        let center = UNUserNotificationCenter.current()
        let features = store.features
        let habits = store.activeHabits.filter(\.hasReminder)

        // Work out the next reminders now (on the main actor), then swap them in.
        var requests: [UNNotificationRequest] = []
        if features.reminders {
            let calendar = Calendar.current
            let now = Date()
            for habit in habits {
                guard let hour = habit.reminderHour, let minute = habit.reminderMinute else { continue }
                var scheduled = 0
                for offset in 0..<14 where scheduled < 7 {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                          let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                          fire > now,
                          HabitMath.isScheduled(habit, on: day),
                          !store.isDone(habit, on: day) else { continue }
                    if case .timesPerWeek(let target) = habit.schedule,
                       HabitMath.weekCount(from: HabitMath.weekStart(day), through: day, isDone: { store.isDone(habit, on: $0) }) >= target {
                        continue
                    }
                    let content = UNMutableNotificationContent()
                    content.title = habit.name
                    let streak = store.currentStreak(habit)
                    content.body = streak > 1 ? "Keep your \(streak)-day streak going." : "A good moment to get it done."
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                        repeats: false
                    )
                    requests.append(UNNotificationRequest(
                        identifier: "\(prefix)\(habit.id.uuidString)-\(HabitMath.key(day))",
                        content: content,
                        trigger: trigger
                    ))
                    scheduled += 1
                }
            }
        }

        let prefix = Self.prefix
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for request in requests { center.add(request) }
        }
    }

    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }
}
