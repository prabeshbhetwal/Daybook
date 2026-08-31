import SwiftUI
import AppKit

/// Dedicated verification entry. Unlike --fixture-window on the production
/// executable, this remains isolated when Launch Services drops its arguments.
/// AppCoordinator and the production App entry are never constructed here.
@MainActor private final class NativeFixtureContext: ObservableObject {
    let scenario: SnapshotScenario
    let store: SessionStore
    let navigation: MainWindowModel
    let settings: SettingsModel

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "FCVerificationScenario") as? String
        guard let scenario = configured.flatMap(SnapshotScenario.init(rawValue:)) else {
            FileHandle.standardError.write(Data("Unknown or missing fixture scenario.\n".utf8))
            exit(2)
        }
        self.scenario = scenario
        let store = Snapshotter.store(for: scenario)
        self.store = store
        navigation = Snapshotter.navigation(for: scenario, store: store)
        settings = SettingsModel(store: store.engine.store, isTrackingEnabled: store.isTrackingEnabled,
            onChange: { store.refresh() }, onTrackingChanged: { store.setTrackingEnabled($0) },
            onAppearanceChanged: { $0.apply(to: NSApplication.shared) },
            dataDirectory: store.engine.archive.dataDirectoryURL)
        settings.appearancePreference = .system
    }
}

@main private struct NativeFixtureApp: App {
    @NSApplicationDelegateAdaptor(StoryFixtureDelegate.self) private var delegate
    @StateObject private var context = NativeFixtureContext()

    var body: some Scene {
        Window("FocusContinuity — safe verification", id: "safe-verification") {
            MainWindowView(store: context.store, settings: context.settings, navigation: context.navigation)
                .environment(\.storyEntryInitiallyOpen, context.scenario.opensStoryEntry)
        }
        .defaultSize(width: 1_160, height: 780)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands { MainWindowCommands(navigation: context.navigation) }
    }
}
