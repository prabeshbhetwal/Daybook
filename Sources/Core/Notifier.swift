import Foundation
import UserNotifications

/// Local notifications for away resolution. Every call is guarded so that an
/// unavailable or denied notification centre is a silent no-op — the attention
/// badge and the popover resolve card carry the flow on their own.
///
/// Takes pre-formatted strings: `Core` must not import `Design`.
final class Notifier {

    private(set) var isAuthorized = false

    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                self?.isAuthorized = granted
                if let error {
                    Diagnostics.log("notification authorisation failed: \(error)")
                }
            }
    }

    func postAwayResolution(title: String, body: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "away-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Diagnostics.log("notification post failed: \(error)") }
        }
    }
}
