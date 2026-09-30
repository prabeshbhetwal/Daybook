import SwiftUI
import AppKit
import Combine

enum SessionHotKeyActionResult: Equatable {
    case started
    case stopped
    case stoppedPendingFinalisation
    case showAwayDecision
    case saveFailed
}

/// The one bridge between `Core` and SwiftUI. Subscribes to the engine's
/// callbacks and republishes them as `@Published` values; views never touch the
/// engine directly. No `@State` anywhere in this app — the Command Line Tools
/// SDK ships no `SwiftUIMacros` plugin, so view state lives in objects like this.
final class SessionStore: ObservableObject {

    let metadataArchive: SessionMetadataArchive
    /// Readings taken while idle. A quiet block of the story reads its span.
    let ambientPower: AmbientPowerLog
    let powerMonitor: PowerSourceMonitoring?
    @Published var sessionNoteDrafts: [UUID: String] = [:]
    @Published var sessionNoteErrors: [UUID: String] = [:]
    @Published var expandedNoteEditorIDs: Set<UUID> = []
    @Published var focusedNoteEditorID: UUID?
    @Published var powerMetadataError: String?
    /// Whether the window's strip has unfolded the automatic session's
    /// naming row. The row and the bar are two views of one store, so the
    /// bar's Name button and the underline's row meet here. Adopt, Undo and
    /// Stop fold it again.
    @Published var isNamingAutomaticSession = false
    var lastPowerState: SessionState = .idle
    var lastPowerRecordID: UUID?
    /// Set on machine wake, consumed by the next power reconcile. Sleep is the
    /// one thing that stops the power monitor while the app is alive; a pause,
    /// an Away answer or a lock does not, and the sidecar must not say it did.
    var powerCoverageLapsed = false
    var pendingPowerObservations: [PendingPowerObservation] = []
    var pendingPowerTransfers: [PendingPowerTransfer] = []
    var pendingPowerTransferError: String?

    @Published var state: SessionState = .idle
    @Published var elapsed: TimeInterval = 0
    /// The clock the user sees: this piece of work today, across its
    /// stretches. A break or an absence splits the record — the timeline stays
    /// honest — but not the clock, so coming back from the kitchen picks up at
    /// 2h 14m rather than at zero. `elapsed` is the current stretch alone.
    @Published var threadElapsed: TimeInterval = 0
    /// How many stretches today's work has had, the running one included.
    @Published var threadSegments = 0
    /// When the first of them began.
    @Published var threadStartedAt: Date?
    @Published var todayTotal: TimeInterval = 0
    @Published var streak = 0
    /// The best run on record, for the Awards streak panel.
    @Published var streakBest = 0
    @Published var weekBars: [DayBar] = []
    @Published var quickStarts: [QuickStart] = []
    /// The activities the user pinned, in their order. Refreshed with the
    /// quick starts; edited through the methods below.
    @Published var savedActivities: [SavedActivity] = []
    @Published var threadsToday: [ThreadSummary] = []
    /// Archive-wide summaries for Focus and Continue Today. Eligibility is
    /// sampled afresh from the paired index when a surface reads them.
    @Published var continuationCandidates: [ThreadSummary] = []
    @Published var goal = GoalProgress(
        goal: FocusConstants.defaultDailyGoal, achieved: 0, typical: nil)
    @Published var sessionsToday = 0
    @Published var longestToday: TimeInterval = 0
    @Published var pendingAway: TimeInterval?
    /// When that absence was, for the card's header and the prompts.
    @Published var pendingAwayRange: (start: Date, end: Date)?

    /// Two-way bound by the popover's intent field and work-type picker.
    @Published var intent: String = ""
    @Published var workType: WorkType = .deepWork
    /// The "New sessions start as" value last applied, so only a change to it
    /// replaces the category picked for the next session.
    var appliedDefaultWorkType: WorkType = .deepWork
    /// Mirrors the preference so the menu bar label, which observes the
    /// store, redraws when it changes.
    @Published var menuBarShowsTime = true

