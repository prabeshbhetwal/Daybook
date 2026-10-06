import Foundation

/// Codable wrapper over `UserDefaults` (C7). Holds the live session snapshot,
/// category overrides, threshold and the active session name.
/// Session history lives in `SessionArchive`, not here.
final class PersistenceStore {

    private enum Key {
        static let state = "fc.state"
        static let overrides = "fc.overrides"
        static let purposeOverrides = "fc.purposeOverrides"
        static let dailyGoal = "fc.dailyGoal"
        static let autoSessions = "fc.autoSessions"
        static let rewardsEnabled = "fc.rewardsEnabled"
        static let rewardLog = "fc.rewardLog"
        static let learning = "fc.learning"
        static let logGrouping = "fc.logGrouping"
        static let threshold = "fc.threshold"
        static let name = "fc.name"
        static let recentActivities = "fc.recentActivities"
        static let menuSessions = "fc.menuSessions"
        static let menuApps = "fc.menuApps"
        static let trackingDisabled = "fc.trackingDisabled"
        static let remindersDisabled = "fc.remindersDisabled"
        static let workInterval = "fc.workInterval"
        static let breakLength = "fc.breakLength"
        static let lastBreakNotice = "fc.lastBreakNotice"
        static let lastBreakTier = "fc.lastBreakTier"
        static let longAwayCap = "fc.longAwayCap"
        static let fullPromptAfter = "fc.fullPromptAfter"
        static let period = "fc.period"
        static let defaultAppTabRawValue = "fc.defaultAppTab"
        /// No longer read: the window always opens on the day. Kept so erasing
        /// all data still clears a value an earlier version saved.
        static let storyTileOrderRawValue = "fc.storyTileOrder"
        static let expandsEntryDetails = "fc.expandsEntryDetails"
        static let interfaceDensityRawValue = "fc.interfaceDensity"
        static let appearanceRawValue = "fc.appearancePreference"
        static let showsTimelineLabels = "fc.showsTimelineLabels"
        static let pendingPowerObservations = "fc.pendingPowerObservations"
        static let pendingPowerTransfers = "fc.pendingPowerTransfers"
        static let pendingPowerMetadataError = "fc.pendingPowerMetadataError"
        static let activityRules = "fc.activityRules"
        static let activityRuleAutomationEnabled = "fc.activityRuleAutomationEnabled"
        static let activityRuleVersion = "fc.activityRuleVersion"
        static let automaticActivityRecord = "fc.automaticActivityRecord"
        static let activityRuleCooldownUntil = "fc.activityRuleCooldownUntil"
        static let workTypes = "fc.workTypes"
        static let savedActivities = "fc.savedActivities"
        static let categoryChoices = "fc.categoryChoices"
        static let idlePauseThreshold = "fc.idlePauseThreshold"
        static let streakMinimum = "fc.streakMinimum"
        static let minimumRecordedSession = "fc.minimumRecordedSession"
        static let continueWindow = "fc.continueWindow"
        static let defaultWorkType = "fc.defaultWorkType"
        static let menuBarShowsTime = "fc.menuBarShowsTime"
        static let showsMenuBarIcon = "fc.showsMenuBarIcon"
        static let dockIconMode = "fc.dockIconMode"
        static let paceWindowDays = "fc.paceWindowDays"
        static let suggestionWindowDays = "fc.suggestionWindowDays"
        static let breakTiersDisabled = "fc.breakTiersDisabled"
        static let quietFold = "fc.quietFold"
        static let nameCategoryKept = "fc.nameCategoryKept"
        static let onboarded = "fc.onboarded"
        static let welcomeLeftAt = "fc.welcomeLeftAt"
        static let globalShortcut = "fc.globalShortcut"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // The catalogue is process-wide and this store is its only writer, so
        // a new store installs what it holds — including nothing, which puts
        // every built-in back to its default.
        WorkTypeCatalog.shared.apply(customisations: workTypeDefinitions)
    }

    // MARK: - First run

