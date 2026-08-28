import SwiftUI
import AppKit
import Combine

/// The one bridge between `Core` and SwiftUI. Subscribes to the engine's
/// callbacks and republishes them as `@Published` values; views never touch the
/// engine directly. No `@State` anywhere in this app — the Command Line Tools
/// SDK ships no `SwiftUIMacros` plugin, so view state lives in objects like this.
final class SessionStore: ObservableObject {

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// The clock the user sees: this piece of work today, across its
    /// stretches. A break or an absence splits the record — the timeline stays
    /// honest — but not the clock, so coming back from the kitchen picks up at
    /// 2h 14m rather than at zero. `elapsed` is the current stretch alone.
    @Published private(set) var threadElapsed: TimeInterval = 0
    /// How many stretches today's work has had, the running one included.
    @Published var threadSegments = 0
    /// When the first of them began.
    @Published var threadStartedAt: Date?
    @Published private(set) var todayTotal: TimeInterval = 0
    @Published private(set) var streak = 0
    @Published private(set) var weekBars: [DayBar] = []
    @Published private(set) var quickStarts: [QuickStart] = []
    @Published var threadsToday: [ThreadSummary] = []
    @Published private(set) var goal = GoalProgress(
        goal: FocusConstants.defaultDailyGoal, achieved: 0, typical: nil)
    @Published private(set) var sessionsToday = 0
    @Published private(set) var longestToday: TimeInterval = 0
    @Published private(set) var pendingAway: TimeInterval?
    /// When that absence was, for the card's header and the prompts.
    @Published private(set) var pendingAwayRange: (start: Date, end: Date)?

    /// Two-way bound by the popover's intent field and work-type picker.
    @Published var intent: String = ""
    @Published var workType: WorkType = .deepWork

    /// Total tracked computer time today — distinct from `todayTotal`, which is
    /// focused-session time.
    @Published private(set) var trackedToday: TimeInterval = 0
    @Published private(set) var previousSession: SessionRecord?
    @Published var isTrackingEnabled = true

    // MARK: Dashboard
    // Setters below are internal rather than private(set) because
    // SessionStore+Dashboard.swift — the same object, split for size — writes
    // them. Views still never assign them; that stays a discipline.

    @Published var rankedApps: [AppRank] = []
    @Published var timelineSegments: [TimelineSegment] = []
    @Published var focusBrackets: [(start: Date, end: Date)] = []
    @Published var runningApps: [RunningApp] = []
    @Published var insights: [Insight] = []
    /// The selected day or period in words (`SummaryText`); `**` marks figures.
    @Published var summarySentences: [String] = []
    /// Today's figures, for the menu bar. Separate from the day-scoped ones
    /// above because the dashboard may be browsing history while this panel must
    /// still answer "how am I doing right now". They shared one `dayOffset`, so
    /// stepping the dashboard back to Yesterday quietly re-scoped the menu bar
    /// too — and it stayed there until the process was quit.
    @Published var glanceApps: [AppRank] = []
    @Published var glanceInsights: [Insight] = []
    @Published var glanceTimeline: [TimelineSegment] = []
    /// Today's focus brackets, for the menu bar. Same reason as `glanceApps`.
    @Published var glanceBrackets: [(start: Date, end: Date)] = []
    @Published var focusQuality = FocusQuality(byWorkType: [],
                                                            insideSessionShare: 0,
                                                            switchesPerSession: 0,
                                                            sessionCount: 0)
    @Published var trackedForSelectedDay: TimeInterval = 0
    /// Baselines for the stat band's context lines: the day before the selected
    /// day, and the period before the selected period.
    @Published var trackedYesterday: TimeInterval = 0
    @Published var previousPeriodTracked: TimeInterval = 0
    /// Minutes at the Mac per hour of the selected day, and the busiest run.
    @Published var rhythm: [RhythmHour] = []
    @Published var rhythmPeak: String?
    /// Per-day series behind the KPI cards' sparklines: the last seven days on
    /// Day, the period's days on Week and Month.
    @Published var sparks = KPISparks()
    /// Work-type split for the donut — the day's, or the period's summed.
    @Published var workTypeShares: [WorkTypeShare] = []
    /// The focus-session figures for a browsed day. On today the live ones are
    /// used instead, because they include the running session and move every
    /// second; these are rebuilt with the dashboard and cover the archive only.
    /// Without them the stat row on Yesterday read yesterday's Tracked beside
    /// today's Sessions, Focused and Longest — four figures, two days.
    @Published var sessionsForSelectedDay = 0
    @Published var focusedForSelectedDay: TimeInterval = 0
    @Published var longestForSelectedDay: TimeInterval = 0
    @Published var longestNameForSelectedDay: String?
    /// 0 = today, 1 = yesterday, and so on back through history.
    @Published var dayOffset = 0

