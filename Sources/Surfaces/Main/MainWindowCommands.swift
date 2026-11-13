import SwiftUI
import AppKit

/// Application commands route through the same model as the tab rail and deep
/// links, then reveal the single persistent main window.
struct MainWindowCommands: Commands {
    /// Observed so Previous Day and Next Day enable and disable as the day
    /// being read changes.
    @ObservedObject var navigation: MainWindowModel

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
            Button("Go to Date…") {
                navigation.goToDate()
                revealMainWindow()
            }
            .keyboardShortcut("j", modifiers: [.command])
            Button("Ask Daybook…") {
                navigation.openAsk()
                revealMainWindow()
            }
            .keyboardShortcut("k", modifiers: [.command])
            Divider()
            // Option-Command-arrows: ⌘[ and ⌘] are the tour card's Back and
            // Next, and ⌥⌘N, P, A, B and S belong to the Session menu.
            Button("Previous Day") { stepDay(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(navigation.historyDayTarget(by: -1) == nil)
            Button("Next Day") { stepDay(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(navigation.historyDayTarget(by: 1) == nil)
            Divider()
            Button("Awards") { route(to: .awards) }
                .keyboardShortcut("6", modifiers: [.command])
            Divider()
            Button("Session Controls") { route(to: .focus) }
                .keyboardShortcut("7", modifiers: [.command])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                navigation.openSettings()
                SettingsWindow.open(openWindow)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private func route(to tab: AppTab) {
        navigation.open(tab: tab)
        revealMainWindow()
    }

    private func stepDay(by delta: Int) {
        navigation.stepHistoryDay(by: delta)
        revealMainWindow()
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
