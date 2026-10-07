import Combine
import SwiftUI

/// Entry point. A separate `@main` type is required: defining `static func main()`
/// on the `App` struct itself would shadow the implementation the `App` protocol
/// provides, leaving no way to actually start the scene phase.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--gallery") {
            GalleryApp.main()
            return
        }
        if CommandLine.arguments.contains("--fixture-window") {
            StoryFixtureApp.main()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let path = CommandLine.arguments.count > index + 1
                ? CommandLine.arguments[index + 1]
                : FileManager.default.currentDirectoryPath + "/snapshots"
            exit(Snapshotter.run(directory: URL(fileURLWithPath: path)) ? 0 : 1)
        }
        quitLegacyApp()
        NameMigration.run()
        DaybookApp.main()
    }

    /// A copy still running under the old name writes the same history, so it
    /// is asked to quit before the folder moves, and stopped if it will not.
    private static func quitLegacyApp() {
        guard NameMigration.legacyDomain != FocusConstants.bundleIdentifier else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: NameMigration.legacyDomain)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        waitUntilGone(running, seconds: 10)
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        waitUntilGone(running, seconds: 2)
    }

    private static func waitUntilGone(_ apps: [NSRunningApplication], seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
}

struct DaybookApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    /// Read straight from the defaults so the status item comes and goes as
    /// the setting changes; written only through the settings model.
    @AppStorage(PersistenceStore.showsMenuBarIconKey) private var showsMenuBarIcon = true

    var body: some Scene {
        let _ = coordinator.windowOpener = WindowOpener(
            open: { tab in openMainWindow(on: tab) },
            // Opened again from Finder, Spotlight or the Dock while running:
            // the window comes forward as it was, with any open sheet and
            // unsaved form still in it.
            reopen: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            })
        // SwiftUI writes this binding back whenever it syncs the status item,
        // unchanged value included. Writing that through saved the default
        // again, which rebuilt the scene, which wrote again: a busy loop.
        MenuBarExtra(isInserted: Binding(get: { showsMenuBarIcon },
                                         set: { if $0 != showsMenuBarIcon { coordinator.settings.showsMenuBarIcon = $0 } })) {
            // Closing the panel only orders it out; this rests its content
            // until it is shown again, so a closed panel costs nothing.
            PanelRest { PopoverView(
                store: coordinator.store,
                settings: coordinator.settings,
                onOpenApplication: { openMainWindow() },
                onOpenSettings: { openMainWindow(on: .settings) },
                onCheckForUpdates: { coordinator.updater.checkForUpdates() },
                onOpenCategoryEditor: { request in
                    CategoryEditorPanel.shared.show(request, model: coordinator.settings) { definition, wasNew in
                        if wasNew { coordinator.store.workType = definition.workType }
                    }
                },
                onOpenActivityEditor: { request in
                    ActivityEditorPanel.shared.show(request, store: coordinator.store)
                }
            ) }
        } label: {
            MenuBarLabelView(model: coordinator.menuBarLabel)
        }
        .menuBarExtraStyle(.window)

        Window("Daybook", id: "main") {
            MainWindowView(
                store: coordinator.store,
                settings: coordinator.settings,
                navigation: coordinator.mainWindow,
                firstRun: coordinator.firstRun
            )
            // A closed window is kept whole by SwiftUI and would go on
            // re-rendering the story every second; it rests until reopened.
            .background(WindowDormancy(onOpenChange: { coordinator.mainWindowOpen = $0 }))
        }
        .defaultSize(width: 1_160.zoomed, height: 780.zoomed)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MainWindowCommands(navigation: coordinator.mainWindow)
            SessionCommands(store: coordinator.store,
                            state: coordinator.sessionCommandState)
            UpdateCommands(updater: coordinator.updater)
        }
    }

    /// "Check for Updates…" under About in the Daybook menu, where
    /// Mac apps keep it.
    struct UpdateCommands: Commands {
        @ObservedObject var updater: AppUpdater

        var body: some Commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    private func openMainWindow(on tab: AppTab? = nil) {
        if let tab { coordinator.mainWindow.open(tab: tab) }
        else { coordinator.mainWindow.revealApplication() }
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
