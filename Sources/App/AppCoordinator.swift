import AppKit
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
    private let hotKey = HotKeyMonitor()
    private let powerMonitor = PowerSourceMonitor()
    private(set) lazy var store = SessionStore(engine: engine, powerMonitor: powerMonitor)
    /// The Settings window's model. Writes go to the same preferences the
    /// engine reads; `onChange` refreshes every surface that shows them.
    private(set) lazy var settings = SettingsModel(
        store: engine.store,
        isTrackingEnabled: engine.store.isUsageTrackingEnabled,
        onChange: { [weak self] in self?.store.refresh() },
        onTrackingChanged: { [weak self] in self?.store.setTrackingEnabled($0) },
        onAppearanceChanged: { [weak self] in self?.applyApplicationAppearance($0) },
        diagnostics: .live(usage: usage))
    /// One route object for the window, menu popover, commands and deep links.
    /// Its first story comes from the persisted preference exactly once at
    /// launch.
    @MainActor private(set) lazy var mainWindow = MainWindowModel(
        selectedTab: .story,
        storyScope: settings.defaultStoryScope,
        store: store)

    /// Input density, fed only at event boundaries — app activation, lock,
    /// unlock, wake — and never on a timer. A repeating timer would be the only
    /// polling in the app and would hold the process off App Nap for a signal
    /// that is consumed just once, when a stretch ends.
    let density = InputDensity()
    private let inputCounters = InputCounters()
    private let densityIdle = IdleMonitor()

    // MARK: - Automatic sessions and rewards

    private var detector = AutoSessionDetector(breakLength: FocusConstants.defaultBreakLength)
    /// Lazy because `RewardHUD` is main-actor isolated and this delegate is
    /// not; every access below is already on the main thread.
    @MainActor private lazy var hud = RewardHUD()
    /// Holds the `--preview-away card` window so it is not released.
    @MainActor private var previewWindow: NSWindow?
    /// Whether the screen is locked, as the notifications have told us. A
    /// display waking behind a lock — a notification, a lid opened to a
    /// password field, a dark wake — is not the user back; the unlock is.
    private var screenLocked = false
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
    private var musicIsPlaying = false

    private func observeMusicPlayback() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: Notification.Name(name), object: nil,
                               queue: .main) { [weak self] note in
                let state = note.userInfo?["Player State"] as? String
                self?.musicIsPlaying = (state == "Playing")
                if state != "Playing" { self?.musicPairingSince = nil }
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
        let usageSnapshot = AppUsageSnapshot(archive: usage, tracker: tracker)
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

        if engine.store.autoSessionsEnabled && !decisionPending {
            // `state != .idle` rather than `state.isRunning`: a session the
            // detector paused is still its session, and reporting it as gone
            // would make the detector discard the pause it is timing.
            lastScoredApp = score.signals.dominantApp
            let decision = detector.evaluate(score: score, at: moment,
                                             sessionRunning: engine.state != .idle,
                                             sessionWasAutoStarted: engine.activeIsAuto,
                                             enginePaused: engine.state.isPaused)
            apply(decision)
        } else {
            // Nothing evaluates while disabled or while a decision is pending,
            // so a qualifying run frozen at switch-off would fire the instant it
            // is switched back on, backdated arbitrarily far — in the pending
            // case, across the very gap the user is being asked about.
            detector.reset()
        }
        evaluateRewards(score: score, at: moment, usageSnapshot: usageSnapshot)
    }

    @MainActor private func apply(_ decision: AutoDecision) {
        switch decision {
        case .none:
            break
        case .start(let workType, let name, let backdatedTo, let because):
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
                            runningWork: engine.elapsedToday()).progress(),
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Determine unattended launch state and restore the engine before any
        // lazy SessionStore/prompt/monitor owner can materialise and refresh.
        screenLocked = AppCoordinator.screenIsLockedNow()
        let displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        _ = AppCoordinator.restorePersistedEngine(
            engine, awayAtLaunch: screenLocked || displayAsleep)

        // From here the store's initial refresh sees the restored active record
        // and may safely replay metadata recovery without pruning its successor.
        let store = self.store
        store.screenLocked = screenLocked
        applyApplicationAppearance(settings.appearancePreference)
        wireMonitor()
        monitor.start()

        // Restore still precedes frontmost activation: from idle, a work app
        // could otherwise overwrite the snapshot with a fresh session.
        // Launched behind a lock, nothing is in front of anyone: seeding the
        // frontmost app would record usage nobody is producing.
        if AppCoordinator.permitsInitialUsageSeed(screenLocked: screenLocked,
                                                  displayAsleep: displayAsleep),
           let frontmost = NSWorkspace.shared.frontmostApplication {
            engine.transition(on: .appActivated(bundleID: frontmost.bundleIdentifier,
                                                name: frontmost.localizedName ?? "Unknown"))
            tracker.appActivated(bundleID: frontmost.bundleIdentifier,
                                 name: frontmost.localizedName ?? "Unknown")
        }
        store.isWatching = WatchDetector.isWatching
        // Apps the purpose rules do not know fall back to what they declare
        // about themselves.
        PurposeMap.declaredCategory = { AppCategoryReader.shared.category(for: $0) }
        store.attach(tracker: tracker, usage: usage)
        store.onDeferredAutomationReady = { [weak self] in self?.scheduleAutomation() }
        store.refresh()
        Task { @MainActor in
            self.awayPrompter.start()
            if let index = CommandLine.arguments.firstIndex(of: "--preview-away") {
                let which = CommandLine.arguments.count > index + 1
                    ? CommandLine.arguments[index + 1] : "quick"
                if which == "card" || which == "past" {
                    if which == "card" { self.store.previewPendingAway(6 * 60) }
                    if which == "past" {
                        // The view's onAppear returns to today; step after it.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.store.stepDay(by: -1) }
                    }
                    // The real main shell in a plain preview window, so the
                    // requested card or historical day can be inspected without
                    // first clicking through the menu-bar extra.
                    self.mainWindow.open(tab: .today)
                    let window = NSWindow(contentRect: NSRect(x: 200, y: 120,
                                                              width: 1_160, height: 780),
                                          styleMask: [.titled, .closable, .resizable],
                                          backing: .buffered, defer: false)
                    window.title = "FocusContinuity (preview)"
                    window.contentMinSize = NSSize(width: 980, height: 680)
                    window.contentView = NSHostingView(rootView: MainWindowView(
                        store: self.store,
                        settings: self.settings,
                        navigation: self.mainWindow
                    ))
                    window.isReleasedWhenClosed = false
                    self.previewWindow = window
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                } else {
                    self.awayPrompter.preview(which == "full" ? .full : .quick)
                }
            }
        }

        // A nudge, never a block: it does not pause the session or take focus.
        observeMusicPlayback()
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
        // Two channels, deliberately. The HUD is for when you are at the screen
        // — it is the one that can actually interrupt a stretch of work, and it
        // never takes focus. The notification is for when you are not looking at
        // this display, and it is the one that survives in Notification Centre.
        store.onBreakDue = { [weak self] prompt in
            guard let self else { return }
            Task { @MainActor in
                self.hud.show(title: prompt.title,
                              detail: prompt.body + " " + prompt.tier.reason,
                              symbolName: prompt.tier.symbolName,
                              duration: FocusConstants.breakHUDSeconds,
                              undo: nil)
            }
            self.notifier.postAwayResolution(title: prompt.title, body: prompt.body)
        }

        notifier.requestAuthorization()
        hotKey.register { [weak self] in
            self?.toggleSessionFromHotKey()
        }
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

    /// Cold-launch restoration boundary. Implemented separately from monitor
    /// wiring so tests can prove ordering without constructing application UI.
    @discardableResult
    static func restorePersistedEngine(_ engine: SessionEngine,
                                       awayAtLaunch: Bool) -> Bool {
        guard let snapshot = engine.store.loadState() else { return false }
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
            self?.engine.transition(on: .awayBegan(trigger: .systemSleep))
            self?.tracker.suspend()
            self?.sampleInput(absent: true)
            self?.scheduleAutomation()
        }
        monitor.onScreenUnlocked = { [weak self] in
            let moment = Date()
            self?.screenLocked = false
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
            self.store.noteMachineWake()
            self.prepareTrackingResume()
            self.store.refresh()
            self.sampleInput()
        }
        monitor.onAppActivated = { [weak self] app in
            guard let self else { return }
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