    /// Whether the welcome has been answered — read through, stepped past or
    /// skipped. Absent means this Mac has never met the app.
    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    /// The chapter a welcome was on when the app last stopped mid-tour. Kept
    /// while the tour runs and cleared when it ends however it ends, so it is
    /// only ever present for a tour that was interrupted, by a quit or a crash.
    var welcomeLeftAt: FirstRunChapter? {
        get { defaults.string(forKey: Key.welcomeLeftAt).flatMap(FirstRunChapter.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.welcomeLeftAt) }
    }

    // MARK: - Learned category choices

    /// The last few categories chosen when a session was started with each
    /// app in front, newest last. What the app suggests next time it sees
    /// that app, ahead of its fixed guesses.
    var categoryChoices: [String: [String]] {
        get { storedDictionary(Key.categoryChoices) }
        set {
            if newValue.isEmpty { defaults.removeObject(forKey: Key.categoryChoices) }
            else { defaults.set(newValue, forKey: Key.categoryChoices) }
        }
    }

    static let categoryChoiceMemory = 3

    func rememberCategoryChoice(_ workType: WorkType, for bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty, workType.countsAsFocus else { return }
        var choices = categoryChoices
        var recent = choices[bundleID] ?? []
        recent.append(workType.rawValue)
        choices[bundleID] = Array(recent.suffix(PersistenceStore.categoryChoiceMemory))
        categoryChoices = choices
    }

    // MARK: - Saved activities

    /// The user's pinned activities, in their order.
    var savedActivities: [SavedActivity] {
        get {
            guard let decoded = decode([SavedActivity].self, forKey: Key.savedActivities) else { return [] }
            return SavedActivities.normalised(decoded)
        }
        set {
            let normalised = SavedActivities.normalised(newValue)
            if normalised.isEmpty {
                defaults.removeObject(forKey: Key.savedActivities)
            } else if let data = try? encoder.encode(normalised) {
                defaults.set(data, forKey: Key.savedActivities)
            }
        }
    }

    // MARK: - Categories

    /// The user's half of the category catalogue: edits to built-ins, stored
    /// under the built-in's identifier, and the categories they made. Writing
    /// here is what changes what every surface shows.
    var workTypeDefinitions: [WorkTypeDefinition] {
        get {
            guard let decoded = decode([WorkTypeDefinition].self, forKey: Key.workTypes) else { return [] }
            return decoded
        }
        set {
            var seen = Set<String>()
            let normalised = newValue.filter { seen.insert($0.id).inserted }
            if normalised.isEmpty {
                defaults.removeObject(forKey: Key.workTypes)
            } else if let data = try? encoder.encode(normalised) {
                defaults.set(data, forKey: Key.workTypes)
            }
            WorkTypeCatalog.shared.apply(customisations: normalised)
        }
    }

    // MARK: - Live state

    func loadState() -> PersistedState? {
        guard let data = defaults.data(forKey: Key.state) else { return nil }
        do {
            return try decoder.decode(PersistedState.self, from: data)
        } catch {
            setAside(data, forKey: Key.state, "\(error)")
            return nil
        }
    }

    func saveState(_ state: PersistedState) {
        do {
            defaults.set(try encoder.encode(state), forKey: Key.state)
        } catch {
            Diagnostics.log("failed to persist state: \(error)")
        }
    }

