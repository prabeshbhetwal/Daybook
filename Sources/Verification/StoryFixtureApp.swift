import SwiftUI
import AppKit

/// A real native window, backed exclusively by temporary fixtures. Unlike a
/// raster snapshot this exercises sheets, keyboard focus and AppKit appearance.
/// It creates no coordinator, system monitors or live-history archive.
@MainActor final class StoryFixtureContext: ObservableObject {
    let store: SessionStore
    let navigation: MainWindowModel
    let settings: SettingsModel

    init() {
        let arguments = CommandLine.arguments
        let scenario = arguments.firstIndex(of: "--fixture-window").flatMap { index in
            index + 1 < arguments.count ? SnapshotScenario(rawValue: arguments[index + 1]) : nil
        } ?? .storyDay
        let store = Snapshotter.store(for: scenario)
        self.store = store
        navigation = Snapshotter.navigation(for: scenario, store: store)
        settings = SettingsModel(store: store.engine.store,
                                 isTrackingEnabled: true,
                                 onChange: { store.refresh() },
                                 onTrackingChanged: { store.setTrackingEnabled($0) },
                                 onAppearanceChanged: { $0.apply(to: NSApplication.shared) },
                                 diagnostics: SettingsDiagnostics(
                                    usageAccuracyEpoch: store.usage?.metadata.accurateFrom,
                                    legacyBackupURL: nil,
                                    recoverySummary: "Isolated verification data. Your history is not loaded.",
                                    version: "Verification", build: "local"),
                                 dataDirectory: store.engine.archive.dataDirectoryURL)
        settings.appearancePreference = .system
    }
}

final class StoryFixtureDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        FixtureFactory.cleanUp()
    }
}

struct StoryFixtureApp: App {
    @NSApplicationDelegateAdaptor(StoryFixtureDelegate.self) private var delegate
    @StateObject private var context = StoryFixtureContext()

    var body: some Scene {
        Window("FocusContinuity — isolated verification", id: "main") {
            MainWindowView(store: context.store, settings: context.settings,
                           navigation: context.navigation)
        }
        .defaultSize(width: 1_160, height: 780)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands { MainWindowCommands(navigation: context.navigation) }
    }
}
