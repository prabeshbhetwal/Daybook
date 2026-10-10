import AppKit
import Combine
import SwiftUI

/// Lifecycle and the ownership graph. Owns the engine and every system monitor;
/// the SwiftUI scenes read state through `SessionStore`.
final class AppCoordinator: NSObject, NSApplicationDelegate {

    let engine: SessionEngine
    private let monitor = EventMonitor()
    private let notifier = Notifier()
    let usage = AppUsageArchive()
    private(set) lazy var tracker = AppUsageTracker(
        archive: usage,
        isEnabled: engine.store.isUsageTrackingEnabled)
    /// Readable so a surface can say why ⌃⌥Space does nothing: its `status`
    /// is published, and tells VoiceOver's claim on the chord apart from
    /// another app's.
    let hotKey = HotKeyMonitor()
    private let powerMonitor = PowerSourceMonitor()
    /// The engine is restored here, not in `applicationDidFinishLaunching`:
    /// SwiftUI draws the menu-bar label first, which builds the store, and the
    /// store's first refresh pruned metadata against an engine that was still
    /// idle. Every launch deleted the running session's power readings.
    private(set) lazy var store: SessionStore = {
        restoreEngineOnce()
        return SessionStore(engine: engine, powerMonitor: powerMonitor)
    }()
    private var engineRestored = false
    /// The status item's view of the store: republishes only what it shows.
    private(set) lazy var menuBarLabel = MenuBarLabelModel(store: store)
    /// The Session menu's view of the store, on the same terms.
    private(set) lazy var sessionCommandState = SessionCommandState(store: store)
    /// The Settings window's model. Writes go to the same preferences the
    /// engine reads; `onChange` refreshes every surface that shows them.
    private(set) lazy var settings = SettingsModel(
        store: engine.store,
        isTrackingEnabled: engine.store.isUsageTrackingEnabled,
        onChange: { [weak self] in self?.store.refresh() },
        onTrackingChanged: { [weak self] in self?.store.setTrackingEnabled($0) },
        onAppearanceChanged: { [weak self] in self?.applyApplicationAppearance($0) },
        onPresenceChanged: { [weak self] in self?.applyPresence() },
        onActivityRulesChanged: { [weak self] in self?.ruleConfigurationChanged() },
        // A method, not a closure that reads `mainWindow`, so the two lazy
        // properties never become each other's dependency.
        replayWelcome: { [weak self] in self?.replayWelcome() },
        resumeWelcome: { [weak self] chapter in self?.replayWelcome(from: chapter) },
        diagnostics: .live(usage: usage, sessions: engine.archive),
        installedAppCatalog: InstalledAppCatalog(observed: { [weak self] in
            guard let self else { return [] }
            var names: [String: String] = [:]
            for session in self.usage.sessions { names[session.bundleID] = session.appName }
            return names.map { InstalledApplication(bundleID: $0.key, name: $0.value,
                                                      url: nil, isInstalled: false) }
        }))
    /// One route object for the window, menu popover, commands and deep links.
    /// It always opens on the day's story.
    @MainActor private(set) lazy var mainWindow = MainWindowModel(opening: .story, store: store)

    /// The welcome. Always present so the window and the menu bar can observe
    /// it; it draws nothing until `begin()`. Whatever ends it — reading it
    /// through, stepping past or skipping — is written down as answered.
    private(set) lazy var firstRun = FirstRunCoach { [weak self] in
        self?.engine.store.hasOnboarded = true
        self?.engine.store.welcomeLeftAt = nil
        // Asked when the welcome ends rather than at launch, where the
        // system's prompt landed on the first card with nothing to say why.
        self?.notifier.requestAuthorization()
    }

    /// Opening the app again while it runs, from Finder, Spotlight or the
    /// Dock. The scene observes it: only SwiftUI can open its window.
    let reopenRequests = PassthroughSubject<Void, Never>()
    /// The updater starts with the first thing that asks for it (the menu's
    /// command, or launch) and only ever in the running app.
    private(set) lazy var updater = AppUpdater()
    private let backups = BackupScheduler()
    /// A second copy launched while this one runs asks it to come forward.
    private var secondLaunchObserver: NSObjectProtocol?
    /// SwiftUI's window actions, handed over by the scene. They live here, not
    /// in the menu bar icon's view, so they still work with the icon hidden.
    var windowOpener: WindowOpener?
    var windowRequests: Set<AnyCancellable> = []
    /// Whether the main window is open: shown, or minimised to the Dock.
    var mainWindowOpen = false {
        didSet { if mainWindowOpen != oldValue { applyPresence() } }
    }

