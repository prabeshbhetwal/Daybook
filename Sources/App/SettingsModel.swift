import ServiceManagement
import SwiftUI
import AppKit

/// Exhaustive identifiers for rows that can mutate behaviour. Each case maps
/// to one real SettingsModel property below; section metadata reuses these keys
/// so search/navigation cannot advertise a control with no backing behaviour.
enum SettingsControlKey: String, CaseIterable, Hashable {
    case opensOn
    case dailyGoal
    case categories
    case breakThreshold
    case longAwayCap
    case fullPromptAfter
    case reminders
    case automaticSessions
    case activityRuleAutomation
    case activityRules
    case automaticGap
    case rewards
    case sessionsPerApp
    case usageRecording
    case appearance
    case density
    case timelineLabels
    case entryDetails
    case idlePause
    case streakMinimum
    case minimumSession
    case continueWindow
    case defaultCategory
    case openAtLogin
    case menuBarTime
    case railApps
    case paceWindow
    case suggestionWindow
    case breakTiers
    case quietFold

    var modelKeyPath: PartialKeyPath<SettingsModel> {
        switch self {
        case .opensOn: return \SettingsModel.defaultStoryScope
        case .dailyGoal: return \SettingsModel.dailyGoal
        case .categories: return \SettingsModel.workTypeDefinitions
        case .breakThreshold: return \SettingsModel.breakThreshold
        case .longAwayCap: return \SettingsModel.longAwayCap
        case .fullPromptAfter: return \SettingsModel.fullPromptAfter
        case .reminders: return \SettingsModel.remindersEnabled
        case .automaticSessions: return \SettingsModel.autoSessionsEnabled
        case .activityRuleAutomation: return \SettingsModel.activityRuleAutomationEnabled
        case .activityRules: return \SettingsModel.activityRules
        case .automaticGap: return \SettingsModel.breakLength
        case .rewards: return \SettingsModel.rewardsEnabled
        case .sessionsPerApp: return \SettingsModel.menuSessionCount
        case .usageRecording: return \SettingsModel.isTrackingEnabled
        case .appearance: return \SettingsModel.appearancePreference
        case .density: return \SettingsModel.interfaceDensity
        case .timelineLabels: return \SettingsModel.showsTimelineLabels
        case .entryDetails: return \SettingsModel.expandsEntryDetails
        case .idlePause: return \SettingsModel.idlePauseThreshold
        case .streakMinimum: return \SettingsModel.streakMinimum
        case .minimumSession: return \SettingsModel.minimumRecordedSession
        case .continueWindow: return \SettingsModel.continueWindow
        case .defaultCategory: return \SettingsModel.defaultWorkType
        case .openAtLogin: return \SettingsModel.opensAtLogin
        case .menuBarTime: return \SettingsModel.menuBarShowsTime
        case .railApps: return \SettingsModel.railAppCount
        case .paceWindow: return \SettingsModel.paceWindowDays
        case .suggestionWindow: return \SettingsModel.suggestionWindowDays
        case .breakTiers: return \SettingsModel.enabledBreakTiers
        case .quietFold: return \SettingsModel.quietFold
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

    private static let accuracyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter
    }()

    static func accuracyEpochLabel(_ date: Date) -> String {
        accuracyDateFormatter.string(from: date)
    }
}

/// Explicitly separates passive app-usage observation from text the user
/// chooses to enter into FocusContinuity. A single disclosure feeds both
/// Tracking and Data so those surfaces cannot drift into contradictory claims.
struct SettingsPrivacyDisclosure {
    enum FocusInput: Hashable {
        case sessionName
        case intent
    }

    let appUsageMonitoringCapturesTextInOtherApps: Bool
    let locallyStoredFocusInputs: Set<FocusInput>

    static let current = SettingsPrivacyDisclosure(
        appUsageMonitoringCapturesTextInOtherApps: false,
        locallyStoredFocusInputs: [.sessionName, .intent])

    var appUsageDetail: String {
        "App-usage monitoring does not capture text in other apps. It stores app names, "
        + "bundle identifiers and activity times locally."
    }

