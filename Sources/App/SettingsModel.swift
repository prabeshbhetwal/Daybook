import SwiftUI
import AppKit

/// The Settings window's model. Wraps the `PersistenceStore` properties the
/// window edits and tells the session store to refresh after each write, so a
/// changed goal moves the ring and a changed threshold moves the away ladder
/// without either surface holding a reference to the other.
///
/// Properties are plain computed settables rather than `@Published`: the truth
/// lives in `UserDefaults`, and `ObservedObject`'s projected bindings work on
/// any settable property. `objectWillChange` is sent by hand before each write.
final class SettingsModel: ObservableObject {

    private let store: PersistenceStore
    private let onChange: () -> Void
    private let onTrackingChanged: (Bool) -> Void
    private let onRevealDataFolder: (() -> Void)?
    /// Mirrored here because the tracker — not the preference — is the truth
    /// about whether recording is on, and the tracker lives with the store.
    private var trackingEnabled: Bool

    init(store: PersistenceStore,
         isTrackingEnabled: Bool,
         onChange: @escaping () -> Void,
         onTrackingChanged: @escaping (Bool) -> Void,
         revealDataFolder: (() -> Void)? = nil) {
        self.store = store
        self.trackingEnabled = isTrackingEnabled
        self.onChange = onChange
        self.onTrackingChanged = onTrackingChanged
        self.onRevealDataFolder = revealDataFolder
    }

    private func write(_ body: () -> Void) {
        objectWillChange.send()
        body()
        onChange()
    }

    var dailyGoal: TimeInterval {
        get { store.dailyGoal }
        set { write { store.dailyGoal = newValue } }
    }

    var autoSessionsEnabled: Bool {
        get { store.autoSessionsEnabled }
        set { write { store.autoSessionsEnabled = newValue } }
    }

    var rewardsEnabled: Bool {
        get { store.rewardsEnabled }
        set { write { store.rewardsEnabled = newValue } }
    }

    var remindersEnabled: Bool {
        get { store.remindersEnabled }
        set { write { store.remindersEnabled = newValue } }
    }

    var breakThreshold: TimeInterval {
        get { store.breakThreshold }
        set { write { store.breakThreshold = newValue } }
    }

    var longAwayCap: TimeInterval {
        get { store.longAwayCap }
        set { write { store.longAwayCap = newValue } }
    }

    /// 0 means Never, so the picker has a concrete tag to bind to.
    var fullPromptAfter: TimeInterval {
        get { store.fullPromptAfter ?? 0 }
        set { write { store.fullPromptAfter = newValue > 0 ? newValue : nil } }
    }

    var breakLength: TimeInterval {
        get { store.breakLength }
        set { write { store.breakLength = newValue } }
    }

    var menuSessionCount: Int {
        get { store.menuSessionCount }
        set { write { store.menuSessionCount = newValue } }
    }

    var isTrackingEnabled: Bool {
        get { trackingEnabled }
        set {
            objectWillChange.send()
            trackingEnabled = newValue
            onTrackingChanged(newValue)
        }
    }

    /// Read-only: reveals local history without mutating a preference or
    /// asking Finder for any additional permission.
    func revealDataFolder() {
        if let onRevealDataFolder {
            onRevealDataFolder()
        } else {
            Self.revealDataFolder(at: SessionArchive.defaultDirectory)
        }
    }

    /// Ensures a pristine install has something Finder can reveal. Returning a
    /// Bool and injecting open/log keeps both failure branches deterministic in
    /// the headless suite while the default path uses the real local services.
    @discardableResult
    static func revealDataFolder(
        at directory: URL,
        fileManager: FileManager = .default,
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) },
        log: (String) -> Void = Diagnostics.log
    ) -> Bool {
        do {
            try fileManager.createDirectory(at: directory,
                                            withIntermediateDirectories: true)
        } catch {
            log("could not create data folder at \(directory.path): \(error)")
            return false
        }
        guard open(directory) else {
            log("could not reveal data folder at \(directory.path): Finder refused to open it")
            return false
        }
        return true
    }

    /// Opens the Settings scene. `SettingsLink` is macOS 14; on 13 the scene is
    /// reached through the responder chain, and the app must be frontmost first
    /// or the window opens behind whatever was.
    static func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
