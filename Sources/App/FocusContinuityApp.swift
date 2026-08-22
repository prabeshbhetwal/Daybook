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
            PopoverView(store: coordinator.store) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "today")
            }
        } label: {
            MenuBarLabelView(store: coordinator.store)
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "today") {
            DashboardView(store: coordinator.store)
        }
        .defaultSize(width: 1020, height: 920)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: coordinator.settings)
        }
    }
}