    /// Total tracked computer time today — distinct from `todayTotal`, which is
    /// focused-session time.
    @Published var trackedToday: TimeInterval = 0
    @Published var previousSession: SessionRecord?
    @Published var isTrackingEnabled = true
    @Published var pendingActivityChoice: ActivityQuietChoice?
    @Published var automaticActivityRecord: AutomaticActivityRecord?
    @Published var activityAutomationError: String?
    var onActivityChoiceSelected: ((UUID) -> Void)?

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
    /// Cached with the selected-day rebuild; views read this without walking
    /// or allocating the usage archive during body evaluation.
    @Published var selectedDayIntegrityNote: String?
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
    /// Goal credit for the selected day: declared focus intersected with the
    /// authoritative usage snapshot. Kept separate from raw session work so the
    /// Focused statistic remains a record of the declared session.
    @Published var focusedActiveForSelectedDay: TimeInterval = 0
    @Published var longestForSelectedDay: TimeInterval = 0
    @Published var longestNameForSelectedDay: String?
    /// 0 = today, 1 = yesterday, and so on back through history.
    @Published var dayOffset = 0

    /// Timeline inspection. Both are single optionals, so hovering allocates nothing.
    @Published var hoveredSegment: TimelineSegment?
    @Published var selectedSegment: TimelineSegment?
    /// Apps used today that are not running now, each with its stretches.
    @Published var earlierToday: [AppDayHistory] = []
    /// The selected day's sessions and rests, as the Sessions card shows them.
    @Published var daySessions: [DayEntry] = []
    /// A session the user clicked: the page narrows to it (Focused, Tracked,
    /// App share) until cleared.
    @Published var selectedSession: DaySession?
    /// Figures for the selected session, computed once when it is selected.
    @Published var sessionAppRanks: [AppRank] = []
    @Published var sessionTracked: TimeInterval = 0
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

    // MARK: Review
    // Review owns an independent period anchor. Browsing a previous week or
    // month must not quietly move Today away from its selected calendar day.
    @Published var reviewAnchor: Date?
    @Published var reviewPeriod: TrackingPeriod = .week
    @Published var reviewDays: [PeriodDay] = []
    @Published var reviewLog: [LogEntry] = []
    /// Full, day-scoped Review evidence for the selected-day detail. The
    /// chronological review log remains independently bounded for rendering.
    @Published var reviewEntriesByDay: [Date: [LogEntry]] = [:]
    @Published var reviewLogTotalEntries = 0
    @Published var reviewAppGroups: [LogAppGroup] = []
    @Published var reviewDayTotals: [Date: TimeInterval] = [:]
    @Published var reviewSummary = PeriodSummary(tracked: 0, activeDays: 0,
                                                  totalDays: 0,
                                                  averagePerActiveDay: 0,
                                                  longest: nil)
    @Published var reviewLongestFocusSeconds: TimeInterval = 0
    @Published var reviewLongestFocusName: String?
    @Published var reviewFocusSessions: [ReviewFocusEntry] = []
    @Published var reviewWorkTypeShares: [WorkTypeShare] = []
    /// Canonical quality for the reviewed period, so the rail can split the
    /// period's time the same three ways the day is split.
    @Published var reviewQuality = FocusQuality(byWorkType: [],
                                                insideSessionShare: 0,
                                                switchesPerSession: 0,
                                                sessionCount: 0)
    @Published var reviewIntegrityNote: String?

    // MARK: Insights
    // Week and Month remain separate read models so local range selection never
    // mutates Review's independently selected period.
    @Published var insightDaySurface = InsightSurface.empty(range: .day)
    @Published var insightWeekSurface = InsightSurface.empty(range: .week)
    @Published var insightMonthSurface = InsightSurface.empty(range: .month)

    /// Canonical History is derived from the authoritative usage snapshot and
    /// the archive. Filter/range state lives beside it because this toolchain
    /// cannot use SwiftUI's macro-backed local state.
    @Published var historyDays: [HistoryDay] = []
    @Published var historyFilter = HistoryFilter()
    @Published var historyRangeStart: Date?
    @Published var historyRangeEnd: Date?
    @Published var historyAppNames: [String: String] = [:]
    /// Source qualifications shown before History's derived filters and rows.
    /// Legacy evidence remains visible; defensive span omissions remain in the
    /// source archive and are counted explicitly rather than disappearing.
    @Published var historyIntegrityNotices: [String] = []

    /// A failed correction stays visible and retryable. The archive is not
    /// refreshed until its candidate was atomically persisted.
    @Published var correctionError: String?
    @Published var canUndoCorrection = false
    var correctionRetry: SessionCorrectionRetry?

    /// Undo for an auto-started session: it stops and its record is discarded,
    /// because the app inventing a session is not a thing worth keeping.
    /// Set by the coordinator so an undone session cannot immediately return.
    var onAutoSessionUndone: (() -> Void)?

