import AppKit
import SwiftUI

/// Settings in a window of its own, the way Mac apps keep them: its own title
/// bar and close button, beside the main window rather than over it. The
/// navigation model still owns whether it is showing (`sheet == .settings`),
/// so every route that opened the old sheet opens this window.
enum SettingsWindow {
    static let id = "settings"

    /// Brings the window forward from anywhere: a menu, the menu bar panel or
    /// the main window. An app without a Dock icon opens it behind the front
    /// app unless it activates first.
    @MainActor static func open(_ openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

/// The window's content: the Settings page with the environment the main
/// window gives its own views, so menus, editors and zoom behave the same.
struct SettingsWindowContent: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    let store: SessionStore

    var body: some View {
        SettingsView(model: settings, navigation: navigation)
            // Fills the window whatever its size. The window's maximum width
            // is this one (`.contentSize` in DaybookApp), so a zoomed window
            // grows taller and never wider than the page, with no bare bands.
            .frame(minWidth: SettingsLayout.minimumWindowWidth, idealWidth: SettingsLayout.maximumWindowWidth,
                   maxWidth: SettingsLayout.maximumWindowWidth,
                   minHeight: SettingsLayout.minimumWindowHeight, idealHeight: SettingsLayout.sheetHeight,
                   maxHeight: .infinity)
            .background(StoryStyle.canvas)
            .environment(\.focusInterfaceDensity, settings.interfaceDensity)
            .zoomRoot()
            .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
            .environment(\.confirmationPolicy, settings.confirmationPolicy)
            .environment(\.openActivityEditor) { request in
                ActivityEditorPanel.shared.show(request, store: store)
            }
            // A category added here becomes the one the next session uses,
            // as it does from any other menu.
            .environment(\.openCategoryEditor) { request in
                CategoryEditorPanel.shared.show(request, model: settings) { definition, wasNew in
                    if wasNew { store.workType = definition.workType }
                }
            }
            .environment(\.haptics) { moment in settings.playHaptic(moment) }
            .tint(StoryStyle.action)
            // Closing the window is closing Settings. A sheet the main window
            // opened since is not this window's to take down.
            .onDisappear { if navigation.sheet == .settings { navigation.closeSheet() } }
    }
}