    /// Timeline inspection. Both are single optionals, so hovering allocates nothing.
    @Published var hoveredSegment: TimelineSegment?
    @Published var selectedSegment: TimelineSegment?
    @Published var stretchesInSelectedHour: [TimelineSegment] = []
    /// Apps whose Top-apps row is expanded to show individual stretches.
    @Published var expandedApps: Set<String> = []
    /// Apps used today that are not running now, each with its stretches.
    @Published var earlierToday: [AppDayHistory] = []
    /// The selected day's sessions and rests, as the Sessions card shows them.
    @Published var daySessions: [DayEntry] = []
    /// A session the user clicked: the page narrows to it (Focused, Tracked,
    /// App share, the timeline's frame) until cleared.
    @Published var selectedSession: DaySession?
    /// A session under the pointer: the timeline frames it lightly.
    @Published var hoveredSession: DaySession?
    /// An app row under the pointer: its blocks brighten on the timeline.
    @Published var highlightedBundleID: String?
    /// Figures for the selected session, computed once when it is selected.
    @Published var sessionAppRanks: [AppRank] = []
    @Published var sessionTracked: TimeInterval = 0

    var timelineWindow: (start: Date, end: Date)? { cachedWindow }
    /// Owns every timeline coordinate. Views ask it for positions.
    var timelineLayout: TimelineLayout?
    /// Today's coordinates, for the menu bar. Same reason as `glanceApps`.
    var glanceLayout: TimelineLayout?

    // MARK: Periods
    @Published var periodDays: [PeriodDay] = []
    @Published var periodLog: [LogEntry] = []
    @Published var periodAppGroups: [LogAppGroup] = []
    @Published var periodDayTotals: [Date: TimeInterval] = [:]
    @Published var periodSummary = PeriodSummary(tracked: 0, activeDays: 0,
                                                              totalDays: 0,
                                                              averagePerActiveDay: 0,
                                                              longest: nil)

    var logGrouping: LogGrouping {
        get { engine.store.logGrouping }
        set {
            engine.store.logGrouping = newValue
            objectWillChange.send()
        }
    }

    /// Whether the collapsed tail of barely-used apps is showing.
    @Published private(set) var showsMinorApps = false

    func toggleMinorApps() { showsMinorApps.toggle() }

    /// True while the running session was started by the detector rather than
    /// by hand — the popover labels it, and only these may be undone.
    var isAutoSession: Bool { state != .idle && engine.activeIsAuto }

    /// Starts a session on the detector's behalf, backdated to when the
    /// qualifying stretch actually began.
    func startAutomatically(workType: WorkType, name: String, backdatedTo: Date,
                            because: String) {
        engine.start(workType: workType, intent: name, isAuto: true)
        engine.backdate(to: backdatedTo)
        refresh()
    }

    /// Undo for an auto-started session: it stops and its record is discarded,
    /// because the app inventing a session is not a thing worth keeping.
    /// Set by the coordinator so an undone session cannot immediately return.
    var onAutoSessionUndone: (() -> Void)?

    func undoAutoSession() {
        guard isAutoSession else { return }
        engine.discard()
        onAutoSessionUndone?()
        refresh()
    }