    var pendingPowerObservations: [PendingPowerObservation] {
        get {
            decode([PendingPowerObservation].self, forKey: Key.pendingPowerObservations) ?? []
        }
        set {
            guard !newValue.isEmpty else {
                defaults.removeObject(forKey: Key.pendingPowerObservations)
                return
            }
            if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Key.pendingPowerObservations)
            }
        }
    }

    var pendingPowerTransfers: [PendingPowerTransfer] {
        get {
            decode([PendingPowerTransfer].self, forKey: Key.pendingPowerTransfers) ?? []
        }
        set {
            guard !newValue.isEmpty else {
                defaults.removeObject(forKey: Key.pendingPowerTransfers)
                return
            }
            if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Key.pendingPowerTransfers)
            }
        }
    }

    var pendingPowerMetadataError: String? {
        get { defaults.string(forKey: Key.pendingPowerMetadataError) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.pendingPowerMetadataError) }
            else { defaults.removeObject(forKey: Key.pendingPowerMetadataError) }
        }
    }

    /// A bounded recent-name list survives short sessions and relaunches. It
    /// stores only names the user submitted, never an unfinished text draft.
    var recentActivities: [QuickStart] {
        guard let items = decode([QuickStart].self, forKey: Key.recentActivities) else { return [] }
        return ActivityChoices.merging(items, [])
    }

    func rememberActivity(name: String, workType: WorkType) {
        let updated = ActivityChoices.merging(
            [QuickStart(id: "", name: name, workType: workType)], recentActivities)
        guard let data = try? encoder.encode(updated) else { return }
        defaults.set(data, forKey: Key.recentActivities)
    }

    // MARK: - Category overrides (D4)

    /// Bundle ID → `AppPurpose.rawValue`. Separate from `overrides`, which is
    /// the auto-pause category: one answers "what is this app", the other
    /// "should it pause me", and a single dictionary could not express both.
    /// Focused seconds targeted per day.
    var dailyGoal: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.dailyGoal)
            return stored > 0 ? stored : FocusConstants.defaultDailyGoal
        }
        set { defaults.set(max(600, newValue), forKey: Key.dailyGoal) }
    }

    /// Both default on. `object(forKey:)` distinguishes "never set" from "off",
    /// which `bool(forKey:)` alone cannot.
    var autoSessionsEnabled: Bool {
        get { defaults.object(forKey: Key.autoSessions) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoSessions) }
    }

    var activityRules: [ActivityRule] {
        get {
            guard let decoded = decode([ActivityRule].self, forKey: Key.activityRules) else { return [] }
            var seen = Set<UUID>()
            return decoded.filter { seen.insert($0.id).inserted }
        }
        set {
            var seen = Set<UUID>()
            let normalised = newValue.compactMap { rule -> ActivityRule? in
                guard seen.insert(rule.id).inserted else { return nil }
                return ActivityRule(id: rule.id, name: rule.name, workType: rule.workType,
                    bundleIDs: rule.bundleIDs, isEnabled: rule.isEnabled,
                    startAfter: rule.startAfter)
            }
            guard let data = try? encoder.encode(normalised) else { return }
            defaults.set(data, forKey: Key.activityRules)
            bumpActivityRuleVersion()
        }
    }

    var activityRuleAutomationEnabled: Bool {
        get { defaults.bool(forKey: Key.activityRuleAutomationEnabled) }
        set {
            guard newValue != activityRuleAutomationEnabled else { return }
            defaults.set(newValue, forKey: Key.activityRuleAutomationEnabled)
            bumpActivityRuleVersion()
        }
    }

    var activityRuleVersion: UInt64 {
        UInt64(max(0, defaults.integer(forKey: Key.activityRuleVersion)))
    }

    private func bumpActivityRuleVersion() {
        defaults.set(Int(min(UInt64(Int.max), activityRuleVersion &+ 1)),
                     forKey: Key.activityRuleVersion)
    }

    var automationMode: AutomationMode {
        activityRuleAutomationEnabled ? .activityRules
            : (autoSessionsEnabled ? .legacyHeuristic : .off)
    }

    var automaticActivityRecord: AutomaticActivityRecord? {
        get {
            decode(AutomaticActivityRecord.self, forKey: Key.automaticActivityRecord)
        }
        set {
            if let newValue, let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Key.automaticActivityRecord)
            } else {
                defaults.removeObject(forKey: Key.automaticActivityRecord)
            }
        }
    }

    var activityRuleCooldownUntil: Date? {
        get { defaults.object(forKey: Key.activityRuleCooldownUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.activityRuleCooldownUntil) }
    }

    var rewardsEnabled: Bool {
        get { defaults.object(forKey: Key.rewardsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.rewardsEnabled) }
    }

    /// `RewardKind.rawValue` → when it last fired. Persisted so a relaunch
    /// cannot reset the app into repeating itself.
    var rewardLog: [String: Date] {
        get { storedDictionary(Key.rewardLog) }
        set { defaults.set(newValue, forKey: Key.rewardLog) }
    }

    /// What the app has learned about its own guesses, per app. JSON rather
    /// than a plist dictionary because the value is a struct, and encoding it
    /// keeps the shape in one place.
    /// Grouped by app by default: the chronological list made the reader scroll
    /// and add up ten rows to answer "how long was I in this app".
    var logGrouping: LogGrouping {
        get {
            (defaults.string(forKey: Key.logGrouping)).flatMap(LogGrouping.init) ?? .byApp
        }
        set { defaults.set(newValue.rawValue, forKey: Key.logGrouping) }
    }

    var autoStartLearning: [String: LearnedSignal] {
        get {
            decode([String: LearnedSignal].self, forKey: Key.learning) ?? [:]
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.learning)
        }
    }

    var purposeOverrides: [String: String] {
        get { storedDictionary(Key.purposeOverrides) }
        set { defaults.set(newValue, forKey: Key.purposeOverrides) }
    }

    var overrides: [String: String] {
        get { storedDictionary(Key.overrides) }
        set { defaults.set(newValue, forKey: Key.overrides) }
    }

    // MARK: - Preferences

    var breakThreshold: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.threshold)
            guard stored > 0 else { return FocusConstants.defaultThreshold }
            return stored
        }
        set { defaults.set(newValue, forKey: Key.threshold) }
    }

    /// Past this, an absence ends the session instead of asking about it. A
    /// preference rather than a constant because the honest answer differs by
    /// life: a school run is not a night, and where one ends and the other
    /// begins is not something this app can know.
    var longAwayCap: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.longAwayCap)
            guard stored > 0 else { return FocusConstants.defaultLongAwayCap }
            return stored
        }
        set { defaults.set(newValue, forKey: Key.longAwayCap) }
    }

    /// Past this an absence is asked about on a blurred screen; under it, from
    /// the menu bar. Nil is Never — stored as 0 so it survives as a choice,
    /// while a missing key reads as the default.
    var fullPromptAfter: TimeInterval? {
        get {
            guard let stored = defaults.object(forKey: Key.fullPromptAfter) as? Double else {
                return FocusConstants.defaultFullPromptAfter
            }
            return stored > 0 ? stored : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.fullPromptAfter) }
    }

    var sessionName: String {
        get { defaults.string(forKey: Key.name) ?? "" }
        set { defaults.set(newValue, forKey: Key.name) }
    }

    /// How many newest grouped app sessions Today shows after an app is selected.
    /// The historical key name is retained for preference compatibility; a
    /// missing key means the default rather than zero.
    var menuSessionCount: Int {
        get {
            let stored = defaults.integer(forKey: Key.menuSessions)
            return stored > 0 ? stored : FocusConstants.defaultMenuSessions
        }
        set { defaults.set(max(1, newValue), forKey: Key.menuSessions) }
    }

    /// How many apps the menu bar lists.
    var menuAppCount: Int {
        get {
            let stored = defaults.integer(forKey: Key.menuApps)
            return stored > 0 ? stored : FocusConstants.defaultMenuApps
        }
        set { defaults.set(max(1, newValue), forKey: Key.menuApps) }
    }

    /// Background app-usage tracking. Defaults to on; stored inverted so that a
    /// missing key reads as enabled.
    var isUsageTrackingEnabled: Bool {
        get { !defaults.bool(forKey: Key.trackingDisabled) }
        set { defaults.set(!newValue, forKey: Key.trackingDisabled) }
    }

    /// Stored inverted so a missing key reads as enabled.
    var remindersEnabled: Bool {
        get { !defaults.bool(forKey: Key.remindersDisabled) }
        set { defaults.set(!newValue, forKey: Key.remindersDisabled) }
    }

    var workInterval: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.workInterval)
            return stored > 0 ? stored : FocusConstants.defaultWorkInterval
        }
        set { defaults.set(newValue, forKey: Key.workInterval) }
    }

    var breakLength: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.breakLength)
            return stored > 0 ? stored : FocusConstants.defaultBreakLength
        }
        set { defaults.set(newValue, forKey: Key.breakLength) }
    }

    /// Quiet at the keyboard for this long pauses a running session.
    var idlePauseThreshold: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.idlePauseThreshold)
            return stored > 0 ? stored : FocusConstants.idlePauseThreshold
        }
        set { defaults.set(newValue, forKey: Key.idlePauseThreshold) }
    }

    /// A day joins the streak once its focus reaches this.
    var streakMinimum: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.streakMinimum)
            return stored > 0 ? stored : FocusConstants.streakMinimum
        }
        set { defaults.set(newValue, forKey: Key.streakMinimum) }
    }

    /// Stretches shorter than this are never written.
    var minimumRecordedSession: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.minimumRecordedSession)
            return stored > 0 ? stored : FocusConstants.minimumRecordedSession
        }
        set { defaults.set(newValue, forKey: Key.minimumRecordedSession) }
    }

    /// How long after a session ends it is still offered to continue.
    var continueWindow: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.continueWindow)
            return stored > 0 ? stored : FocusConstants.continueWindow
        }
        set { defaults.set(newValue, forKey: Key.continueWindow) }
    }

    /// The chord that reaches the app from any other, or nil once turned
    /// off. Absent means the standard Control-Option-Space.
    var globalShortcut: GlobalShortcut? {
        get {
            guard defaults.object(forKey: Key.globalShortcut) != nil else { return .standard }
            return decode(GlobalShortcutPreference.self, forKey: Key.globalShortcut)?.shortcut
        }
        set {
            if let data = try? encoder.encode(GlobalShortcutPreference(shortcut: newValue)) {
                defaults.set(data, forKey: Key.globalShortcut)
            }
        }
    }

    /// Whether the menu bar shows the running time beside the ring.
    var menuBarShowsTime: Bool {
        get { defaults.object(forKey: Key.menuBarShowsTime) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.menuBarShowsTime) }
    }

    /// The scene reads this key directly so the status item comes and goes
    /// as it changes; it is published here so that read cannot drift.
    static let showsMenuBarIconKey = Key.showsMenuBarIcon

    var showsMenuBarIcon: Bool {
        get { defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showsMenuBarIcon) }
    }

    /// Stored raw so Core keeps no opinion on how the mode is shown.
    var dockIconModeRawValue: String {
        get { defaults.string(forKey: Key.dockIconMode) ?? DockIconMode.whileWindowOpen.rawValue }
        set { defaults.set(newValue, forKey: Key.dockIconMode) }
    }

    /// How many working days "your usual pace" compares today with.
    var paceWindowDays: Int {
        get {
            let stored = defaults.integer(forKey: Key.paceWindowDays)
            return stored > 0 ? stored : FocusConstants.goalMedianWindowDays
        }
        set { defaults.set(max(1, newValue), forKey: Key.paceWindowDays) }
    }

    /// How far back activity suggestions look.
    var suggestionWindowDays: Int {
        get {
            let stored = defaults.integer(forKey: Key.suggestionWindowDays)
            return stored > 0 ? stored : FocusConstants.quickStartWindowDays
        }
        set { defaults.set(max(1, newValue), forKey: Key.suggestionWindowDays) }
    }

    /// The break reminder tiers that are on. Stored as the ones turned off,
    /// so a build that adds a tier ships it on.
    var enabledBreakTiers: Set<BreakTier> {
        get {
            let off = Set((defaults.array(forKey: Key.breakTiersDisabled) as? [Int] ?? []).compactMap(BreakTier.init(rawValue:)))
            return Set(BreakTier.allCases).subtracting(off)
        }
        set {
            let off = Set(BreakTier.allCases).subtracting(newValue).map(\.rawValue).sorted()
            defaults.set(off, forKey: Key.breakTiersDisabled)
        }
    }

    /// Quiet timeline rows fold once a run reaches this many; 0 never folds.
    /// The tidy-up the reader chose to keep as it is, by its signature: the
    /// goal tile stops offering it until a new session or rule joins.
    var nameCategoryKept: String {
        get { defaults.string(forKey: Key.nameCategoryKept) ?? "" }
        set { defaults.set(newValue, forKey: Key.nameCategoryKept) }
    }

    var quietFold: Int {
        get {
            guard let stored = defaults.object(forKey: Key.quietFold) as? Int else { return FocusConstants.defaultQuietFold }
            return max(0, stored)
        }
        set { defaults.set(max(0, newValue), forKey: Key.quietFold) }
    }

    /// The category a fresh session starts under before you choose one.
    var defaultWorkType: WorkType {
        get {
            guard let raw = defaults.string(forKey: Key.defaultWorkType) else { return .fallbackStartable }
            let type = WorkType(rawValue: raw)
            return WorkType.startable.contains(type) ? type : .fallbackStartable
        }
        set { defaults.set(newValue.rawValue, forKey: Key.defaultWorkType) }
    }

    /// Persisted so quitting does not re-fire the nudge on next launch. The tier
    /// travels with the timestamp: without it, a relaunch after a fifty-minute
    /// nudge cannot tell whether the next one would be an escalation (fire now)
    /// or a repeat (stay quiet).
    var lastBreakNotice: BreakNotice? {
        get {
            let stored = defaults.double(forKey: Key.lastBreakNotice)
            guard stored > 0 else { return nil }
            // `defaults.integer` cannot distinguish "absent" from zero, and
            // zero is a valid tier — so the obvious `?? .ultradian` fallback
            // never fired for a record written before tiers existed. `object`
            // is what actually reports absence.
            let tier = (defaults.object(forKey: Key.lastBreakTier) as? Int)
                .flatMap(BreakTier.init(rawValue:)) ?? .ultradian
            return BreakNotice(tier: tier, at: Date(timeIntervalSince1970: stored))
        }
        set {
            defaults.set(newValue?.at.timeIntervalSince1970 ?? 0, forKey: Key.lastBreakNotice)
            defaults.set(newValue?.tier.rawValue ?? BreakTier.ultradian.rawValue,
                         forKey: Key.lastBreakTier)
        }
    }

    /// Day, Week or Month. Unrecognised or missing values read as Day.
    var trackingPeriod: TrackingPeriod {
        get {
            guard let raw = defaults.string(forKey: Key.period),
                  let period = TrackingPeriod(rawValue: raw) else { return .day }
            return period
        }
        set { defaults.set(newValue.rawValue, forKey: Key.period) }
    }

    // MARK: - Window and UI preferences

    /// Stored as raw values so Core does not depend on navigation enums.
    var defaultAppTabRawValue: String {
        get { defaults.string(forKey: Key.defaultAppTabRawValue) ?? "focus" }
        set { defaults.set(newValue, forKey: Key.defaultAppTabRawValue) }
    }


    var storyTileOrderRawValue: String {
        get { defaults.string(forKey: Key.storyTileOrderRawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.storyTileOrderRawValue) }
    }

    var expandsEntryDetails: Bool {
        get { defaults.bool(forKey: Key.expandsEntryDetails) }
        set { defaults.set(newValue, forKey: Key.expandsEntryDetails) }
    }

    /// Stored as raw values so Core does not depend on UI density enums.
    var interfaceDensityRawValue: String {
        get { defaults.string(forKey: Key.interfaceDensityRawValue) ?? "comfortable" }
        set { defaults.set(newValue, forKey: Key.interfaceDensityRawValue) }
    }

    /// Stored as raw values so Core does not depend on appearance enums.
    var appearanceRawValue: String {
        get { defaults.string(forKey: Key.appearanceRawValue) ?? "system" }
        set { defaults.set(newValue, forKey: Key.appearanceRawValue) }
    }

    /// Whether day ribbons show per-app time ranges.
    var showsTimelineLabels: Bool {
        get {
            guard let value = defaults.object(forKey: Key.showsTimelineLabels) as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else { return true }
            return value.boolValue
        }
        set { defaults.set(newValue, forKey: Key.showsTimelineLabels) }
    }

    /// Decodes a stored value. Bytes this build cannot read are kept aside
    /// first: the caller falls back to a default, and its next save would
    /// otherwise write over the only copy.
    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            setAside(data, forKey: key, "\(error)")
            return nil
        }
    }

    /// A stored dictionary, or empty. A value of any other shape is kept aside
    /// first, for the same reason as `decode`.
    private func storedDictionary<Value>(_ key: String) -> [String: Value] {
        guard let object = defaults.object(forKey: key) else { return [:] }
        if let dictionary = object as? [String: Value] { return dictionary }
        setAside(object, forKey: key, "not a dictionary of \(Value.self)")
        return [:]
    }

    /// Moves an unreadable value to `<key>.unreadable.<time>`, once per value.
    /// With it kept, the key reads as absent, so later reads skip the failed
    /// decode and this scan.
    private func setAside(_ value: Any, forKey key: String, _ reason: String) {
        let prefix = key + ".unreadable."
        let stored = defaults.dictionaryRepresentation()
        let alreadyKept = stored.contains { $0.key.hasPrefix(prefix) && ($0.value as AnyObject).isEqual(value) }
        if !alreadyKept {
            var aside = prefix + String(Int(Date().timeIntervalSince1970))
            while stored[aside] != nil { aside += "+" }
            defaults.set(value, forKey: aside)
            Diagnostics.log("\(key) unreadable, kept as \(aside): \(reason)")
        }
        defaults.removeObject(forKey: key)
    }

    /// Every preference this app stores, for a backup: its own `fc.` keys and
    /// nothing from the shared global domain.
    var backupSnapshot: [String: Any] {
        defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("fc.") }
    }

    /// Used by the self-test harness to leave no residue behind.
    func removeAll() {
        let keys = [Key.state, Key.overrides, Key.threshold, Key.name,
                    Key.menuSessions, Key.menuApps, Key.trackingDisabled,
                    Key.purposeOverrides, Key.dailyGoal, Key.autoSessions,
                    Key.rewardsEnabled, Key.rewardLog, Key.learning, Key.logGrouping,
                    Key.remindersDisabled, Key.workInterval, Key.breakLength,
                    Key.lastBreakNotice, Key.lastBreakTier, Key.longAwayCap,
                    Key.fullPromptAfter, Key.period, Key.defaultAppTabRawValue,
                    Key.storyTileOrderRawValue,
                    Key.expandsEntryDetails,
                    Key.interfaceDensityRawValue, Key.appearanceRawValue,
                    Key.showsTimelineLabels, Key.pendingPowerObservations,
                    Key.pendingPowerTransfers,
                    Key.pendingPowerMetadataError, Key.activityRules,
                    Key.activityRuleAutomationEnabled, Key.activityRuleVersion,
                    Key.automaticActivityRecord, Key.activityRuleCooldownUntil,
                    Key.workTypes, Key.savedActivities, Key.categoryChoices,
                    Key.idlePauseThreshold, Key.streakMinimum, Key.minimumRecordedSession,
                    Key.continueWindow, Key.defaultWorkType, Key.menuBarShowsTime,
                    Key.showsMenuBarIcon, Key.dockIconMode, Key.nameCategoryKept,
                    Key.paceWindowDays, Key.suggestionWindowDays, Key.breakTiersDisabled,
                    Key.quietFold, Key.welcomeLeftAt, Key.globalShortcut]
        for key in keys { defaults.removeObject(forKey: key) }
        // And the unreadable values kept aside from those keys, but nothing else.
        for stored in defaults.dictionaryRepresentation().keys
        where keys.contains(where: { stored.hasPrefix($0 + ".unreadable.") }) {
            defaults.removeObject(forKey: stored)
        }
        WorkTypeCatalog.shared.apply(customisations: [])
    }
}
