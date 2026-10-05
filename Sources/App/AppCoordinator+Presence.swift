import AppKit
import Combine

extension AppCoordinator {
    /// A Dock icon and the app's menus while they are wanted; a menu bar
    /// agent otherwise. The bundle launches as an agent (`LSUIElement`), so a
    /// login start never flashes a Dock icon before the setting is read.
    func applyPresence() {
        let regular = AppPresence.showsDockIcon(mode: settings.dockIconMode,
                                                windowOpen: mainWindowOpen,
                                                menuBarIconShown: settings.showsMenuBarIcon)
        let policy: NSApplication.ActivationPolicy = regular ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Menus appear only once a regular app is active again.
        if regular, mainWindowOpen { NSApp.activate(ignoringOtherApps: true) }
    }

    /// What opens the window without the menu bar icon's help: the welcome
    /// beginning (nothing else is on screen at first launch), and the app
    /// opened again from Finder, Spotlight or the Dock.
    func observeWindowRequests() {
        firstRun.$progress
            .map { $0 != nil }
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.windowOpener?.open(nil) }
            .store(in: &windowRequests)
        reopenRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.windowOpener?.reopen() }
            .store(in: &windowRequests)
    }
}

