import SwiftUI
import AppKit

/// Application commands route through the same model as the tab rail and deep
/// links, then reveal the single persistent main window.
struct MainWindowCommands: Commands {
    let navigation: MainWindowModel

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(AppTab.allCases) { tab in
                Button(tab.title) {
                    route(to: tab)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(tab.commandNumber))),
                                  modifiers: [.command])
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                navigation.openSettings()
                revealMainWindow()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private func route(to tab: AppTab) {
        navigation.open(tab: tab)
        revealMainWindow()
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
