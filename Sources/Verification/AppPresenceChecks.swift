import Foundation
import AppKit
import SwiftUI

/// When the app shows a Dock icon and its menus, and that it can never be
/// left with no way in.
enum AppPresenceChecks {
    static let tests: [(String, () -> [String])] = [
        ("The Dock icon follows its setting and the window, and never leaves the app unreachable",
         dockIconRule),
        ("Hiding the menu bar icon keeps the Dock icon, and both settings start where the app always was",
         settingsKeepAWayIn),
        ("The main window reports opening when shown and closing only when closed, not when hidden",
         windowReportsOpenAndClose)
    ]

    static func dockIconRule() -> [String] {
        var problems: [String] = []
        let cases: [(DockIconMode, Bool, Bool, Bool)] = [
            (.whileWindowOpen, true, true, true), (.whileWindowOpen, false, true, false),
            (.always, false, true, true), (.never, true, true, false),
            // No menu bar icon: whatever the mode, the Dock is the way in.
            (.never, false, false, true), (.whileWindowOpen, false, false, true)
        ]
        for (mode, open, iconShown, expected) in cases
        where AppPresence.showsDockIcon(mode: mode, windowOpen: open, menuBarIconShown: iconShown) != expected {
            problems.append("\(mode), window open \(open), menu bar icon \(iconShown) gave \(!expected)")
        }
        return problems
    }

    static func settingsKeepAWayIn() -> [String] {
        let suite = "fc-presence-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not make a defaults suite"] }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistenceStore(defaults: defaults)
        var changes = 0
        let settings = SettingsModel(store: store, isTrackingEnabled: true, onChange: {},
                                     onTrackingChanged: { _ in }, onPresenceChanged: { changes += 1 })
        var problems: [String] = []
        if !settings.showsMenuBarIcon || settings.dockIconMode != .whileWindowOpen {
            problems.append("a new install did not start with the menu bar icon and a Dock icon while the window is open")
        }
        settings.dockIconMode = .never
        settings.showsMenuBarIcon = false
        if settings.dockIconMode != .always {
            problems.append("hiding the menu bar icon left the Dock icon on \(settings.dockIconMode)")
        }
        if changes != 2 { problems.append("the coordinator heard \(changes) presence changes, not 2") }
        store.removeAll()
        if !settings.showsMenuBarIcon || settings.dockIconMode != .whileWindowOpen {
            problems.append("Reset did not bring back the menu bar icon and the default Dock icon")
        }
        return problems
    }

    /// The coordinator learns of the window through this signal alone, so the
    /// Dock icon is only as right as it: shown is open, ordered out (as Hide
    /// does) is still open, and only a close is closed.
    static func windowReportsOpenAndClose() -> [String] {
        MainActor.assumeIsolated {
            var events: [Bool] = []
            let window = NSWindow(contentRect: NSRect(x: -4_000, y: -4_000, width: 120, height: 60),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Color.clear.frame(width: 120, height: 60)
                .background(WindowDormancy(onOpenChange: { events.append($0) })))
            func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            spin()
            window.orderFront(nil); spin()
            window.orderOut(nil); spin()
            window.orderFront(nil); spin()
            window.close(); spin()
            var problems: [String] = []
            if events.first != true { problems.append("showing the window did not report it open: \(events)") }
            if events.last != false { problems.append("closing the window did not report it closed: \(events)") }
            if events.dropLast().contains(false) { problems.append("hiding the window reported it closed: \(events)") }
            return problems
        }
    }
}
