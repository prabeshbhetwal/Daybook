import SwiftUI
import AppKit

/// Speaks a sentence to VoiceOver without moving its cursor.
///
/// A sighted reader sees an error arrive under a field, or a card change
/// places; someone listening hears nothing unless the change is said out
/// loud. High priority, because each of these is a direct answer to what the
/// reader just did.
enum Announcement {
    static func post(_ text: String) {
        guard !text.isEmpty else { return }
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [
                                .announcement: text,
                                .priority: NSAccessibilityPriorityLevel.high.rawValue
                             ])
    }
}

extension View {
    /// Says a message when it appears or changes — a save that failed, a
    /// value that was refused — so it is heard as well as seen.
    func announcesChanges(to message: String?) -> some View {
        onChange(of: message) { next in
            if let next { Announcement.post(next) }
        }
    }
}
