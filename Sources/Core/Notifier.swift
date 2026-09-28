import Foundation
import UserNotifications

/// Local notifications for away resolution. Every call is guarded so that an
/// unavailable or denied notification centre is a silent no-op — the attention
/// badge and the popover resolve card carry the flow on their own.
///
/// Takes pre-formatted strings: `Core` must not import `Design`.
final class Notifier {

    /// Only an app bundle has a notification centre; the bare self-test and
    /// snapshot binaries would raise on asking for one.
    private var hasCentre: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func requestAuthorization(then: ((Bool) -> Void)? = nil) {
        guard hasCentre else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    Diagnostics.log("notification authorisation failed: \(error)")
                }
                then?(granted)
            }
    }

    /// Permission is read when posting, not remembered from launch: someone
    /// who allows notifications in System Settings later gets the next one
    /// without restarting the app, and someone who turns them off is not
    /// posted to. If nobody has been asked yet (a welcome left before its
    /// end), the first reminder is the moment to ask.
    func postAwayResolution(title: String, body: String) {
        guard hasCentre else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Self.post(title: title, body: body, to: center)
            case .notDetermined:
                self?.requestAuthorization { granted in
                    if granted { Self.post(title: title, body: body, to: center) }
                }
            default:
                return
            }
        }
    }

    private static func post(title: String, body: String, to center: UNUserNotificationCenter) {
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