    /// Input density, fed only at event boundaries — app activation, lock,
    /// unlock, wake — and never on a timer. A repeating timer would be the only
    /// polling in the app and would hold the process off App Nap for a signal
    /// that is consumed just once, when a stretch ends.
    let density = InputDensity()
    private let inputCounters = InputCounters()
    private let densityIdle = IdleMonitor()

    // MARK: - Automatic sessions and rewards

    private var detector = AutoSessionDetector(breakLength: FocusConstants.defaultBreakLength)
    private lazy var activityAutomation = ActivityAutomation(
        scheduler: MainActivityDeadlineScheduler(),
        input: { [weak self] in self?.activityRuleInput() ?? ActivityRuleInput.disabled },
        apply: { [weak self] result in
            Task { @MainActor in self?.applyActivityRuleResult(result) }
        })
    /// Lazy because `RewardHUD` is main-actor isolated and this delegate is
    /// not; every access below is already on the main thread.
    @MainActor private lazy var hud = RewardHUD()
    /// Holds the `--preview-away card` window so it is not released.
    @MainActor private var previewWindow: NSWindow?
    /// Whether the screen is locked, as the notifications have told us. A
    /// display waking behind a lock — a notification, a lid opened to a
    /// password field, a dark wake — is not the user back; the unlock is.
    private var screenLocked = false
    private var machineSleeping = false
    private var foregroundGeneration: UInt64 = 0
    /// Puts the away question where the user is. Lazy for the same reason as
    /// the HUD: main-actor isolated, first touched on the main thread.
    @MainActor private lazy var awayPrompter = AwayPrompter(
        store: store, fullPromptAfter: { [weak self] in self?.engine.store.fullPromptAfter })
    /// When the focused-app-plus-music combination began, or nil when it is not
    /// currently holding. Reset the moment either half stops being true.
    private var musicPairingSince: Date?
    /// The app whose behaviour justified the running automatic session. Kept so
    /// the outcome — kept or undone — can be credited to the right app.
    private var autoStartedFor: String?
    private var lastScoredApp: String?

    /// Set from the players' own distributed notifications. Both are broadcast
    /// publicly and need no permission; neither carries anything but playback
    /// state, which is all this reads.
    private var music = MusicPlayback()
    private var musicIsPlaying: Bool { music.isPlaying }

