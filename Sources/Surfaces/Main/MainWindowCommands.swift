import SwiftUI
import AppKit

/// Application commands route through the same model as the tab rail and deep
/// links, then reveal the single persistent main window.
struct MainWindowCommands: Commands {
    let navigation: MainWindowModel

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(Array(StoryScope.allCases.enumerated()), id: \.element.id) { index, scope in
                Button(scope.title) {
                    navigation.selectScope(scope)
                    revealMainWindow()
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))),
                                  modifiers: [.command])
            }
            Divider()
            Button("History") { route(to: .review) }
                .keyboardShortcut("4", modifiers: [.command])
            Button("Insights") { route(to: .insights) }
                .keyboardShortcut("5", modifiers: [.command])
            Button("Awards") { route(to: .awards) }
                .keyboardShortcut("6", modifiers: [.command])
            Divider()
            Button("Focus session…") { route(to: .focus) }
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