    /// Time until the next break nudge, and whether one is overdue.
    @Published private(set) var breakCountdown: TimeInterval = 0
    @Published private(set) var isBreakDue = false
    /// Which kind of break is coming next, so the countdown can name it.
    @Published private(set) var nextBreakTier: BreakTier?
    /// Raised when a break becomes due. The coordinator shows the HUD and posts
    /// the notification; the prompt already carries its own words.
    var onBreakDue: ((BreakPrompt) -> Void)?
    /// The user declared themselves away. The coordinator suspends the usage
    /// tracker, which the engine cannot reach from `Core`.
    var onAwayBegan: (() -> Void)?
    /// They came back by hand rather than by touching an app.
    var onAwayEnded: (() -> Void)?

    // Internal for SessionStore+Dashboard.swift.
    var cachedWindow: (start: Date, end: Date)?
    var earliestDay: Date?
    /// The "usual pace" median. Recomputed on refresh rather than every tick:
    /// it walks fourteen days of history and only moves as the hour does.
    private var cachedTypical: TimeInterval?
    /// Worked seconds of the running thread's earlier stretches today. Rebuilt
    /// on refresh; the ticker adds the live stretch each second.
    // Internal for SessionStore+Dashboard.swift, which rebuilds it.
    var threadBaseSeconds: TimeInterval = 0
    /// Counts ticks so the periodic archive flush can run at its own cadence.
    private var tick = 0
    /// Reads one integer per tick. No new timer: the engine is event-driven and
    /// this is the only signal it cannot be told about, because nothing posts a
    /// notification when you *stop* using a machine.
    private let idle = IdleMonitor()
    /// Whether something on screen is being watched right now — a video, a
    /// call, a presentation keeping the display awake. Set by the coordinator
    /// from powerd's assertion list; the default never is.
    var isWatching: () -> Bool = { false }
    /// Set by the coordinator from the lock notifications. While the screen is
    /// locked, no HID reading counts as presence.
    var screenLocked = false
    private var watchingCache: (at: Date, value: Bool)?
    private var lastSampleWatching = false
    private var watchingEndedAt: Date?
    /// Owns confirmed-active time and suppresses the HID reset caused by wake.
    /// Kept pure so wake versus human input can be exercised with an injected
    /// clock and no CoreGraphics permissions.
    private var presenceGate = PresenceGate()

    // Internal for SessionStore+Dashboard.swift; views still never touch this.
    let engine: SessionEngine
    var tracker: AppUsageTracker?
    var usage: AppUsageArchive?
    private var ticker: Timer?

    init(engine: SessionEngine) {
        self.engine = engine
        engine.threadContextMatcher = { [weak self] app in
            self?.runningThreadUses(app) ?? true
        }
        engine.onStateChanged = { [weak self] state in
            DispatchQueue.main.async { self?.apply(state) }
        }
        engine.onNeedsDecision = { [weak self] away, _ in
            DispatchQueue.main.async {
                self?.pendingAwayRange = self?.engine.pendingAwayRange
                self?.pendingAway = away
            }
        }
        apply(engine.state)
    }

    deinit {
        ticker?.invalidate()
    }

    // MARK: - Derived state

    private func apply(_ state: SessionState) {
        self.state = state
        if case .awaitingUserDecision(let away, _) = state {
            pendingAwayRange = engine.pendingAwayRange
            pendingAway = away
        } else {
            pendingAwayRange = nil
            pendingAway = nil
        }
        refresh()
    }

    /// True whenever something on screen is still moving.
    ///
    /// Not `state.isRunning`: an unanswered away question froze the clock, the
    /// totals and the background flush until the card was dismissed, so the app
    /// looked stopped while the user was plainly working. And not sessions
    /// alone either — "at the Mac" climbs whether or not anyone pressed Start,
    /// so an open stretch is reason enough to keep counting. Both go quiet on
    /// lock and sleep, which is when `suspend()` closes the stretch.
    private var ticks: Bool {
        if tracker?.isObserving == true { return true }
        return engine.state != .idle && !engine.state.isPaused
    }

