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
        static let defaultStoryScopeRawValue = "fc.defaultStoryScope"
        static let sessionControlsPinned = "fc.sessionControlsPinned"
        static let storyTileOrderRawValue = "fc.storyTileOrder"
        static let expandsEntryDetails = "fc.expandsEntryDetails"
        static let interfaceDensityRawValue = "fc.interfaceDensity"
        static let appearanceRawValue = "fc.appearancePreference"
        static let showsTimelineLabels = "fc.showsTimelineLabels"
        static let pendingPowerObservations = "fc.pendingPowerObservations"
        static let pendingPowerTransfers = "fc.pendingPowerTransfers"
        static let pendingPowerMetadataError = "fc.pendingPowerMetadataError"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Live state

    func loadState() -> PersistedState? {
        guard let data = defaults.data(forKey: Key.state) else { return nil }
        do {
            return try decoder.decode(PersistedState.self, from: data)
        } catch {
            Diagnostics.log("discarding unreadable persisted state: \(error)")
            defaults.removeObject(forKey: Key.state)
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

    func clearState() {
        defaults.removeObject(forKey: Key.state)
    }

    var pendingPowerObservations: [PendingPowerObservation] {
        get {
            guard let data = defaults.data(forKey: Key.pendingPowerObservations),
                  let value = try? decoder.decode([PendingPowerObservation].self, from: data)
            else { return [] }
            return value
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
            guard let data = defaults.data(forKey: Key.pendingPowerTransfers),
                  let value = try? decoder.decode([PendingPowerTransfer].self, from: data)
            else { return [] }
            return value
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
        guard let data = defaults.data(forKey: Key.recentActivities),
              let items = try? decoder.decode([QuickStart].self, from: data) else { return [] }
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

    var rewardsEnabled: Bool {
        get { defaults.object(forKey: Key.rewardsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.rewardsEnabled) }
    }

    /// `RewardKind.rawValue` → when it last fired. Persisted so a relaunch
    /// cannot reset the app into repeating itself.
    var rewardLog: [String: Date] {
        get { defaults.dictionary(forKey: Key.rewardLog) as? [String: Date] ?? [:] }
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
            guard let data = defaults.data(forKey: Key.learning),
                  let decoded = try? JSONDecoder().decode([String: LearnedSignal].self,
                                                          from: data) else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.learning)
        }
    }

    var purposeOverrides: [String: String] {
        get { defaults.dictionary(forKey: Key.purposeOverrides) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.purposeOverrides) }
    }

    var overrides: [String: String] {
        get { defaults.dictionary(forKey: Key.overrides) as? [String: String] ?? [:] }
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

    var defaultStoryScopeRawValue: String {
        get { defaults.string(forKey: Key.defaultStoryScopeRawValue) ?? "day" }
        set { defaults.set(newValue, forKey: Key.defaultStoryScopeRawValue) }
    }

    /// Pinning controls only their presentation in the existing main window.
    /// It is deliberately stored beside other UI preferences and never read by
    /// SessionEngine, so relaunch cannot start, stop or otherwise mutate work.
    var sessionControlsPinned: Bool {
        get { defaults.bool(forKey: Key.sessionControlsPinned) }
        set { defaults.set(newValue, forKey: Key.sessionControlsPinned) }
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

    /// Used by the self-test harness to leave no residue behind.
    func removeAll() {
        for key in [Key.state, Key.overrides, Key.threshold, Key.name,
                    Key.menuSessions, Key.menuApps, Key.trackingDisabled,
                    Key.purposeOverrides, Key.dailyGoal, Key.autoSessions,
                    Key.rewardsEnabled, Key.rewardLog, Key.learning, Key.logGrouping,
                    Key.remindersDisabled, Key.workInterval, Key.breakLength,
                    Key.lastBreakNotice, Key.lastBreakTier, Key.longAwayCap,
                    Key.fullPromptAfter, Key.period, Key.defaultAppTabRawValue,
                    Key.defaultStoryScopeRawValue, Key.sessionControlsPinned,
                    Key.storyTileOrderRawValue,
                    Key.expandsEntryDetails,
                    Key.interfaceDensityRawValue, Key.appearanceRawValue,
                    Key.showsTimelineLabels, Key.pendingPowerObservations,
                    Key.pendingPowerTransfers,
                    Key.pendingPowerMetadataError] {
            defaults.removeObject(forKey: key)
        }
    }
}
