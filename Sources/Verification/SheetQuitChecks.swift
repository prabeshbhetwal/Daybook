import AppKit

/// AppKit refuses to quit while a sheet is open, before the delegate is
/// asked, so every sheet Daybook shows must let the app quit: the Quit
/// button, ⌘Q and macOS's own quit at log out, restart or shut down.
enum SheetQuitChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Quit works while Settings, or a confirmation over it, is open", sheetsLetTheAppQuit),
    ]

    private static func sheetsLetTheAppQuit() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let token = SheetQuitPolicy.observe()
            defer { NotificationCenter.default.removeObserver(token) }
            func window(_ rect: NSRect) -> NSWindow {
                NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
            }
            let main = window(NSRect(x: -10_000, y: -10_000, width: 400, height: 300))
            let settings = window(NSRect(x: 0, y: 0, width: 300, height: 200))
            let confirmation = window(NSRect(x: 0, y: 0, width: 200, height: 100))
            // Never made key, as when Daybook opens a sheet in the background.
            main.orderFront(nil)
            main.beginSheet(settings)
            settings.beginSheet(confirmation)
            _ = InstalledAppCatalog.turnRunLoop(until: {
                !settings.preventsApplicationTerminationWhenModal
                    && !confirmation.preventsApplicationTerminationWhenModal
            }, timeout: 2)
            for (name, sheet, parent) in [("Settings", settings, main), ("a confirmation", confirmation, settings)] {
                expect(parent.attachedSheet === sheet && !sheet.preventsApplicationTerminationWhenModal,
                       "\(name) lets the app quit, got attached \(parent.attachedSheet === sheet), "
                       + "prevents quit \(sheet.preventsApplicationTerminationWhenModal)", &problems)
            }
            settings.endSheet(confirmation)
            main.endSheet(settings)
            main.orderOut(nil)
            return problems
        }
    }
}