    /// Time until the next break nudge, and whether one is overdue.
    @Published var breakCountdown: TimeInterval = 0
    @Published var isBreakDue = false
    /// Which kind of break is coming next, so the countdown can name it.
    @Published var nextBreakTier: BreakTier?
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
    var earliestDayCache: (revision: EvidenceRevision, day: Date?)?
    /// Archive callbacks rebuild the dashboard only while its window is on
    /// screen. Hidden changes are coalesced until the next appearance.
    var dashboardVisible = false
    var dashboardArchiveRefreshPending = false
    var dashboardLiveTailRefreshPending = false
    var dashboardReadModelDay: Date?
    var dashboardEvidenceRevision: EvidenceRevision?
    /// The archive-wide facts History's map shows, kept until the evidence
    /// behind them changes.
    var historyArchiveFactsCache: (revision: EvidenceRevision, facts: HistoryArchiveFacts)?
    /// History's recent readings: the rail asks for one at a time, but a
    /// reader who opens a week, then its month, then the week again should
    /// not pay for the week twice. Bounded; the oldest goes first.
    var insightReadingCache: [InsightReadingKey: InsightReading] = [:]
    var insightReadingCacheOrder: [InsightReadingKey] = []
    /// How many times the reading was actually built. Verification reads it to
    /// prove a ticking clock no longer rebuilds an unchanged page.
    var insightReadingComputeCount = 0
    /// How many times the Insights surfaces were built. Verification reads it
    /// to prove a page that does not show them does not build them.
    var insightsComputeCount = 0
    /// The journal a search narrows to, kept while the search and the archive
    /// behind it stay the same; its matches walk every record.
    var searchJournalCache: (key: SearchJournalKey, entries: [JournalEntry])?
    /// History's tree: its index, its rows per parent place and its
    /// summaries per place, held until the archive changes.
    var historyTreeCache: HistoryTreeCache?
    /// The dashboard rail's figures for a day History has open.
    var storyRailDayCache: (day: Date, revision: EvidenceRevision, minute: Int, reading: StoryRailDay)?
    var historyTreeComputeCount = 0
    /// The find bar's app list, sorted by name once per archive state; it
    /// was sorted afresh on every render, once a second.
    var historyAppListCache: (key: JournalKey, ids: [String])?
    var historyAppListComputeCount = 0
    /// How many times a search's matches were walked.
    var searchJournalComputeCount = 0
    var reviewEvidenceRevision: EvidenceRevision?
    /// Explicit-date Story projections are immutable read models. Historical
    /// values survive ticker frames; current or running dates deliberately
    /// bypass this bounded cache.
    var storyProjectionCache: [StoryDayProjectionCacheKey: StoryDayProjection] = [:]
    var storyProjectionCacheOrder: [StoryDayProjectionCacheKey] = []
    var reviewVisible = false
    var reviewRefreshPending = true
    /// Marks a ticker-only Review update: patch the current live day instead
    /// of rebuilding stable all-history evidence.
    var reviewLiveTailRefreshPending = false
    var insightsVisible = false
    var insightsRefreshPending = true
    var glanceArchiveRefreshPending = false
    /// Read-model generations change only after a real rebuild. They support
    /// coalescing diagnostics and keep unchanged ticker frames observable.
    var dashboardReadModelGeneration = 0
    var dashboardArchiveReadModelGeneration = 0
    var reviewReadModelGeneration = 0
    var historyIndexGeneration = 0
    /// Nested archive callbacks join the outer refresh and are consumed once
    /// when its final frame exits.
    var refreshTransactionDepth = 0
    /// The "usual pace" median. Recomputed on refresh rather than every tick:
    /// it walks fourteen days of history and moves at local minute boundaries.
    var cachedTypical: TimeInterval?
    var cachedTypicalMinute: Date?
    var lastLiveFrame: LiveFrame?
    /// Worked seconds of the running thread's earlier stretches today. Rebuilt
    /// on refresh; the ticker adds the live stretch each second.
    // Internal for SessionStore+Dashboard.swift, which rebuilds it.
    var threadBaseSeconds: TimeInterval = 0
    /// Counts ticks so the periodic archive flush can run at its own cadence.
    var tick = 0
    /// Reads one integer per tick. No new timer: the engine is event-driven and
    /// this is the only signal it cannot be told about, because nothing posts a
    /// notification when you *stop* using a machine.
    /// Real HID idle in the product; tests inject `.disabled` so a fixture's
    /// open stretch is not trimmed by however long the build Mac sat untouched.
    let idle: IdleMonitor
    /// Whether something on screen is being watched right now — a video, a
    /// call, a presentation keeping the display awake. Set by the coordinator
    /// from powerd's assertion list; the default never is.
    var isWatching: () -> Bool = { false }
    /// Set by the coordinator from the lock notifications. While the screen is
    /// locked, no HID reading counts as presence.
    var screenLocked = false
    var watchingCache: (at: Date, value: Bool)?
    var lastSampleWatching = false
    var watchingEndedAt: Date?
    /// Owns confirmed-active time and suppresses the HID reset caused by wake.
    /// Kept pure so wake versus human input can be exercised with an injected
    /// clock and no CoreGraphics permissions.
    var presenceGate = PresenceGate()
    var pendingWakeActivation: (bundleID: String?, name: String)?
    var deferredAutomationPending = false
    /// The coordinator evaluates automation through this callback only after a
    /// wake has been matched to genuine presence.
    var onDeferredAutomationReady: (() -> Void)?
    var onAutomationStateChanged: (() -> Void)?