    private func updateTicker() {
        ticks ? startTicker() : stopTicker()
    }

    /// Attaches the background usage tracker. Optional: the focus loop works
    /// fully without it, and the gallery drives the store without one.
    func attach(tracker: AppUsageTracker, usage: AppUsageArchive) {
        self.tracker = tracker
        self.usage = usage
        self.isTrackingEnabled = tracker.isEnabled
        refresh()
    }

    /// Wakes are machine events. Keep sampling on the existing ticker, but do
    /// not let the HID reset count as a return.
    func noteMachineWake() {
        presenceGate.noteMachineWake()
    }

    /// Unlock and explicit returns are direct proof of presence. A waiting app
    /// candidate begins at this instant; an already-active tracker is unchanged.
    func confirmPresence(at moment: Date) {
        presenceGate.confirm(at: moment)
        tracker?.confirmPresence(at: moment)
    }

    /// Recomputes everything the surfaces display. One pass over each archive.
    func refresh() {
        // Fold the in-flight stretch in first, or the frontmost app always looks
        // idle in its own menu.
        tracker?.flush()
        // The fourteen-day walk behind "usual pace" only changes as the clock
        // hour moves, so it is computed here and reused by the ticker.
        cachedTypical = DailyGoal(archive: engine.archive,
                                  goal: engine.store.dailyGoal,
                                  usage: usage?.sessions ?? [],
                                  running: engine.runningSpan).typical()
        refreshThread()
        refreshLiveFigures()

        weekBars = engine.archive.weekBars()
        quickStarts = engine.archive.quickStarts(limit: 7)
        workType = engine.activeWorkType
        previousSession = engine.archive.records.last
        isTrackingEnabled = tracker?.isEnabled ?? false
        refreshDashboard()
        refreshBreak()
        updateTicker()
    }

    /// Every figure that moves second by second, in one place.
    ///
    /// These used to be split: the ticker advanced `elapsed` while `goal`,
    /// `streak` and `longestToday` were only rebuilt on a state change. With the
    /// popover open — exactly when someone is comparing them — the goal bar sat
    /// frozen at whatever it read when the panel opened while the timer directly
    /// beneath it counted on, so the two disagreed by however long you looked.
    private func refreshLiveFigures() {
        // `engine.state`, not the published mirror: `state` is updated on an
        // async hop, and several callers refresh synchronously right after
        // mutating the engine, when the mirror still says `.idle`.
        let inFlight = engine.elapsedToday()
        elapsed = engine.elapsed
        // Gated on state: the engine's `elapsed` keeps counting from the last
        // start after a stop, because nothing reads it when idle — this does.
        threadElapsed = engine.state == .idle ? 0 : threadBaseSeconds + elapsed
        todayTotal = engine.todayTotal
        sessionsToday = engine.sessionsToday
        longestToday = engine.longestToday
        streak = engine.archive.currentStreak(includingToday: inFlight)
        goal = GoalProgress(goal: engine.store.dailyGoal,
                            achieved: DailyGoal(archive: engine.archive,
                                                goal: engine.store.dailyGoal,
                                                usage: usage?.sessions ?? [],
                                                running: engine.runningSpan,
                                                runningWork: inFlight)
                                .achievedToday(),
                            typical: cachedTypical)
        // Re-read rather than adding the open stretch to a cached total. The
        // cached version missed every segment that opened *and closed* between
        // refreshes, so the figure went backwards on each app switch.
        if let usage {
            trackedToday = usage.totalToday() + (tracker?.unpersistedSeconds() ?? 0)
        }
    }

    // MARK: - Break reminders