    var storageDetail: String {
        appUsageDetail
        + " Session names and intent entered into FocusContinuity are stored locally."
    }
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
    private let onAppearanceChanged: (AppearancePreference) -> Void
    private let onActivityRulesChanged: () -> Void
    private let onRevealDataFolder: (() -> Void)?
    private let onReplayWelcome: (() -> Void)?
    private let openDataFolder: ((URL) -> Bool)?
    let diagnostics: SettingsDiagnostics
    /// The archive directory displayed and revealed by Privacy. Fixtures pass
    /// their own temporary directory so this surface cannot reach live data.
    let dataDirectoryURL: URL
    /// Mirrored here because the tracker — not the preference — is the truth
    /// about whether recording is on, and the tracker lives with the store.
    private var trackingEnabled: Bool
    let installedAppCatalog: InstalledAppCatalog

    init(store: PersistenceStore,
         isTrackingEnabled: Bool,
         onChange: @escaping () -> Void,
         onTrackingChanged: @escaping (Bool) -> Void,
         onAppearanceChanged: @escaping (AppearancePreference) -> Void = { _ in },
         onActivityRulesChanged: @escaping () -> Void = {},
         revealDataFolder: (() -> Void)? = nil,
         replayWelcome: (() -> Void)? = nil,
         diagnostics: SettingsDiagnostics = .unavailable,
         dataDirectory: URL = SessionArchive.defaultDirectory,
         openDataFolder: ((URL) -> Bool)? = nil,
         installedAppCatalog: InstalledAppCatalog = InstalledAppCatalog()) {
        self.store = store
        self.trackingEnabled = isTrackingEnabled
        self.onChange = onChange
        self.onTrackingChanged = onTrackingChanged
        self.onAppearanceChanged = onAppearanceChanged
        self.onActivityRulesChanged = onActivityRulesChanged
        self.onRevealDataFolder = revealDataFolder
        self.onReplayWelcome = replayWelcome
        self.openDataFolder = openDataFolder
        self.diagnostics = diagnostics
        self.dataDirectoryURL = dataDirectory
        self.installedAppCatalog = installedAppCatalog
    }

    /// Whether the welcome can be shown again. Absent outside the running
    /// application, so the row is never offered where it could do nothing.
    var canReplayWelcome: Bool { onReplayWelcome != nil }

    /// Run the welcome again. It is the app's only explanation of itself, and
    /// a one-off that cannot be recovered is a manual nobody can reopen.
    func replayWelcome() {
        onReplayWelcome?()
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
        set {
            write { store.autoSessionsEnabled = newValue }
            onActivityRulesChanged()
        }
    }

    var activityRuleAutomationEnabled: Bool {
        get { store.activityRuleAutomationEnabled }
        set {
            write { store.activityRuleAutomationEnabled = newValue }
            onActivityRulesChanged()
        }
    }

    /// The user's half of the category catalogue. Writing it re-resolves every
    /// category name, icon and colour in the app.
    var workTypeDefinitions: [WorkTypeDefinition] {
        get { store.workTypeDefinitions }
        set { write { store.workTypeDefinitions = newValue } }
    }

    /// Keeps one entry per category: an edited built-in or a made category is
    /// replaced in place, a new one is appended.
    func saveCategory(_ definition: WorkTypeDefinition) {
        var definitions = workTypeDefinitions
        if let index = definitions.firstIndex(where: { $0.id == definition.id }) {
            definitions[index] = definition
        } else {
            definitions.append(definition)
        }
        workTypeDefinitions = definitions
    }

    /// A made category leaves every picker but keeps describing its records.
    /// Retires or restores any category but Break. The last startable
    /// category cannot go: a session has to be filed somewhere.
    func setCategoryRetired(id: String, _ retired: Bool) {
        let type = WorkType(rawValue: id)
        guard type != .breakTime else { return }
        if retired, WorkType.startable.filter({ $0 != type }).isEmpty { return }
        var definitions = workTypeDefinitions
        if let index = definitions.firstIndex(where: { $0.id == id }) {
            definitions[index].isRetired = retired
        } else if var base = WorkTypeCatalog.builtInDefinitions.first(where: { $0.id == id }) {
            base.isRetired = retired
            definitions.append(base)
        } else { return }
        workTypeDefinitions = definitions
    }

    /// Drops the edit to a built-in, returning it to its shipped name, icon
    /// and colour.
    func resetCategory(id: String) {
        guard WorkType(rawValue: id).isBuiltIn else { return }
        workTypeDefinitions = workTypeDefinitions.filter { $0.id != id }
    }

    var activityRules: [ActivityRule] {
        get { store.activityRules }
        set {
            write { store.activityRules = newValue }
            onActivityRulesChanged()
        }
    }

