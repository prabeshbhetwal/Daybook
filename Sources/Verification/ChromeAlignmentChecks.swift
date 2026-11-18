import AppKit
import Foundation

/// Two things that line up: the window buttons with the chrome row beside
/// them, and a period row's hover tint with the card it tints.
enum ChromeAlignmentChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The window buttons sit in the middle of the chrome row at any zoom", buttonsCentred),
        ("A period row's hover tint is its card's, not the whole button's", periodTintIsTheCards),
    ]

    private static func buttonsCentred() -> [String] {
        var problems: [String] = []
        let button: CGFloat = 16
        // The row at 80%, 100% and 160% zoom, and one of an odd height.
        for row in [CGFloat(42), 50, 75, 80] {
            let placed = TrafficLightCentreAnchor.placement(row: row, button: button)
            expect(placed.band == row, "a \(row)pt row is a band of \(placed.band)", &problems)
            let above = placed.band - button - placed.y
            expect(abs(above - placed.y) <= 1,
                   "in a \(row)pt row a button has \(placed.y) below it and \(above) above", &problems)
            expect(placed.y == placed.y.rounded(), "in a \(row)pt row a button sits at \(placed.y)", &problems)
        }
        // A row shorter than a button never cuts the button off.
        let short = TrafficLightCentreAnchor.placement(row: 10, button: button)
        expect(short.band == button && short.y == 0,
               "a 10pt row is a band of \(short.band) with the button at \(short.y)", &problems)
        problems += buttonsStayCentred()
        return problems
    }

    /// AppKit lays its title bar out again at moments no notification names;
    /// a button it moves back is put in the middle again.
    private static func buttonsStayCentred() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 300),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            let anchor = TrafficLightCentreAnchor()
            window.contentView?.addSubview(anchor)
            anchor.height = 66
            guard let close = window.standardWindowButton(.closeButton) else { return problems }
            let middle = TrafficLightCentreAnchor.placement(row: 66, button: close.frame.height).y
            expect(close.frame.origin.y == middle, "a 66pt row puts the button at \(close.frame.origin.y), not \(middle)", &problems)
            // The anchor centres once more outside the view update that added it.
            _ = InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.3)
            close.setFrameOrigin(NSPoint(x: close.frame.origin.x, y: 0))
            _ = InstalledAppCatalog.turnRunLoop(until: { close.frame.origin.y == middle }, timeout: 2)
            expect(close.frame.origin.y == middle,
                   "a button AppKit moved back sits at \(close.frame.origin.y), not \(middle)", &problems)
            // The window the app opens has all three buttons, and each is level with the others.
            let full = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 300),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
            full.titlebarAppearsTransparent = true
            full.titleVisibility = .hidden
            let fullAnchor = TrafficLightCentreAnchor()
            full.contentView?.addSubview(fullAnchor)
            fullAnchor.height = 66
            _ = InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.3)
            let all = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { full.standardWindowButton($0) }
            let centres = all.map { $0.frame.midY }
            expect(all.count == 3 && Set(centres).count == 1,
                   "the three window buttons are centred at \(centres), not level", &problems)
            // AppKit can swap in a zoom button no frame watch sees; a window event lays the
            // buttons out again, so one that came in that way is put level.
            let before = fullAnchor.passes
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: full)
            expect(fullAnchor.passes > before, "losing key focus does not lay the window buttons out again", &problems)
            return problems
        }
    }

    private static func periodTintIsTheCards() -> [String] {
        var problems: [String] = []
        expect(!HistoryTreeRow.buttonTints(isEmpty: false, isPeriod: true),
               "a month's whole button tints under the pointer", &problems)
        expect(HistoryTreeRow.buttonTints(isEmpty: false, isPeriod: false),
               "a plain row's button does not tint under the pointer", &problems)
        expect(!HistoryTreeRow.buttonTints(isEmpty: true, isPeriod: false),
               "an empty row's button tints under the pointer", &problems)
        return problems
    }
}