    /// Continuous computer use, session or not: the case that hurts is grinding
    /// for hours without ever pressing Start.
    private func refreshBreak() {
        guard let usage, engine.store.remindersEnabled else {
            breakCountdown = 0
            isBreakDue = false
            nextBreakTier = nil
            return
        }
        let moment = Date()
        let result = BreakReminder.evaluate(usage.sessions, now: moment,
                                            last: engine.store.lastBreakNotice)
        breakCountdown = result.next?.seconds ?? 0
        nextBreakTier = result.next?.tier
        isBreakDue = result.due != nil

        guard let prompt = result.prompt else { return }
        engine.store.lastBreakNotice = BreakNotice(tier: prompt.tier, at: moment)
        onBreakDue?(prompt)
    }

    // Settings are written by `SettingsModel`; these are the read side the
    // surfaces still need.
    var remindersEnabled: Bool { engine.store.remindersEnabled }

    /// How long an absence has to be before the app asks about it rather than
    /// quietly leaving it out.
    var breakThreshold: TimeInterval { engine.breakThreshold }

    /// And how long before it stops asking and simply ends the session.
    var longAwayCap: TimeInterval { engine.store.longAwayCap }

    /// `Look away in 3m`, or `Break due` once one is. Names the kind of break so
    /// a thirty-second look-away is not mistaken for a quarter of an hour off.
    var breakLabel: String {
        guard remindersEnabled else { return "Reminders off" }
        if isBreakDue { return "Break due" }
        guard let tier = nextBreakTier else { return "No break due" }
        return "\(tier.shortLabel) in \(Tokens.preciseDuration(breakCountdown))"
    }

    /// How often the open usage stretch is written to disk, bounding what an
    /// unclean exit can lose.
    private static let flushEverySeconds = 60

    /// How often continuous use is re-checked against the break thresholds.
    private static let breakCheckSeconds = 5

    /// Presence is categorical for the engine: once the gate confirms input,
    /// its age must not be reinterpreted as continued quiet. The tracker still
    /// receives the honest `since` date separately.
    func applyPresenceObservation(_ observation: PresenceObservation) -> TimeInterval {
        switch observation {
        case .active(let since):
            tracker?.confirmPresence(at: since)
            return 0
        case .quiet(let seconds): return seconds
        }
    }

    /// One sample a second: seconds since the last input, told apart into
    /// idle and watched. Quiet in front of a film, a call or a presentation is
    /// presence, and the engine must not read it as an absence. Watching is
    /// read from powerd at most every five seconds and only once a minute of
    /// quiet has built up — nothing depends on it before then.
    private func observeIdle() {
        let raw = idle.idleSeconds()
        let now = Date()
        let displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        let observation = presenceGate.observe(rawIdleSeconds: raw,
                                               at: now,
                                               displayAwake: displayAwake,
                                               screenLocked: screenLocked)
        let quiet = applyPresenceObservation(observation)
        if quiet < 60 {
            // Recent input: nothing to tell apart, and any watching is over.
            watchingCache = nil
            lastSampleWatching = false
            watchingEndedAt = nil
            tracker?.observeIdle(seconds: quiet)
            engine.transition(on: .idleObserved(seconds: quiet))
            return
        }
        let watching: Bool
        if let cache = watchingCache, now.timeIntervalSince(cache.at) < 5 {
            watching = cache.value
        } else {
            watching = isWatching()
            watchingCache = (now, watching)
        }
        if watching {
            lastSampleWatching = true
            watchingEndedAt = nil
            tracker?.observeIdle(seconds: quiet)
            engine.transition(on: .watchingObserved(seconds: quiet))
            return
        }
        if lastSampleWatching { watchingEndedAt = now }
        lastSampleWatching = false
        // Once the watching stops, idle counts from then — not from the last
        // keypress before the film, which would put the film into the absence.
        let effective = watchingEndedAt.map { min(quiet, now.timeIntervalSince($0)) } ?? quiet
        tracker?.observeIdle(seconds: effective)
        engine.transition(on: .idleObserved(seconds: effective))
    }

