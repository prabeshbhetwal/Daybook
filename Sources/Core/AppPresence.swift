import Foundation

/// When FocusContinuity shows a Dock icon, and with it the app's own menus
/// across the top of the screen. The menu bar icon is the other way in.
enum DockIconMode: String, CaseIterable {
    case whileWindowOpen
    case always
    case never
}

enum AppPresence {
    /// A regular app (Dock icon, menus) or a menu bar agent. With the menu bar
    /// icon hidden, the Dock is the only way back in, so it always shows.
    static func showsDockIcon(mode: DockIconMode, windowOpen: Bool, menuBarIconShown: Bool) -> Bool {
        guard menuBarIconShown else { return true }
        switch mode {
        case .always: return true
        case .never: return false
        case .whileWindowOpen: return windowOpen
        }
    }
}