    // Internal for SessionStore+Dashboard.swift; views still never touch this.
    let engine: SessionEngine
    /// Shared clock for live figures and calendar navigation. Production uses
    /// wall time; self-tests advance it without a run loop.
    let now: () -> Date
    let applicationIsRunning: (String) -> Bool
    let activateApplication: (String, Bool) -> Void
    /// Rebuilt with `continuationCandidates` after archive mutations, so Focus
    /// does not repeatedly scan history while composing its headings and rows.
    var continuationIndex: ContinuationPolicy.Index?
    var tracker: AppUsageTracker?
    var usage: AppUsageArchive?
    var ticker: Timer?
    let schedulesTicker: Bool
    /// How many snapshots were actually built. Verification reads it.
    var usageSnapshotComputeCount = 0
    var usageSnapshotCache: (usageID: ObjectIdentifier, revision: Int, second: Int,
                             snapshot: AppUsageSnapshot)?

    init(engine: SessionEngine,
         schedulesTicker: Bool = true,
         metadataArchive: SessionMetadataArchive? = nil,
         ambientPower: AmbientPowerLog? = nil,
         powerMonitor: PowerSourceMonitoring? = nil,
         applicationIsRunning: @escaping (String) -> Bool = {
             !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
         },
         activateApplication: @escaping (String, Bool) -> Void = { bundleID, ignoringOtherApps in
             NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?
                 .activate(options: ignoringOtherApps ? .activateIgnoringOtherApps : [])
         },
         now: @escaping () -> Date = Date.init,
         idle: IdleMonitor = IdleMonitor()) {
        self.idle = idle
        self.engine = engine
        self.workType = engine.store.defaultWorkType
        self.appliedDefaultWorkType = engine.store.defaultWorkType
        engine.archive.streakMinimum = engine.store.streakMinimum
        engine.archive.quickStartWindowDays = engine.store.suggestionWindowDays
        self.menuBarShowsTime = engine.store.menuBarShowsTime
        self.metadataArchive = metadataArchive
            ?? SessionMetadataArchive(directory: engine.archive.dataDirectoryURL)
        self.ambientPower = ambientPower
            ?? AmbientPowerLog(directory: engine.archive.dataDirectoryURL)
        self.powerMonitor = powerMonitor
        let recoveredObservations = engine.store.pendingPowerObservations
        let recoveredTransferError = engine.store.pendingPowerMetadataError
        self.pendingPowerObservations = recoveredObservations
        self.pendingPowerTransfers = engine.store.pendingPowerTransfers
        self.pendingPowerTransferError = recoveredTransferError
        self.powerMetadataError = recoveredObservations.lazy
            .compactMap(\.lastError).first ?? recoveredTransferError
        self.schedulesTicker = schedulesTicker
        self.now = now
        self.applicationIsRunning = applicationIsRunning
        self.activateApplication = activateApplication
        self.automaticActivityRecord = engine.activeAutomaticAction.map {
            AutomaticActivityRecord(action: $0, resultingRecordID: engine.activeRecordID)
        }
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
        powerMonitor?.start { [weak self] observation in
            guard let self else { return }
            // A reading belongs to the running stretch, or to the day.
            if self.engine.state == .idle {
                self.ambientPower.append(observation, now: self.now())
            } else {
                self.enqueuePowerObservation(observation, for: self.engine.activeRecordID)
            }
            self.storyProjectionCache.removeAll(keepingCapacity: true)
            self.storyProjectionCacheOrder.removeAll(keepingCapacity: true)
            self.objectWillChange.send()
        }
        apply(engine.state)
    }

    deinit {
        ticker?.invalidate()
        powerMonitor?.stop()
    }
}
