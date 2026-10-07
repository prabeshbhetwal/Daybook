import ServiceManagement
import SwiftUI
import AppKit
import UserNotifications
import Combine

/// Exhaustive identifiers for rows that can mutate behaviour. Each case maps
/// to one real SettingsModel property below; section metadata reuses these keys
/// so search/navigation cannot advertise a control with no backing behaviour.
enum SettingsControlKey: String, CaseIterable, Hashable {
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
    case menuBarIcon
    case dockIcon
    case updateChecks
    case updateFrequency
    case updateInstall
    case railApps
    case paceWindow
    case suggestionWindow
    case breakTiers
    case quietFold

    var modelKeyPath: PartialKeyPath<SettingsModel> {
        switch self {
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
        case .menuBarIcon: return \SettingsModel.showsMenuBarIcon
        case .dockIcon: return \SettingsModel.dockIconMode
        case .updateChecks: return \SettingsModel.checksForUpdatesAutomatically
        case .updateFrequency: return \SettingsModel.updateFrequency
        case .updateInstall: return \SettingsModel.updateInstallMode
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

    static func live(usage: AppUsageArchive, sessions: SessionArchive? = nil, bundle: Bundle = .main,
                     dataDirectory: URL = SessionArchive.defaultDirectory,
                     fileManager: FileManager = .default) -> SettingsDiagnostics {
        let backup = usage.legacyBackupURL
            ?? latestLegacyBackup(in: dataDirectory, fileManager: fileManager)
        var notes: [String] = []
        // Session history first: when it is missing, it is what the reader
        // notices, and the only explanation is here.
        if sessions?.isReadOnly == true {
            notes.append("Session history is read-only because sessions.json could not be read "
                + "or set aside. Its bytes are unchanged.")
        } else if let aside = latestSetAside(prefix: "sessions-corrupt-", in: dataDirectory,
                                             fileManager: fileManager) {
            notes.append("Session history that could not be read was set aside as "
                + "\(aside.lastPathComponent) and is not shown.")
        }
        if usage.isReadOnly {
            notes.append("App usage is read-only because its file could not be safely rewritten.")
        } else if backup != nil {
            notes.append("Older app use was upgraded only after a copy of the original file was kept.")
        }
        let recovery = notes.isEmpty ? "Nothing needed recovering." : notes.joined(separator: " ")
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
        latestSetAside(prefix: "app-usage-v1-backup-", in: directory, fileManager: fileManager)
    }

    /// The newest `<prefix><stamp>.json` beside the archive. A second file in
    /// the same second is `<prefix><stamp>-2.json`, and so on; any other name
    /// is not one of ours.
    private static func latestSetAside(prefix: String, in directory: URL,
                                       fileManager: FileManager) -> URL? {
        let suffix = ".json"
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return nil }
        return entries.compactMap { url -> (order: (Int, Int), url: URL)? in
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            guard name.hasPrefix(prefix), name.hasSuffix(suffix),
                  fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return nil }
            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -suffix.count)
            guard let order = setAsideOrder(name[start..<end]) else { return nil }
            return (order, url)
        }
        .max { $0.order < $1.order }?.url
    }

    /// `<stamp>`, or `<stamp>-<n>` with n from 2, as `UnreadableFile` names them.
    private static func setAsideOrder(_ stem: Substring) -> (Int, Int)? {
        if let stamp = Int(stem) { return (stamp, 1) }
        guard let dash = stem.lastIndex(of: "-"), let stamp = Int(stem[..<dash]),
              let ordinal = Int(stem[stem.index(after: dash)...]), ordinal > 1 else { return nil }
        return (stamp, ordinal)
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
/// chooses to enter into Daybook. A single disclosure feeds both
/// Tracking and Data so those surfaces cannot drift into contradictory claims.
struct SettingsPrivacyDisclosure {
    enum FocusInput: Hashable {
        case sessionName
        case intent
        case note
        case power
    }

    let appUsageMonitoringCapturesTextInOtherApps: Bool
    let locallyStoredFocusInputs: Set<FocusInput>

    static let current = SettingsPrivacyDisclosure(
        appUsageMonitoringCapturesTextInOtherApps: false,
        locallyStoredFocusInputs: [.sessionName, .intent, .note, .power])

    var appUsageDetail: String {
        "App-usage monitoring does not capture text in other apps. It stores app names, "
        + "bundle identifiers and activity times locally."
    }

    var storageDetail: String {
        appUsageDetail
        + " Session names, intent and notes entered into Daybook are stored locally,"
        + " with the power source, battery level, charging state and charger wattage"
        + " seen during each session. Two things reach a server: the update check,"
        + " which asks GitHub for the latest version and sends the app's own, and"
        + " dictation, which uses Apple's speech recognition and may send the audio"
        + " to Apple when this Mac cannot recognise your language itself."
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
    private let onPresenceChanged: () -> Void
    private let onActivityRulesChanged: () -> Void
    private let onRevealDataFolder: (() -> Void)?
    private let onReplayWelcome: (() -> Void)?
    private let onResumeWelcome: ((FirstRunChapter) -> Void)?
    private let openDataFolder: ((URL) -> Bool)?
    let diagnostics: SettingsDiagnostics
    /// The archive directory displayed and revealed by Privacy. Fixtures pass
    /// their own temporary directory so this surface cannot reach live data.
    let dataDirectoryURL: URL
    /// Where "Back up to iCloud Drive" writes. Checks pass a scratch folder.
    let backupRoot: URL
    /// What the last backup did, shown under its button.
    @Published private(set) var backupStatus: String?
    /// Mirrored here because the tracker — not the preference — is the truth
    /// about whether recording is on, and the tracker lives with the store.
    private var trackingEnabled: Bool
    /// Fills in the background after Activities opens. Its changes are
    /// republished as the model's own: the pages read it through the model,
    /// and unrepublished they kept dashed icons and bundle ids until
    /// something else redrew them.
    let installedAppCatalog: InstalledAppCatalog
    private var catalogChanges: AnyCancellable?

    init(store: PersistenceStore,
         isTrackingEnabled: Bool,
         onChange: @escaping () -> Void,
         onTrackingChanged: @escaping (Bool) -> Void,
         onAppearanceChanged: @escaping (AppearancePreference) -> Void = { _ in },
         onPresenceChanged: @escaping () -> Void = {},
         onActivityRulesChanged: @escaping () -> Void = {},
         revealDataFolder: (() -> Void)? = nil,
         replayWelcome: (() -> Void)? = nil,
         resumeWelcome: ((FirstRunChapter) -> Void)? = nil,
         diagnostics: SettingsDiagnostics = .unavailable,
         dataDirectory: URL = SessionArchive.defaultDirectory,
         openDataFolder: ((URL) -> Bool)? = nil,
         backupRoot: URL = DataBackup.iCloudDriveRoot,
         installedAppCatalog: InstalledAppCatalog = InstalledAppCatalog()) {
        self.store = store
        self.trackingEnabled = isTrackingEnabled
        self.onChange = onChange
        self.onTrackingChanged = onTrackingChanged
        self.onAppearanceChanged = onAppearanceChanged
        self.onPresenceChanged = onPresenceChanged
        self.onActivityRulesChanged = onActivityRulesChanged
        self.onRevealDataFolder = revealDataFolder
        self.onReplayWelcome = replayWelcome
        self.onResumeWelcome = resumeWelcome
        self.openDataFolder = openDataFolder
        self.diagnostics = diagnostics
        self.dataDirectoryURL = dataDirectory
        self.backupRoot = backupRoot
        self.installedAppCatalog = installedAppCatalog
        catalogChanges = installedAppCatalog.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Whether the welcome can be shown again. Absent outside the running
    /// application, so the row is never offered where it could do nothing.
    var canReplayWelcome: Bool { onReplayWelcome != nil }

    /// Run the welcome again. It is the app's only explanation of itself, and
    /// a one-off that cannot be recovered is a manual nobody can reopen.
    func replayWelcome() {
        onReplayWelcome?()
    }

    /// The chapter a tour was left on by a quit or a crash, if one was.
    var interruptedWelcomeChapter: FirstRunChapter? {
        onResumeWelcome == nil ? nil : store.welcomeLeftAt
    }

    /// Picks the tour up at the chapter it was left on.
    func resumeWelcome() {
        guard let chapter = interruptedWelcomeChapter else { return }
        onResumeWelcome?(chapter)
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

    /// Whether Control-Option-Space is working, as the coordinator's hot key
    /// reports it. Settings is the one place that says why it might not be.
    @Published var globalShortcutStatus: HotKeyMonitor.Status = .off
    /// Why the last recorded chord was not taken, until one is.
    @Published var globalShortcutMessage: String?
    /// The coordinator's hot key takes the chord; false when macOS refused it.
    var applyGlobalShortcut: ((GlobalShortcut?) -> Bool)?

    var globalShortcut: GlobalShortcut? { store.globalShortcut }

    /// Records a chord, or nil to turn the shortcut off. A chord that could
    /// not be global is refused here; one another app holds is refused by
    /// macOS through `applyGlobalShortcut`, and the one held is kept.
    func setGlobalShortcut(_ shortcut: GlobalShortcut?) {
        if let shortcut, let reason = GlobalShortcut.refusal(modifiers: shortcut.modifiers) {
            globalShortcutMessage = reason
            return
        }
        if let shortcut, let apply = applyGlobalShortcut, !apply(shortcut) {
            let kept = store.globalShortcut.map { "\($0.glyphs) is kept." } ?? "The shortcut stays off."
            globalShortcutMessage = "\(shortcut.glyphs) is taken by another app. \(kept)"
            return
        }
        if shortcut == nil { _ = applyGlobalShortcut?(nil) }
        globalShortcutMessage = nil
        write { store.globalShortcut = shortcut }
    }

    /// Registered, but macOS will not open the app at login until the user
    /// approves it. The switch reads off then, since that is the truth, and
    /// the page says where to approve it rather than flipping back silently.
    var loginItemNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// The user declined notifications for the app, so a break reminder shows
    /// on screen but never reaches Notification Centre.
    @Published private(set) var notificationsDenied = false

    /// Reads again what only System Settings changes: login-item approval and
    /// notification permission. Called when the page opens and whenever the
    /// app comes back to the front.
    func refreshSystemStatus() {
        objectWillChange.send()
        // Only an app bundle has a notification centre; asking from the bare
        // self-test binary raises instead of answering.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async {
                guard let self, self.notificationsDenied != denied else { return }
                self.notificationsDenied = denied
            }
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    var menuBarShowsTime: Bool {
        get { store.menuBarShowsTime }
        set { write { store.menuBarShowsTime = newValue } }
    }

    var showsMenuBarIcon: Bool {
        get { store.showsMenuBarIcon }
        set {
            write {
                store.showsMenuBarIcon = newValue
                // Hidden, the menu bar icon leaves the Dock as the only way
                // back in, so the picker says so rather than claim otherwise.
                if !newValue { store.dockIconModeRawValue = DockIconMode.always.rawValue }
            }
            onPresenceChanged()
        }
    }

    /// The updater, in the running app only: fixtures and the self-test
    /// leave it nil, and the Updates page then says updates are off here.
    var updater: (any UpdateControlling)? {
        didSet {
            updaterChanges = updater?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    private var updaterChanges: AnyCancellable?

    var checksForUpdatesAutomatically: Bool {
        get { updater?.automaticallyChecks ?? false }
        set { updater?.automaticallyChecks = newValue }
    }

    var updateFrequency: UpdateFrequency {
        get { updater?.frequency ?? .weekly }
        set { updater?.frequency = newValue }
    }

    var updateInstallMode: UpdateInstallMode {
        get { updater?.installMode ?? .askFirst }
        set { updater?.installMode = newValue }
    }

    var dockIconMode: DockIconMode {
        get { DockIconMode(rawValue: store.dockIconModeRawValue) ?? .whileWindowOpen }
        set {
            write { store.dockIconModeRawValue = newValue.rawValue }
            onPresenceChanged()
        }
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

    var interfaceDensity: InterfaceDensity {
        get { InterfaceDensity(rawValue: store.interfaceDensityRawValue) ?? .comfortable }
        set { write { store.interfaceDensityRawValue = newValue.rawValue } }
    }

    /// The interface zoom as a scale, 1.2 for 120%. A new value snaps to a
    /// step, is stored, and is handed to the one model every window reads.
    var interfaceZoom: Double {
        get { Double(store.interfaceZoomPercent) / 100 }
        set {
            let percent = InterfaceZoom.nearestPercent(toScale: newValue)
            write { store.interfaceZoomPercent = percent }
            ZoomModel.shared.apply(percent: percent)
        }
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

    /// Copies the data folder and preferences to a new dated folder in iCloud
    /// Drive. Only ever on request: the app otherwise keeps everything local.
    func backUpToICloudDrive(at date: Date = Date()) {
        do {
            let folder = try DataBackup.make(from: dataDirectoryURL, preferences: store.backupSnapshot,
                                             into: backupRoot, at: date)
            backupStatus = "Backed up to iCloud Drive › \(DataBackup.folderName) › \(folder.lastPathComponent)."
        } catch {
            backupStatus = error.localizedDescription
            Diagnostics.log("backup to iCloud Drive failed: \(error)")
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
