import Foundation
import UserNotifications

/// Local notifications for away resolution. Every call is guarded so that an
/// unavailable or denied notification centre is a silent no-op — the attention
/// badge and the popover resolve card carry the flow on their own.
///
/// Takes pre-formatted strings: `Core` must not import `Design`.
final class Notifier {

    /// Nothing is posted before the app has asked. The self-test binary never
    /// asks, and it has no notification centre to post to.
    private var hasAsked = false

    func requestAuthorization() {
        hasAsked = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error {
                    Diagnostics.log("notification authorisation failed: \(error)")
                }
            }
    }

    /// Permission is read when posting, not remembered from launch: someone
    /// who allows notifications in System Settings later gets the next one
    /// without restarting the app, and someone who turns them off is not
    /// posted to.
    func postAwayResolution(title: String, body: String) {
        guard hasAsked else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: "away-\(UUID().uuidString)",
                                                content: content,
                                                trigger: nil)
            center.add(request) { error in
                if let error { Diagnostics.log("notification post failed: \(error)") }
            }
        }
    }
}