    private func observeMusicPlayback() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: Notification.Name(name), object: nil,
                               queue: .main) { [weak self] note in
                guard let self else { return }
                self.music.update(player: name, state: note.userInfo?["Player State"] as? String)
                if !self.music.isPlaying { self.musicPairingSince = nil }
            }
        }
    }

    /// Runs after every input sample, on the same event boundaries. No timer:
    /// the app's only repeating timer remains the one-second session ticker.
    /// The workspace notifications that drive this already arrive on the main
    /// thread, but their closures are not actor-isolated, so the hop is what
    /// tells the compiler what is already true.
    private func scheduleAutomation() {
        Task { @MainActor [weak self] in self?.evaluateAutomation() }
    }

    @MainActor private func evaluateAutomation() {
        // While a decision is pending the app has asked the user a question, and
        // must not answer it on their behalf by starting or ending sessions.
        // Everything else still runs: returning here outright also skipped the
        // flush below, so background recording stopped dead for as long as the
        // card went unanswered — the app reported "at the Mac 0m" through five
        // minutes of real use.
        let decisionPending: Bool
        if case .awaitingUserDecision = engine.state { decisionPending = true }
        else { decisionPending = false }

        tracker.flush()
        let moment = Date()
        // The store's view, not a second one: it is keyed on the revision the
        // flush just moved, so it is rebuilt now, once, and shared.
        let usageSnapshot = store.effectiveUsageSnapshot ?? AppUsageSnapshot(archive: usage, tracker: tracker)
        let window = (start: moment.addingTimeInterval(-FocusConstants.focusWindow),
                      end: moment)
        let score = FocusScorer(purposeOverrides: engine.store.purposeOverrides)
            .score(segments: usageSnapshot.sessions, activity: density.activity, window: window)

        // Rebuilt each pass so a break length changed in settings takes effect
        // rather than being frozen at whatever it was on first use.
        detector.breakLength = engine.store.breakLength
        // Learned per app: sessions the user keeps make the app quicker to
        // start for that app, sessions they undo make it slower.
        detector.startThreshold = PurposeLearner(signals: engine.store.autoStartLearning)
            .startThreshold(for: score.signals.dominantApp)

        if engine.store.automationMode == .activityRules {
            detector.reset()
            activityAutomation.observe(activityRuleInput(at: moment))
        } else {
            activityAutomation.cancel()
            store.presentActivityChoice(nil)
        }

        if engine.store.automationMode == .legacyHeuristic && !decisionPending {
            // `state != .idle` rather than `state.isRunning`: a session the
            // detector paused is still its session, and reporting it as gone
            // would make the detector discard the pause it is timing.
            lastScoredApp = score.signals.dominantApp
            let decision = detector.evaluate(score: score, at: moment,
                                             sessionRunning: engine.state != .idle,
                                             sessionWasAutoStarted: engine.activeIsAuto,
                                             enginePaused: engine.state.isPaused)
            apply(decision)
        } else if engine.store.automationMode != .activityRules {
            // Nothing evaluates while disabled or while a decision is pending,
            // so a qualifying run frozen at switch-off would fire the instant it
            // is switched back on, backdated arbitrarily far — in the pending
            // case, across the very gap the user is being asked about.
            detector.reset()
        }
        evaluateRewards(score: score, at: moment, usageSnapshot: usageSnapshot)
    }

    private func ruleConfigurationChanged() {
        activityAutomation.cancel()
        store.presentActivityChoice(nil)
        scheduleAutomation()
    }

    /// The unbroken recorded run ending now. Only the last day is merged: a
    /// record that ends before it can join the run only if the run reaches
    /// back that far, and then the whole history is merged instead. Merging
    /// all of it on every automation pass grew with uncapped history.
    static func recentCoverage(_ sessions: [AppUsageSession], endingAt moment: Date) -> DateInterval? {
        let horizon = moment.addingTimeInterval(-24 * 3_600)
        func intervals(_ from: [AppUsageSession]) -> [DateInterval] {
            from.map { DateInterval(start: $0.start, end: $0.end) }
        }
        let recent = ActivityAccounting.contiguousCoverage(
            intervals(sessions.filter { $0.end >= horizon }), endingAt: moment)
        guard let recent, recent.start <= horizon.addingTimeInterval(1) else { return recent }
        return ActivityAccounting.contiguousCoverage(intervals(sessions), endingAt: moment)
    }

    private func activityRuleInput(at moment: Date = Date()) -> ActivityRuleInput {
        let presence: ActivityPresence
        if screenLocked { presence = .locked }
        else if machineSleeping { presence = .sleeping }
        else if case .paused(reason: .away) = engine.state { presence = .away }
        else { presence = .present }
        let snapshot = store.effectiveUsageSnapshot ?? AppUsageSnapshot(archive: usage, tracker: tracker)
        let coverage = Self.recentCoverage(snapshot.sessions, endingAt: moment)
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let controlsAreForeground = frontmost == FocusConstants.bundleIdentifier
        let cooldownAllows = engine.store.activityRuleCooldownUntil.map { moment >= $0 } ?? true
        return ActivityRuleInput(timestamp: moment,
            foregroundBundleID: tracker.currentBundleID,
            foregroundIsActive: frontmost == tracker.currentBundleID,
            controlsAreForeground: controlsAreForeground,
            foregroundGeneration: foregroundGeneration,
            presence: presence, trackingEnabled: tracker.isEnabled,
            automationEnabled: engine.store.automationMode == .activityRules && cooldownAllows,
            ruleVersion: engine.store.activityRuleVersion,
            rules: engine.store.activityRules, ownership: store.activityOwnership,
            pendingManualState: decisionPending || store.hasPendingManualActivityState,
            recordingCoverage: coverage)
    }

    private var decisionPending: Bool {
        if case .awaitingUserDecision = engine.state { return true }
        return false
    }

    @MainActor private func applyActivityRuleResult(_ result: ActivityRuleResult) {
        switch result {
        case .ambiguous(let choice):
            store.presentActivityChoice(choice)
        case .start(let action):
            guard let record = store.applyAutomaticActivity(action) else { return }
            let verb = engine.activeThreadWasContinued ? "continued" : "started"
            hud.show(title: "\(action.ruleName) session \(verb)", detail: action.reason,
                     symbolName: "play.circle.fill",
                     undo: { [weak self] in
                        _ = self?.store.undoAutomaticActivity(
                            expectedRecordID: record.resultingRecordID)
                     })
        case .none, .deadline:
            break
        }
    }

    @MainActor private func apply(_ decision: AutoDecision) {
        switch decision {
        case .none:
            break
        case .start(let guessedType, let name, let backdatedTo, let because):
            // What the user filed this app under lately beats the purpose
            // table's guess.
            let workType = engine.categories.learnedWorkType(for: lastScoredApp) ?? guessedType
            store.startAutomatically(workType: workType, name: name,
                                     backdatedTo: backdatedTo, because: because)
            autoStartedFor = lastScoredApp
            // Deliberately not gated on `rewardsEnabled`: this is a notice about
            // something the app did to the user's history, and the HUD carries
            // the only Undo. Silently inventing sessions with no way back is
            // worse than an unwanted congratulation.
            hud.show(title: name.isEmpty ? "Focus session started"
                                          : "\(name) session started",
                     detail: because,
                     symbolName: "play.circle.fill",
                     undo: { [weak self] in self?.store.undoAutoSession() })
        case .pause(let because):
            engine.transition(on: .manualPause)
            Diagnostics.log("auto-paused: \(because)")
        case .resume:
            engine.transition(on: .manualResume)
        case .end(let at, let because):
            // Ending naturally is the user having let it stand.
            engine.store.autoStartLearning = PurposeLearner(
                signals: engine.store.autoStartLearning).recordingKept(autoStartedFor)
            autoStartedFor = nil
            engine.stop(endingAt: at)
            detector.reset()
            // `stop()` fires `onStateChanged`, which already refreshes; a second
            // pass re-runs the month-long rollup for nothing.
            Diagnostics.log("auto-ended: \(because)")
        }
    }

    @MainActor private func evaluateRewards(score: FocusScore, at moment: Date,
                                            usageSnapshot: AppUsageSnapshot) {
        guard engine.store.rewardsEnabled else { return }

        // Ask the cheap question first. Building the context below walks the
        // whole archive twice and fourteen days of history besides; doing that
        // on every app switch to discover a cooldown was already running cost
        // real CPU in a menu-bar app that is supposed to be invisible.
        let rewards = RewardEngine(log: engine.store.rewardLog)
        guard !rewards.isRateLimited else { return }
        // Enumerating every process on the machine is the most expensive thing
        // here, so it happens after the gate, not before it.
        updateMusicPairing(score: score, at: moment)

        let context = RewardContext(
            focusedToday: engine.todayTotal,
            sameWeekdayLastWeek: engine.archive.focusedSameWeekdayLastWeek(),
            streak: engine.archive.currentStreak(includingToday: engine.elapsedToday()),
            bestStreak: engine.archive.bestStreak(),
            // With no usage the goal's intersection is always zero, which kept
            // `goalReached` and `goalPace` permanently dormant — the one goal
            // computation in the app that was still fed no evidence.
            goal: DailyGoal(archive: engine.archive, goal: engine.store.dailyGoal,
                            usage: usageSnapshot.sessions,
                            usageAccurateFrom: usageSnapshot.accurateFrom,
                            running: engine.runningSpan,
                            runningWork: engine.elapsedToday(),
                            runningPaused: engine.runningPausedSpans,
                            windowDays: engine.store.paceWindowDays).progress(),
            endedMedia: recentlyEndedMedia(before: moment,
                                           usage: usageSnapshot.sessions),
            musicPairing: musicPairingSince.map { moment.timeIntervalSince($0) },
            isSessionRunning: engine.state != .idle)

        guard let reward = rewards.next(for: context) else { return }
        engine.store.rewardLog = rewards.recording(reward)
        hud.show(title: reward.title, detail: reward.detail,
                 symbolName: reward.symbolName, undo: nil)
    }

    /// Music counts only while a focused app is actually frontmost — a playlist
    /// running behind a film is not "focused work with music".
    ///
    /// `musicIsPlaying` is set by the players' own broadcast notifications, not
    /// inferred from the app being open: Spotify launching at login and sitting
    /// paused all day is not music playing, and claiming otherwise would be the
    /// fabrication this app refuses everywhere else. With no notification ever
    /// received the flag stays false and the reward simply never fires.
    private func updateMusicPairing(score: FocusScore, at moment: Date) {
        if musicIsPlaying && score.signals.dominantPurpose.isFocused {
            if musicPairingSince == nil { musicPairingSince = moment }
        } else {
            musicPairingSince = nil
        }
    }

    /// A media stretch that closed in the last minute. Anything older has
    /// already been reported or missed; re-reporting it would be a lie about
    /// when it happened.
    private func recentlyEndedMedia(before moment: Date,
                                    usage: [AppUsageSession]) -> (appName: String,
                                                                  seconds: TimeInterval)? {
        let overrides = engine.store.purposeOverrides
        // `endReason == .stillOpen` means the tracker split an ongoing stretch
        // for bookkeeping, not that the user stopped watching. Without this the
        // HUD says "hope you enjoyed it" while the film is still playing.
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let recent = usage.last {
            moment.timeIntervalSince($0.end) < 60 && moment >= $0.end
                && $0.endReason != .stillOpen
                && $0.bundleID != frontmost
                && PurposeMap.purpose(for: $0.bundleID, activity: .passive,
                                      overrides: overrides) == .media
        }
        guard let recent else { return nil }
        return (recent.appName, recent.seconds)
    }

    /// Reads three integers. Called only from handlers that were going to run
    /// anyway, so it adds no wakeups.
    private func sampleInput(absent: Bool = false) {
        density.record(InputSample(at: Date(),
                                   keys: inputCounters.keys(),
                                   clicks: inputCounters.clicks(),
                                   scrolls: inputCounters.scrolls(),
                                   // Whatever the counters do behind a locked
                                   // screen, it was not this person working.
                                   idleSeconds: absent ? .greatestFiniteMagnitude
                                                       : densityIdle.idleSeconds()))
    }

    /// macOS 13 exposes no API to open a `MenuBarExtra` window programmatically.
    /// Ordinary states therefore keep the zero-friction start/stop route, while
    /// an unresolved Away question is re-presented through the existing prompt
    /// owner. The shortcut never archives or clears unclassified evidence.
    private func toggleSessionFromHotKey() {
        let result = store.performSessionHotKeyAction()
        if result == .showAwayDecision {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mainWindow.open(tab: .focus)
                _ = self.awayPrompter.presentPendingDecision()
            }
        }
    }

    override init() {
        self.engine = SessionEngine()
        super.init()
    }

    private var welcomeEffects: AnyCancellable?
    private var activeWelcomeEffect: FirstRunEffect?

    /// A card can declare one thing for the app to do while it shows. The
    /// coach only reports where the reader is; this applies the effect on
    /// the way in and reverses it on the way out — including when the tour
    /// is skipped with the sample away card still up.
    private var welcomePlace: AnyCancellable?

    /// Where a running tour is, written down as it moves, so a quit or a crash
    /// mid-tour leaves something Settings can pick up from. The tour's end
    /// clears it.
    private func rememberWelcomePlace() {
        welcomePlace = firstRun.$progress
            .compactMap { $0?.chapter }
            .removeDuplicates()
            .sink { [weak self] chapter in self?.engine.store.welcomeLeftAt = chapter }
    }

    private func observeWelcomeEffects() {
        welcomeEffects = firstRun.$progress
            .map { $0?.current.effect }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] next in
                guard let self else { return }
                Task { @MainActor in
                    if let previous = self.activeWelcomeEffect { self.undo(previous) }
                    if let next { self.apply(next) }
                    self.activeWelcomeEffect = next
                }
            }
    }

    @MainActor private func apply(_ effect: FirstRunEffect) {
        switch effect {
        case .openSessionControls:
            mainWindow.focusSessionControls()
        case .previewAwayCard:
            // The real card with sample figures; answers dismiss it and
            // resolve nothing, because there is no absence behind it.
            awayPrompter.preview(.quick)
        case .showHistory:
            mainWindow.open(tab: .review)
        }
    }

    @MainActor private func undo(_ effect: FirstRunEffect) {
        switch effect {
        case .openSessionControls:
            break
        case .previewAwayCard:
            awayPrompter.dismiss()
        case .showHistory:
            mainWindow.returnToStory()
        }
    }

    /// Settings is a panel over the story and the welcome points at the story,
    /// so the panel comes down with it.
    private func replayWelcome(from chapter: FirstRunChapter? = nil) {
        Task { @MainActor in
            self.mainWindow.closeSheet()
            self.firstRun.begin(at: chapter)
        }
    }

    /// A Mac with history has plainly met the app before, whatever the flag
    /// says, so the build that first ships a welcome does not ambush anybody
    /// already using it. `--onboarding` forces it for inspection.
    private func presentWelcomeIfNew() {
        guard FirstRunGate.shouldWelcome(
            onboarded: engine.store.hasOnboarded,
            hasSessionHistory: !engine.archive.records.isEmpty,
            hasUsageHistory: !usage.sessions.isEmpty,
            forced: CommandLine.arguments.contains("--onboarding")) else {
            // No welcome to read first, so the system's question can come now.
            notifier.requestAuthorization()
            return
        }
        firstRun.begin()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Determine unattended launch state and restore the engine before any
        // lazy SessionStore/prompt/monitor owner can materialise and refresh.
        // Building the store restores the engine first, if the menu-bar label
        // has not already built it. From here the store's refreshes see the
        // restored active record and never prune its metadata.
        let store = self.store
        let displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        store.screenLocked = screenLocked
        applyApplicationAppearance(settings.appearancePreference)
        ZoomModel.shared.apply(percent: InterfaceZoom.nearestPercent(toScale: settings.interfaceZoom))
        wireMonitor()
        monitor.start()

        // Restore still precedes frontmost activation: from idle, a work app
        // could otherwise overwrite the snapshot with a fresh session.
        // Launched behind a lock, nothing is in front of anyone: seeding the
        // frontmost app would record usage nobody is producing.
        if AppCoordinator.permitsInitialUsageSeed(screenLocked: screenLocked,
                                                  displayAsleep: displayAsleep),
           let frontmost = NSWorkspace.shared.frontmostApplication {
            foregroundGeneration &+= 1
            engine.transition(on: .appActivated(bundleID: frontmost.bundleIdentifier,
                                                name: frontmost.localizedName ?? "Unknown"))
            tracker.appActivated(bundleID: frontmost.bundleIdentifier,
                                 name: frontmost.localizedName ?? "Unknown")
        }
        store.readWatching = WatchDetector.read
        store.readWorkTraffic = WorkTrafficReader.read
        AgentPings.listen { [weak store] in store?.lastAgentPing = Date() }
        // Apps the purpose rules do not know fall back to what they declare
        // about themselves.
        PurposeMap.declaredCategory = { AppCategoryReader.shared.category(for: $0) }
        store.attach(tracker: tracker, usage: usage)
        store.onDeferredAutomationReady = { [weak self] in self?.scheduleAutomation() }
        store.onAutomationStateChanged = { [weak self] in self?.scheduleAutomation() }
        store.onActivityChoiceSelected = { [weak self] ruleID in
            guard let self else { return }
            _ = self.activityAutomation.choose(ruleID: ruleID,
                                                using: self.activityRuleInput())
        }
        store.refresh()
        observeWindowRequests()
        applyPresence()
        updater.isBusy = { [weak self] in self?.store.holdsUnsavedWork ?? false }
        settings.updater = updater
        // New or not by the welcome's own rule: recorded app use alone makes
        // an install an existing one, so its history is not uploaded unasked.
        engine.store.settleBackupSchedule(isExistingInstall: !FirstRunGate.shouldWelcome(
            onboarded: engine.store.hasOnboarded,
            hasSessionHistory: !engine.archive.records.isEmpty,
            hasUsageHistory: !usage.sessions.isEmpty,
            forced: false))
        backups.start { [weak self] in self?.settings.backUpIfDue() }
        secondLaunchObserver = DistributedNotificationCenter.default().addObserver(
            forName: InstanceLock.reopenNotification, object: nil, queue: .main) { [weak self] _ in
            NSApp.activate()
            self?.reopenRequests.send()
        }
        observeWelcomeEffects()
        rememberWelcomePlace()
        Task { @MainActor in
            self.presentWelcomeIfNew()
            self.awayPrompter.start()
            self.openRequestedPreview()
        }

        // A nudge, never a block: it does not pause the session or take focus.
        observeMusicPlayback()
        wireSessionCallbacks()

        hotKey.register(engine.store.globalShortcut) { [weak self] in
            self?.toggleSessionFromHotKey()
        }
        settings.applyGlobalShortcut = { [weak self] chord in self?.hotKey.apply(chord) ?? false }
        hotKey.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &settings.$globalShortcutStatus)
    }

    /// What the store reports back once a session is running: undone automatic
    /// sessions, declared absence and due breaks.
    private func wireSessionCallbacks() {
        // A session the user rejected must not reappear a few minutes later:
        // the conditions that justified it are still true.
        store.onAutoSessionUndone = { [weak self] in
            guard let self else { return }
            self.engine.store.autoStartLearning = PurposeLearner(
                signals: self.engine.store.autoStartLearning)
                .recordingUndone(self.autoStartedFor)
            self.autoStartedFor = nil
            self.detector.suppressStarts(
                until: Date().addingTimeInterval(FocusConstants.defaultWorkInterval))
        }
        // Declaring yourself away stops background recording too. Nothing should
        // accrue while nobody is there, and saying so is more reliable than the
        // idle trim, which only notices three minutes after the fact.
        store.onAwayBegan = { [weak self] in self?.tracker.suspend() }
        store.onAwayEnded = { [weak self] in self?.resumeTracking() }
        // One channel per moment. At the screen, the HUD: it can interrupt a
        // stretch of work and never takes focus. Away from it — locked, asleep
        // or declared away — the notification, which survives in Notification
        // Centre until you are back. Both at once said the same thing twice.
        store.onBreakDue = { [weak self] prompt in
            guard let self else { return }
            let away: Bool
            if case .paused(reason: .away) = self.engine.state { away = true } else { away = false }
            let reachesScreen = AppCoordinator.breakReminderReachesScreen(
                screenLocked: self.screenLocked,
                displayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
                machineSleeping: self.machineSleeping,
                away: away)
            guard reachesScreen else {
                self.notifier.postBreakReminder(title: prompt.title, body: prompt.body)
                return
            }
            Task { @MainActor in
                self.hud.show(title: prompt.title,
                              detail: prompt.body + " " + prompt.tier.reason,
                              symbolName: prompt.tier.symbolName,
                              duration: FocusConstants.breakHUDSeconds,
                              undo: nil)
            }
        }
    }

    /// `--preview-away quick|full|card|past`: shows the away prompt, or the main
    /// window at a pending card or a past day, without clicking through the
    /// menu-bar extra first.
    @MainActor private func openRequestedPreview() {
        guard let index = CommandLine.arguments.firstIndex(of: "--preview-away") else { return }
        let which = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "quick"
        guard which == "card" || which == "past" else {
            awayPrompter.preview(which == "full" ? .full : .quick)
            return
        }
        if which == "card" { store.previewPendingAway(6 * 60) }
        // The real main shell in a plain preview window, so the requested card
        // or historical day can be inspected without first clicking through
        // the menu-bar extra.
        mainWindow.open(tab: .today)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 120, width: 1_160.zoomed, height: 780.zoomed),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Daybook (preview)"
        window.contentMinSize = ZoomWindowFit.minimum(base: MainWindowView.minimumBase)
        window.contentView = NSHostingView(rootView: MainWindowView(
            store: store, settings: settings, navigation: mainWindow))
        window.isReleasedWhenClosed = false
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.persist()
        tracker.suspend()
        monitor.stop()
        hotKey.unregister()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Closing the window never ends the app: it records all day from the
    /// menu bar. While the window is open the app is a regular one (see
    /// `applyPresence`), and SwiftUI quits a regular app when its last window
    /// closes unless told not to.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A menu-bar app has no Dock icon to click, so opening it again is how a
    /// reader asks for its window. The window comes back the way the menu
    /// bar's Open does; false, because that already answered the request.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        reopenRequests.send()
        return false
    }

    /// SwiftUI's optional preferred scheme controls only its rendered tree.
    /// The application-level override is what must be removed when the user
    /// selects System, otherwise a prior explicit Light or Dark choice can
    /// remain pinned for the running macOS app.
    private func applyApplicationAppearance(_ preference: AppearancePreference) {
        preference.apply(to: NSApp)
    }

    /// Captures the frontmost app without recording it. The candidate becomes
    /// active only when the presence gate confirms a return.
    private func prepareTrackingResume() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        store.prepareTrackingResume(bundleID: frontmost.bundleIdentifier,
                                    name: frontmost.localizedName ?? "Unknown")
    }

    /// Unlock and explicit return are human actions, so they can activate the
    /// prepared app immediately rather than waiting for a HID sample.
    @discardableResult
    private func resumeTracking(at moment: Date = Date()) -> Bool {
        prepareTrackingResume()
        let releasedDeferredAutomation = store.confirmPresence(at: moment)
        // Returning to a paused session changes no state — `.awayEnded` on `.paused`
        // deliberately drops the interval, because the pause already accounts
        // for it — so nothing else refreshes here. Without this the one-second
        // ticker, stopped when the machine slept, never restarts, and an
        // idle-paused session stays paused forever with no way back.
        store.refresh()
        return releasedDeferredAutomation
    }

    /// The session dictionary says whether the screen is locked right now —
    /// the one fact the notifications cannot tell a process that was not
    /// running when the lock happened.
    private static func screenIsLockedNow() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// Pure launch policy kept at the lifecycle seam so sleep/lock combinations
    /// can be verified without manipulating the real display in a headless run.
    static func permitsInitialUsageSeed(screenLocked: Bool,
                                        displayAsleep: Bool) -> Bool {
        !screenLocked && !displayAsleep
    }

    /// Whether a break reminder shown on this display would be seen. When it
    /// would, the HUD alone carries it; when it would not, the notification
    /// alone does. Pure so the four absences can be verified headless.
    static func breakReminderReachesScreen(screenLocked: Bool,
                                           displayAsleep: Bool,
                                           machineSleeping: Bool,
                                           away: Bool) -> Bool {
        !screenLocked && !displayAsleep && !machineSleeping && !away
    }

    /// Once per process, before the store exists: locked or asleep at launch
    /// means the person was away while the app was closed.
    private func restoreEngineOnce() {
        guard !engineRestored else { return }
        engineRestored = true
        screenLocked = AppCoordinator.screenIsLockedNow()
        let displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        _ = AppCoordinator.restorePersistedEngine(
            engine, awayAtLaunch: screenLocked || displayAsleep)
    }

    /// Cold-launch restoration boundary. Implemented separately from monitor
    /// wiring so tests can prove ordering without constructing application UI.
    @discardableResult
    static func restorePersistedEngine(_ engine: SessionEngine,
                                       awayAtLaunch: Bool) -> Bool {
        guard let snapshot = engine.launchSnapshot() else { return false }
        engine.restore(from: snapshot, awayAtLaunch: awayAtLaunch)
        return true
    }

    private func wireMonitor() {
        monitor.onScreenLocked = { [weak self] in
            self?.screenLocked = true
            self?.store.screenLocked = true
            self?.engine.transition(on: .awayBegan(trigger: .screenLock))
            self?.tracker.suspend()
            self?.sampleInput(absent: true)
            self?.scheduleAutomation()
        }
        monitor.onSystemWillSleep = { [weak self] in
            self?.machineSleeping = true
            self?.engine.transition(on: .awayBegan(trigger: .systemSleep))
            self?.tracker.suspend()
            self?.sampleInput(absent: true)
            self?.scheduleAutomation()
        }
        monitor.onScreenUnlocked = { [weak self] in
            let moment = Date()
            self?.screenLocked = false
            self?.machineSleeping = false
            self?.store.screenLocked = false
            self?.engine.transition(on: .awayEnded)
            let releasedDeferredAutomation = self?.resumeTracking(at: moment) ?? false
            self?.sampleInput()
            if !releasedDeferredAutomation { self?.scheduleAutomation() }
        }
        monitor.onSystemDidWake = { [weak self] in
            // A wake is the machine's, not the person's. One closed-lid
            // evening delivered this twenty-five times — maintenance dark
            // wakes, notification flashes — and treating each as a return
            // chopped a six-hour absence into silently excluded slivers. The
            // absence ends at the unlock, or at the first input the ticker
            // confirms; never here. The refresh restarts the ticker so that
            // confirmation can happen.
            guard let self else { return }
            self.machineSleeping = false
            self.store.noteMachineWake()
            self.prepareTrackingResume()
            self.store.refresh()
            self.sampleInput()
        }
        monitor.onAppActivated = { [weak self] app in
            guard let self else { return }
            if app.bundleIdentifier == FocusConstants.bundleIdentifier,
               let choice = self.activityAutomation.freezeChoiceForControls(at: Date()) {
                self.store.presentActivityChoice(choice)
            } else {
                self.foregroundGeneration &+= 1
            }
            let delivered = self.store.handleApplicationActivation(
                bundleID: app.bundleIdentifier,
                name: app.localizedName ?? "Unknown")
            self.sampleInput()
            if delivered { self.scheduleAutomation() }
        }
        monitor.onWillPowerOff = { [weak self] in
            self?.engine.persist()
            self?.tracker.suspend()
        }

    }
}

/// Which players are playing. Music and Spotify report separately, so pausing
/// one must not silence the other.
struct MusicPlayback {
    private var playing: Set<String> = []
    var isPlaying: Bool { !playing.isEmpty }

    mutating func update(player: String, state: String?) {
        if state == "Playing" { playing.insert(player) } else { playing.remove(player) }
    }
}