    /// Cosmetic only, exactly like the AppKit build's title timer: it reads
    /// nothing the state machine consumes and drives no transition.
    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.observeIdle()
            // Nothing else writes the open stretch to disk on a schedule, so a
            // crash, a Force Quit or a `kill` took everything since the last app
            // switch with it — `applicationWillTerminate` does not run for any
            // of those. Bounded to a minute now, instead of unbounded.
            if self.tick % SessionStore.flushEverySeconds == 0 {
                if (self.tracker?.unpersistedSeconds() ?? 0) >=
                        TimeInterval(SessionStore.flushEverySeconds) {
                    self.tracker?.flush()
                }
                // The engine's snapshot has the same problem: `savedAt` is the
                // last app switch, and a relaunch reads everything since it as
                // an absence. A heartbeat bounds that to a minute too.
                if self.engine.state != .idle { self.engine.persist() }
            }
            // Breaks are timed from continuous use, which nothing else observes
            // on a schedule: staying inside one app posts no notification, so a
            // check driven only by refreshes never fired for exactly the person
            // this feature exists for. Every few seconds is enough for a
            // countdown shown in minutes, and keeps the archive walk off 1 Hz.
            if self.tick % SessionStore.breakCheckSeconds == 0 { self.refreshBreak() }
            self.refreshLiveFigures()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Actions

    /// Pressing Start continues a session already running on the same kind of
    /// work — including one the app started by itself — and only begins a new
    /// one when the work type differs. Background recording is unaffected
    /// either way: app usage is captured all day regardless of sessions.
    func start() {
        if engine.wouldAdopt(workType: workType) {
            engine.adopt(intent: intent)
        } else {
            engine.start(workType: workType, intent: intent)
        }
        intent = ""
        refresh()
    }

    func startQuick(_ quick: QuickStart) {
        workType = quick.workType
        if engine.wouldAdopt(workType: quick.workType) {
            engine.adopt(intent: quick.name)
        } else {
            engine.start(workType: quick.workType, intent: quick.name)
        }
        intent = ""
        refresh()
    }

    /// Drives the Start button's label, so the button says what it will do.
    var startWouldContinue: Bool { engine.wouldAdopt(workType: workType) }

    func stop() {
        engine.stop()
    }

    func togglePause() {
        let resumable = !engine.state.isRunning && engine.state != .idle
        engine.transition(on: resumable ? .manualResume : .manualPause)
    }

    /// "I am stepping away." The one thing the app never has to guess at, and
    /// the answer to the question it would otherwise ask on your return.
    /// Unlike Pause this also stops background recording — a paused session
    /// still leaves you sitting at the Mac, being away does not.
    func markAway() {
        engine.transition(on: .markedAway)
        onAwayBegan?()
        refresh()
    }

    /// Ends a declared away. Any real activity ends it too, through the ordinary
    /// app-activation path; this is the explicit version for coming back to a
    /// Mac that was left on a session that has no work app to return to.
    func endAway() {
        engine.transition(on: .manualResume)
        onAwayEnded?()
        refresh()
    }

    /// True while the user has declared themselves away, as opposed to having
    /// paused a session they are still sitting in front of.
    var isAway: Bool {
        if case .paused(.away) = state { return true }
        return false
    }

    /// `label` names a break in the user's words ("dinner"); it is ignored for
    /// any other answer.
    func resolve(_ decision: UserDecision, label: String? = nil) {
        engine.decide(decision, label: label)
    }

    /// `--preview-away card` only: fakes a pending question so the popover and
    /// dashboard cards can be looked at without staging an absence. Touches
    /// nothing in the engine; answering resolves nothing and simply clears it.
    func previewPendingAway(_ away: TimeInterval) {
        pendingAwayRange = (start: Date().addingTimeInterval(-away), end: Date())
        pendingAway = away
    }

    // MARK: - Presentation helpers

    var activeIntent: String {
        engine.sessionName.isEmpty ? "Focus session" : engine.sessionName
    }

    var isIdle: Bool { state == .idle }
    var isPaused: Bool { state.isPaused }
}
