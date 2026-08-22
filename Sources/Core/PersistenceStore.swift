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
        static let menuSessions = "fc.menuSessions"
        static let menuApps = "fc.menuApps"
        static let trackingDisabled = "fc.trackingDisabled"
        static let remindersDisabled = "fc.remindersDisabled"
        static let workInterval = "fc.workInterval"
        static let breakLength = "fc.breakLength"
        static let lastBreakNotice = "fc.lastBreakNotice"
        static let lastBreakTier = "fc.lastBreakTier"
        static let longAwayCap = "fc.longAwayCap"
        static let period = "fc.period"
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

    var sessionName: String {
        get { defaults.string(forKey: Key.name) ?? "" }
        set { defaults.set(newValue, forKey: Key.name) }
    }

    /// How many recent sessions each app shows in the menu bar. Settable in
    /// Settings; a missing key means the default rather than zero.
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

    /// Used by the self-test harness to leave no residue behind.
    func removeAll() {
        for key in [Key.state, Key.overrides, Key.threshold, Key.name,
                    Key.menuSessions, Key.menuApps, Key.trackingDisabled,
                    Key.purposeOverrides, Key.dailyGoal, Key.autoSessions,
                    Key.rewardsEnabled, Key.rewardLog, Key.learning, Key.logGrouping,
                    Key.remindersDisabled, Key.workInterval, Key.breakLength,
                    Key.lastBreakNotice, Key.lastBreakTier, Key.longAwayCap,
                    Key.period] {
            defaults.removeObject(forKey: key)
        }
    }
}
