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
                onOpenFocus: { openMainWindow(on: .focus) },
                onOpenSettings: { openMainWindow(on: .settings) }
            )
        } label: {
            MenuBarLabelView(store: coordinator.store)
        }
        .menuBarExtraStyle(.window)

        Window("FocusContinuity", id: "main") {
            MainWindowView(
                store: coordinator.store,
                settings: coordinator.settings,
                navigation: coordinator.mainWindow
            )
        }
        .defaultSize(width: 1_160, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            MainWindowCommands(navigation: coordinator.mainWindow)
        }
    }

    private func openMainWindow(on tab: AppTab) {
        coordinator.mainWindow.open(tab: tab)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