    func saveActivityRule(_ rule: ActivityRule) {
        var rules = activityRules
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule }
        else { rules.append(rule) }
        activityRules = rules
    }

    func removeActivityRule(id: UUID) {
        activityRules = activityRules.filter { $0.id != id }
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

    var idlePauseThreshold: TimeInterval {
        get { store.idlePauseThreshold }
        set { write { store.idlePauseThreshold = newValue } }
    }

    var streakMinimum: TimeInterval {
        get { store.streakMinimum }
        set { write { store.streakMinimum = newValue } }
    }

    var minimumRecordedSession: TimeInterval {
        get { store.minimumRecordedSession }
        set { write { store.minimumRecordedSession = newValue } }
    }

    var continueWindow: TimeInterval {
        get { store.continueWindow }
        set { write { store.continueWindow = newValue } }
    }

    var defaultWorkType: WorkType {
        get { store.defaultWorkType }
        set { write { store.defaultWorkType = newValue } }
    }

    /// Registered with the system, not stored here: launchd is the truth.
    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
            }
        }
    }
    @Published var loginItemError: String?

    var menuBarShowsTime: Bool {
        get { store.menuBarShowsTime }
        set { write { store.menuBarShowsTime = newValue } }
    }

    var railAppCount: Int {
        get { store.menuAppCount }
        set { write { store.menuAppCount = newValue } }
    }

    var paceWindowDays: Int {
        get { store.paceWindowDays }
        set { write { store.paceWindowDays = newValue } }
    }

    var suggestionWindowDays: Int {
        get { store.suggestionWindowDays }
        set { write { store.suggestionWindowDays = newValue } }
    }

    var enabledBreakTiers: Set<BreakTier> {
        get { store.enabledBreakTiers }
        set { write { store.enabledBreakTiers = newValue } }
    }

    var quietFold: Int {
        get { store.quietFold }
        set { write { store.quietFold = newValue } }
    }

    var defaultAppTab: AppTab {
        get { AppTab(rawValue: store.defaultAppTabRawValue) ?? .focus }
        set { write { store.defaultAppTabRawValue = newValue.rawValue } }
    }

    /// Which story the window opens on. The window is the story, so this is the
    /// launch preference the interface can actually honour.
    var defaultStoryScope: StoryScope {
        get { StoryScope(rawValue: store.defaultStoryScopeRawValue) ?? .day }
        set { write { store.defaultStoryScopeRawValue = newValue.rawValue } }
    }

    /// Whether a session entry opens with its detail already showing. Local
    /// reading preference: it changes how the story is first drawn, never what
    /// it says.
    var expandsEntryDetails: Bool {
        get { store.expandsEntryDetails }
        set { write { store.expandsEntryDetails = newValue } }
    }

    /// How the rail's tiles are arranged. Stored as names so the order
    /// survives a release that adds or removes a tile.
    var storyTileOrder: [StoryTileKind] {
        get { StoryTileKind.order(from: store.storyTileOrderRawValue) }
        set { write { store.storyTileOrderRawValue = StoryTileKind.raw(from: newValue) } }
    }

    /// Presentation preference for the in-window session strip. This setter
    /// performs only the ordinary settings write; session actions remain owned
    /// by SessionStore and cannot be triggered by pinning.
    var sessionControlsPinned: Bool {
        get { store.sessionControlsPinned }
        set { write { store.sessionControlsPinned = newValue } }
    }

    var interfaceDensity: InterfaceDensity {
        get { InterfaceDensity(rawValue: store.interfaceDensityRawValue) ?? .comfortable }
        set { write { store.interfaceDensityRawValue = newValue.rawValue } }
    }

    var appearancePreference: AppearancePreference {
        get { AppearancePreference(rawValue: store.appearanceRawValue) ?? .system }
        set {
            write { store.appearanceRawValue = newValue.rawValue }
            onAppearanceChanged(newValue)
        }
    }

    var showsTimelineLabels: Bool {
        get { store.showsTimelineLabels }
        set { write { store.showsTimelineLabels = newValue } }
    }

    var interfaceLayout: InterfaceDensity.Layout { interfaceDensity.layout }

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
        } else if let openDataFolder {
            Self.revealDataFolder(at: dataDirectoryURL, open: openDataFolder)
        } else {
            Self.revealDataFolder(at: dataDirectoryURL)
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
