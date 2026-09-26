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
        FocusContinuityApp.main()
    }
}

struct FocusContinuityApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                store: coordinator.store,
                settings: coordinator.settings,
                onOpenApplication: { openMainWindow() },
                onOpenSettings: { openMainWindow(on: .settings) },
                onOpenCategoryEditor: { request in
                    CategoryEditorPanel.shared.show(request, model: coordinator.settings) { definition, wasNew in
                        if wasNew { coordinator.store.workType = definition.workType }
                    }
                },
                onOpenActivityEditor: { request in
                    ActivityEditorPanel.shared.show(request, store: coordinator.store)
                }
            )
        } label: {
            MenuBarLabelView(model: coordinator.menuBarLabel)
                // The app is an LSUIElement, so nothing is on screen at first
                // launch. A welcome nobody can see is no welcome: when one
                // begins, the window it explains has to be in front of them.
                .onReceive(coordinator.firstRun.$progress.map { $0 != nil }.removeDuplicates()) { active in
                    if active { openMainWindow() }
                }
        }
        .menuBarExtraStyle(.window)

        Window("FocusContinuity", id: "main") {
            MainWindowView(
                store: coordinator.store,
                settings: coordinator.settings,
                navigation: coordinator.mainWindow,
                firstRun: coordinator.firstRun
            )
        }
        .defaultSize(width: 1_160, height: 780)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MainWindowCommands(navigation: coordinator.mainWindow)
        }
    }

    private func openMainWindow(on tab: AppTab? = nil) {
        if let tab { coordinator.mainWindow.open(tab: tab) }
        else { coordinator.mainWindow.revealApplication() }
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
