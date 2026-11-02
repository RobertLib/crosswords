import UserNotifications

/// Opens the daily puzzle when the player taps its reminder.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    private weak var app: AppModel?

    init(app: AppModel) {
        self.app = app
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.identifier.hasPrefix(ReminderScheduler.prefix) else { return }
        await MainActor.run { app?.openDailyFromReminder() }
    }
}
