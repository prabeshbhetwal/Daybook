import SwiftUI
import AppKit

/// Application commands route through the same model as the tab rail and deep
/// links, then reveal the single persistent main window.
struct MainWindowCommands: Commands {
    let navigation: MainWindowModel

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Navigate") {
            // The day's story and History are the two places to read.
            Button("Story") {
                navigation.returnToStory()
                revealMainWindow()
            }
            .keyboardShortcut("1", modifiers: [.command])
            Button("History") { route(to: .review) }
                .keyboardShortcut("2", modifiers: [.command])
            Button("Find in History") {
                navigation.findInHistory()
                revealMainWindow()
            }
            .keyboardShortcut("f", modifiers: [.command])
            Divider()
            Button("Awards") { route(to: .awards) }
                .keyboardShortcut("6", modifiers: [.command])
            Divider()
            Button("Session controls…") { route(to: .focus) }
                .keyboardShortcut("7", modifiers: [.command])
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
