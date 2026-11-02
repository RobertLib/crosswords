import Foundation
import UserNotifications

/// Schedules the optional local "daily puzzle" reminder. Purely on-device.
///
/// Instead of one repeating notification, the next eight weeks are scheduled individually,
/// so a day whose puzzle is already solved can be skipped. The schedule is checked whenever
/// the app becomes active or a daily puzzle is solved, and written again only when it has
/// changed. Reminders already delivered are cleared once they are out of date, and tapping one
/// opens the daily puzzle.
enum ReminderScheduler {
    nonisolated static let prefix = "daily-reminder-"
    /// Long enough to bring back a player who stopped opening the app, within the 64 pending
    /// notifications iOS keeps for an app.
    private static let daysAhead = 56

    /// Asks for permission if needed. Returns whether reminders can be delivered.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    /// Whether the player has turned notifications off for the app.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func refresh(settings: PlayerSettings, solvedToday: Bool, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        // A reminder left in Notification Center is stale once its day is over or its puzzle solved.
        let todayID = prefix + DailySchedule.key(for: now)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            $0.hasPrefix(prefix) && ($0 < todayID || ($0 == todayID && solvedToday))
        })

        let wanted = requests(settings: settings, solvedToday: solvedToday, now: now)
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        // The app becomes active often, and mostly nothing has changed: then the schedule stays.
        guard !isScheduled(wanted, as: pending) else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        for request in wanted {
            // Superseded by a newer refresh, which starts over.
            guard !Task.isCancelled else { return }
            try? await center.add(request)
        }
    }

    /// The reminders the settings ask for from `now` on: one a day at the chosen time, none for a
    /// time already past or for today once its puzzle is solved.
    static func requests(settings: PlayerSettings, solvedToday: Bool, now: Date = .now,
                         calendar: Calendar = .current) -> [UNNotificationRequest] {
        guard settings.reminderEnabled else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fireDate = calendar.date(bySettingHour: settings.reminderHour, minute: settings.reminderMinute,
                                               second: 0, of: day),
                  fireDate > now, !(offset == 0 && solvedToday) else { return nil }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Your daily puzzle is ready")
            content.body = String(localized: "A fresh crossword is waiting. Keep your streak glowing!")
            content.sound = .default
            // No time zone: the reminder keeps to the local time wherever the player is.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            return UNNotificationRequest(identifier: prefix + DailySchedule.key(for: day), content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }
    }

    /// Whether the pending reminders are exactly the wanted ones: the same days, times and text.
    static func isScheduled(_ wanted: [UNNotificationRequest], as pending: [UNNotificationRequest]) -> Bool {
        func signature(_ request: UNNotificationRequest) -> String {
            let c = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
            let time = [c?.year, c?.month, c?.day, c?.hour, c?.minute].map { $0.map(String.init) ?? "-" }
            return ([request.identifier] + time + [request.content.title, request.content.body]).joined(separator: "|")
        }
        return Set(wanted.map(signature)) == Set(pending.map(signature)) && wanted.count == pending.count
    }
}
