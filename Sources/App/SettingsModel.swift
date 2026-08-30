import SwiftUI
import AppKit

/// Exhaustive identifiers for rows that can mutate behaviour. Each case maps
/// to one real SettingsModel property below; section metadata reuses these keys
/// so search/navigation cannot advertise a control with no backing behaviour.
enum SettingsControlKey: String, CaseIterable, Hashable {
    case defaultTab
    case dailyGoal
    case breakThreshold
    case longAwayCap
    case fullPromptAfter
    case reminders
    case automaticSessions
    case automaticGap
    case rewards
    case sessionsPerApp
    case usageRecording
    case appearance
    case density
    case timelineLabels

    var modelKeyPath: PartialKeyPath<SettingsModel> {
        switch self {
        case .defaultTab: return \SettingsModel.defaultAppTab
        case .dailyGoal: return \SettingsModel.dailyGoal
        case .breakThreshold: return \SettingsModel.breakThreshold
        case .longAwayCap: return \SettingsModel.longAwayCap
        case .fullPromptAfter: return \SettingsModel.fullPromptAfter
        case .reminders: return \SettingsModel.remindersEnabled
        case .automaticSessions: return \SettingsModel.autoSessionsEnabled
        case .automaticGap: return \SettingsModel.breakLength
        case .rewards: return \SettingsModel.rewardsEnabled
        case .sessionsPerApp: return \SettingsModel.menuSessionCount
        case .usageRecording: return \SettingsModel.isTrackingEnabled
        case .appearance: return \SettingsModel.appearancePreference
        case .density: return \SettingsModel.interfaceDensity
        case .timelineLabels: return \SettingsModel.showsTimelineLabels
        }
    }
}

/// Read-only facts shown in Data and Advanced. The live constructor receives
/// the already-open archive, avoiding a second read/migration pass merely to
/// populate Settings.
struct SettingsDiagnostics {
    let usageAccuracyEpoch: Date?
    let legacyBackupURL: URL?
    let recoverySummary: String
    let version: String
    let build: String

    static func live(usage: AppUsageArchive, bundle: Bundle = .main,
                     dataDirectory: URL = SessionArchive.defaultDirectory,
                     fileManager: FileManager = .default) -> SettingsDiagnostics {
        let backup = usage.legacyBackupURL
            ?? latestLegacyBackup(in: dataDirectory, fileManager: fileManager)
        let recovery: String
        if usage.isReadOnly {
            recovery = "App usage is read-only because its source evidence could not be safely rewritten."
        } else if backup != nil {
            recovery = "Legacy app usage was migrated only after its original bytes were preserved."
        } else {
            recovery = "No evidence-preserving recovery is currently required."
        }
        return SettingsDiagnostics(
            usageAccuracyEpoch: usage.metadata.accurateFrom,
            legacyBackupURL: backup,
            recoverySummary: recovery,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "Development",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "Unnumbered")
    }

    /// Migration backups intentionally remain ordinary files beside the live
    /// archive. Rediscovering them makes the Data pane truthful after relaunch
    /// without opening, rewriting or otherwise touching their evidence.
    static func latestLegacyBackup(in directory: URL,
                                   fileManager: FileManager = .default) -> URL? {
        let prefix = "app-usage-v1-backup-"
        let suffix = ".json"
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return nil }
        return entries.compactMap { url -> (stamp: Int, url: URL)? in
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            guard name.hasPrefix(prefix), name.hasSuffix(suffix),
                  fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return nil }
            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -suffix.count)
            guard let stamp = Int(name[start..<end]) else { return nil }
            return (stamp, url)
        }
        .max { $0.stamp < $1.stamp }?.url
    }

    static let unavailable = SettingsDiagnostics(
        usageAccuracyEpoch: nil,
        legacyBackupURL: nil,
        recoverySummary: "Archive diagnostics are unavailable in this presentation context.",
        version: "Development",
        build: "Unnumbered")
}

/// Preferences projected into the SwiftUI surface tree. Keeping the density
/// itself in the environment lets each consumer derive its own appropriate
/// layout metrics without adding a parallel global style object.
private struct FocusInterfaceDensityKey: EnvironmentKey {
    static let defaultValue = InterfaceDensity.comfortable
}

private struct FocusTimelineLabelsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var focusInterfaceDensity: InterfaceDensity {
        get { self[FocusInterfaceDensityKey.self] }
        set { self[FocusInterfaceDensityKey.self] = newValue }
    }

    var focusShowsTimelineLabels: Bool {
        get { self[FocusTimelineLabelsKey.self] }
        set { self[FocusTimelineLabelsKey.self] = newValue }
    }
}

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
    let diagnostics: SettingsDiagnostics
    /// Mirrored here because the tracker — not the preference — is the truth
    /// about whether recording is on, and the tracker lives with the store.
    private var trackingEnabled: Bool

    init(store: PersistenceStore,
         isTrackingEnabled: Bool,
         onChange: @escaping () -> Void,
         onTrackingChanged: @escaping (Bool) -> Void,
         revealDataFolder: (() -> Void)? = nil,
         diagnostics: SettingsDiagnostics = .unavailable) {
        self.store = store
        self.trackingEnabled = isTrackingEnabled
        self.onChange = onChange
        self.onTrackingChanged = onTrackingChanged
        self.onRevealDataFolder = revealDataFolder
        self.diagnostics = diagnostics
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

    var defaultAppTab: AppTab {
        get { AppTab(rawValue: store.defaultAppTabRawValue) ?? .focus }
        set { write { store.defaultAppTabRawValue = newValue.rawValue } }
    }

    var interfaceDensity: InterfaceDensity {
        get { InterfaceDensity(rawValue: store.interfaceDensityRawValue) ?? .comfortable }
        set { write { store.interfaceDensityRawValue = newValue.rawValue } }
    }

    var appearancePreference: AppearancePreference {
        get { AppearancePreference(rawValue: store.appearanceRawValue) ?? .system }
        set { write { store.appearanceRawValue = newValue.rawValue } }
    }

    var showsTimelineLabels: Bool {
        get { store.showsTimelineLabels }
        set { write { store.showsTimelineLabels = newValue } }
    }

    /// Nil deliberately means System; forcing the current system value would
    /// stop the app following an appearance change while it remains open.
    var preferredColorScheme: ColorScheme? {
        switch appearancePreference {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var interfaceLayout: InterfaceDensity.Layout { interfaceDensity.layout }

    var dataDirectoryURL: URL { SessionArchive.defaultDirectory }

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

}
