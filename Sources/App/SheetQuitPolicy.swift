import AppKit

/// AppKit will not quit while a sheet is open, and refuses before it asks the
/// app's delegate: the Quit button, ⌘Q and macOS's own quit at log out,
/// restart or shut down all stop without a word while Settings, Insights or a
/// confirmation is showing. So every sheet lets the app quit, as the window
/// under it always has. A half-written rule or category form goes with it,
/// as it does when Daybook quits with Settings closed.
enum SheetQuitPolicy {
    /// Watches every window of the app for a sheet. Keep the token for as long
    /// as the policy should hold.
    static func observe(center: NotificationCenter = .default) -> NSObjectProtocol {
        center.addObserver(forName: NSWindow.willBeginSheetNotification, object: nil, queue: .main) { note in
            let parent = note.object as? NSWindow
            // The notice comes before the sheet is attached; a turn later it
            // is. A sheet that never becomes key, opened while Daybook is in
            // the background, is still found this way.
            DispatchQueue.main.async {
                parent?.attachedSheet?.preventsApplicationTerminationWhenModal = false
            }
        }
    }
}
