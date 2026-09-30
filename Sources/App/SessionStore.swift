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
    var lastPowerState: SessionState = .idle
    var lastPowerRecordID: UUID?
    /// Set on machine wake, consumed by the next power reconcile. Sleep is the
    /// one thing that stops the power monitor while the app is alive; a pause,
    /// an Away answer or a lock does not, and the sidecar must not say it did.
    var powerCoverageLapsed = false
    var pendingPowerObservations: [PendingPowerObservation] = []
    var pendingPowerTransfers: [PendingPowerTransfer] = []
    var pendingPowerTransferError: String?

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
    /// The best run on record, for the Awards streak panel.
    @Published private(set) var streakBest = 0
    @Published private(set) var weekBars: [DayBar] = []
    @Published private(set) var quickStarts: [QuickStart] = []
    /// The activities the user pinned, in their order. Refreshed with the
    /// quick starts; edited through the methods below.
    @Published private(set) var savedActivities: [SavedActivity] = []
    @Published var threadsToday: [ThreadSummary] = []
    /// Archive-wide summaries for Focus and Continue Today. Eligibility is
    /// sampled afresh from the paired index when a surface reads them.
    @Published var continuationCandidates: [ThreadSummary] = []
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
    /// The "New sessions start as" value last applied, so only a change to it
    /// replaces the category picked for the next session.
    private var appliedDefaultWorkType: WorkType = .deepWork
    /// Mirrors the preference so the menu bar label, which observes the
    /// store, redraws when it changes.
    @Published var menuBarShowsTime = true

    /// Total tracked computer time today — distinct from `todayTotal`, which is
    /// focused-session time.
    @Published private(set) var trackedToday: TimeInterval = 0
    @Published private(set) var previousSession: SessionRecord?
    @Published var isTrackingEnabled = true
    @Published private(set) var pendingActivityChoice: ActivityQuietChoice?
    @Published private(set) var automaticActivityRecord: AutomaticActivityRecord?
    @Published private(set) var activityAutomationError: String?
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
    @Published private(set) var correctionError: String?
    @Published private(set) var canUndoCorrection = false
    var corrections: [SessionStoreCorrectionState] { engine.fieldCorrections }
    var lastCorrection: SessionStoreCorrectionState? { corrections.last }
    var correctionRetry: SessionCorrectionRetry?

    func publishCorrectionError(_ error: String?) { correctionError = error }
    func publishCanUndoCorrection(_ available: Bool) { canUndoCorrection = available }

    var logGrouping: LogGrouping {
        get { engine.store.logGrouping }
        set {
            engine.store.logGrouping = newValue
            objectWillChange.send()
        }
    }

    /// True while the running session was started by the detector rather than
    /// by hand — the popover labels it, and only these may be undone.
    var isAutoSession: Bool { state != .idle && engine.activeIsAuto }

    var activityOwnership: ActivityOwnership {
        guard engine.state != .idle else { return .none }
        if engine.activeIsAuto,
           let automaticActivityRecord,
           automaticActivityRecord.resultingRecordID == engine.activeRecordID {
            return .automatic(ruleID: automaticActivityRecord.action.ruleID,
                              recordID: engine.activeRecordID)
        }
        return .manual(activityName: engine.sessionName, workType: engine.activeWorkType)
    }

    var hasPendingManualActivityState: Bool {
        hasUnresolvedAwayDecision || engine.state.isPaused
    }

    func presentActivityChoice(_ choice: ActivityQuietChoice?) {
        pendingActivityChoice = choice
    }

    func chooseActivity(ruleID: UUID) { onActivityChoiceSelected?(ruleID) }

    @discardableResult
    func applyAutomaticActivity(_ action: ActivityAutomaticAction) -> AutomaticActivityRecord? {
        guard !hasUnresolvedAwayDecision,
              engine.store.automationMode == .activityRules,
              engine.store.activityRuleVersion == action.ruleVersion,
              engine.store.activityRuleCooldownUntil.map({ now() >= $0 }) ?? true,
              engine.store.activityRules.contains(where: {
                $0.id == action.ruleID && $0.isEnabled && $0.name == action.ruleName
                    && $0.workType == action.workType
              }) else { return nil }

        let applied: Bool
        if let expected = action.expectedRecordID {
            applied = engine.switchAutomatically(action: action, expectedRecordID: expected)
        } else {
            applied = engine.startAutomatically(action: action)
        }
        guard applied else {
            activityAutomationError = engine.awayDecisionError
                ?? "The automatic activity could not be saved. Current work was preserved."
            refresh()
            return nil
        }
        let record = AutomaticActivityRecord(action: action,
                                             resultingRecordID: engine.activeRecordID)
        automaticActivityRecord = record
        activityAutomationError = engine.awayDecisionError
        pendingActivityChoice = nil
        refresh()
        return record
    }

    @discardableResult
    func undoAutomaticActivity(expectedRecordID: UUID) -> Bool {
        guard let record = automaticActivityRecord,
              record.acceptsUndo(for: expectedRecordID),
              engine.activeRecordID == expectedRecordID,
              engine.activeIsAuto, !hasUnresolvedAwayDecision else { return false }
        guard engine.discard() else {
            activityAutomationError = engine.awayDecisionError
                ?? "The automatic activity could not be undone. Current work was preserved."
            refresh()
            return false
        }
        engine.store.activityRuleCooldownUntil = now()
            .addingTimeInterval(FocusConstants.defaultWorkInterval)
        automaticActivityRecord = nil
        activityAutomationError = nil
        refresh()
        return true
    }

    /// The authoritative action boundary for every ordinary session mutation.
    /// Views hide controls while an Away question is pending, but global
    /// shortcuts and future non-visual callers must be rejected here as well.
    /// Read the engine first because its callback publishes `state` on an async
    /// main-queue hop; `pendingAway` additionally covers the side-effect-free
    /// preview route used by the visual harness.
    var hasUnresolvedAwayDecision: Bool {
        if case .awaitingUserDecision = engine.state { return true }
        return pendingAway != nil
    }

    /// Starts a session on the detector's behalf, backdated to when the
    /// qualifying stretch actually began.
    func startAutomatically(workType: WorkType, name: String, backdatedTo: Date,
                            because: String) {
        guard !hasUnresolvedAwayDecision else { return }
        guard replaceSession(workType: workType, intent: name, isAuto: true) else { return }
        engine.backdate(to: backdatedTo)
        refresh()
    }

    /// Undo for an auto-started session: it stops and its record is discarded,
    /// because the app inventing a session is not a thing worth keeping.
    /// Set by the coordinator so an undone session cannot immediately return.
    var onAutoSessionUndone: (() -> Void)?

    @discardableResult
    func undoAutoSession(resumeTracking: Bool = false) -> Bool {
        guard isAutoSession, !hasUnresolvedAwayDecision else { return false }
        let origin = (engine.activeThreadID, engine.sessionStartDate)
        let discarded = engine.discard()
        if let error = engine.awayDecisionError {
            publishCorrectionError(error)
            correctionRetry = .discarding(threadID: origin.0, sessionStart: origin.1, resumeTracking: resumeTracking)
        } else {
            publishCorrectionError(nil)
            correctionRetry = nil
        }
        guard discarded else { refresh(); return false }
        onAutoSessionUndone?()
        if resumeTracking { onAwayEnded?() }
        refresh()
        return true
    }

    /// The Focus correction controls sit at the App boundary because declared
    /// Away owns a coordinator side effect as well as an engine transition.
    /// Resume tracking first, exactly as `I'm back` does, then preserve the
    /// existing adopt/reclassify semantics of `start()`.
    func applyAutomaticSessionCorrection() {
        guard isAutoSession, !hasUnresolvedAwayDecision else { return }
        if isAway {
            // `endAway()` refreshes `workType` from the still-active session.
            // Preserve the user's pending correction across that required
            // tracking-resume path before asking `start()` to apply it.
            let requestedIntent = intent
            let requestedWorkType = workType
            endAway()
            intent = requestedIntent
            workType = requestedWorkType
        }
        // This is a correction of the detector-owned current stretch, not the
        // ordinary Start action. It deliberately claims a same-type automatic
        // stretch even when the person supplies its first real name.
        if engine.wouldAdopt(workType: workType) {
            engine.adopt(intent: intent)
        } else {
            guard replaceSession(workType: workType, intent: intent) else { return }
        }
        engine.store.rememberActivity(name: intent, workType: workType)
        intent = ""
        refresh()
    }

    /// Undo rejects the app's detected session wholesale. Applying
    /// `endAway()` first would legitimately archive long work/Away stretches
    /// and clear automatic ownership before discard can act. Remember only
    /// whether tracking was suspended, discard while ownership is intact, then
    /// resume the App-level tracker exactly once.
    func undoAutomaticSessionCorrection() {
        guard isAutoSession, !hasUnresolvedAwayDecision else { return }
        _ = undoAutoSession(resumeTracking: isAway)
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
    /// The first day with anything recorded, kept per evidence revision. It
    /// bounds day stepping, the date picker and History's journal, which can all
    /// be reached while the dashboard is hidden and not rebuilding, so it is
    /// derived on demand rather than left to that rebuild.
    var earliestDay: Date? {
        get {
            let revision = evidenceRevision
            if let cached = earliestDayCache, cached.revision == revision { return cached.day }
            guard let usage else { return earliestDayCache?.day }
            let day = DashboardStats(sessions: engine.archive, usage: usage,
                                     usageSnapshot: effectiveUsageSnapshot, now: now)
                .earliestRecordedDay()
            earliestDayCache = (revision, day)
            return day
        }
        set { earliestDayCache = (evidenceRevision, newValue) }
    }
    private var earliestDayCache: (revision: EvidenceRevision, day: Date?)?
    /// Archive callbacks rebuild the dashboard only while its window is on
    /// screen. Hidden changes are coalesced until the next appearance.
    var dashboardVisible = false
    var dashboardArchiveRefreshPending = false
    var dashboardLiveTailRefreshPending = false
    var dashboardReadModelDay: Date?
    struct EvidenceRevision: Hashable {
        let day: Date
        let sessions: Int
        let usageID: ObjectIdentifier?
        let usage: Int
        let overlay: Int
        let metadata: Int

        /// True when only app use moved: the live overlay, or a checkpoint
        /// the usage archive can name the days of. Sessions, corrections
        /// and midnight change any day, so those still rebuild.
        func sameArchive(as other: EvidenceRevision) -> Bool {
            day == other.day && sessions == other.sessions && usageID == other.usageID
                && metadata == other.metadata
        }
    }
    var evidenceRevision: EvidenceRevision {
        EvidenceRevision(day: Calendar.current.startOfDay(for: now()),
                         sessions: engine.archive.revision,
                         usageID: usage.map { ObjectIdentifier($0) },
                         usage: usage?.revision ?? -1, overlay: tracker?.overlayRevision ?? -1,
                         metadata: metadataArchive.revision)
    }
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
    private(set) var dashboardReadModelGeneration = 0
    private(set) var dashboardArchiveReadModelGeneration = 0
    private(set) var reviewReadModelGeneration = 0
    private(set) var historyIndexGeneration = 0
    func noteDashboardReadModelRebuild(full: Bool = true) {
        dashboardReadModelGeneration &+= 1
        if full { dashboardArchiveReadModelGeneration &+= 1 }
    }
    func noteReviewReadModelRebuild() { reviewReadModelGeneration &+= 1 }
    func noteHistoryIndexRebuild() { historyIndexGeneration &+= 1 }
    /// Nested archive callbacks join the outer refresh and are consumed once
    /// when its final frame exits.
    var refreshTransactionDepth = 0
    /// The "usual pace" median. Recomputed on refresh rather than every tick:
    /// it walks fourteen days of history and moves at local minute boundaries.
    private var cachedTypical: TimeInterval?
    private var cachedTypicalMinute: Date?
    private struct LiveFrame: Equatable {
        let day: Date
        let minute: Date?
        let archiveRevision: Int
        let usageID: ObjectIdentifier?
        let usageRevision: Int
        let overlayRevision: Int
        let overlays: [AppUsageSession]
        let state: SessionState
        let threadID: UUID?
        let workType: WorkType
        let worked: TimeInterval
        let spanStart: Date?
        let spanEnd: Date?
        let goal: TimeInterval
    }
    private var lastLiveFrame: LiveFrame?

    private func liveFrame(at moment: Date) -> LiveFrame {
        let calendar = Calendar.current
        let span = engine.runningSpan
        return LiveFrame(day: calendar.startOfDay(for: moment),
                         minute: calendar.dateInterval(of: .minute, for: moment)?.start,
                         archiveRevision: engine.archive.revision,
                         usageID: usage.map { ObjectIdentifier($0) },
                         usageRevision: usage?.revision ?? -1,
                         overlayRevision: tracker?.overlayRevision ?? -1,
                         overlays: tracker?.usageOverlaySessions() ?? [],
                         state: engine.state,
                         threadID: engine.state == .idle ? nil : engine.activeThreadID,
                         workType: engine.activeWorkType,
                         worked: engine.state == .idle ? 0 : engine.elapsed,
                         spanStart: span?.start, spanEnd: span?.end,
                         goal: engine.store.dailyGoal)
    }
    /// Worked seconds of the running thread's earlier stretches today. Rebuilt
    /// on refresh; the ticker adds the live stretch each second.
    // Internal for SessionStore+Dashboard.swift, which rebuilds it.
    var threadBaseSeconds: TimeInterval = 0
    /// Counts ticks so the periodic archive flush can run at its own cadence.
    private var tick = 0
    /// Reads one integer per tick. No new timer: the engine is event-driven and
    /// this is the only signal it cannot be told about, because nothing posts a
    /// notification when you *stop* using a machine.
    /// Real HID idle in the product; tests inject `.disabled` so a fixture's
    /// open stretch is not trimmed by however long the build Mac sat untouched.
    private let idle: IdleMonitor
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
    private var pendingWakeActivation: (bundleID: String?, name: String)?
    private var deferredAutomationPending = false
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
    private var ticker: Timer?
    private let schedulesTicker: Bool
    var hasScheduledTicker: Bool { ticker != nil }

    /// The sole read model for live and historical consumers. Pending tracker
    /// records replace durable records by stable UUID in memory; the archive's
    /// bytes and accuracy epoch remain unchanged until a write succeeds.
    ///
    /// Built at most once a second, not once per read. It used to be rebuilt
    /// on every access — a copy and a re-hash of every usage session in the
    /// archive — and one projection of one day reads it several times, while
    /// History read it for every day it showed, every second.
    ///
    /// The archive and the tracker each count their changes, and that pair is
    /// most of the key. It cannot be all of it: the tracker's open segment is
    /// live, its end is the clock, and it grows without any revision moving.
    /// So the clock is in the key too, to the second — the finest grain any
    /// figure in the app is shown at — which keeps a live tail honest while
    /// still collapsing forty reads in one tick into one build. A new second
    /// with unchanged revisions patches the live records into the previous
    /// build rather than copying the whole archive again.
    var effectiveUsageSnapshot: AppUsageSnapshot? {
        guard let usage else { return nil }
        let revision = usage.revision &* 1_000_003 &+ (tracker?.overlayRevision ?? 0)
        let second = Int(now().timeIntervalSinceReferenceDate.rounded(.down))
        if var cached = usageSnapshotCache, cached.revision == revision,
           cached.usageID == ObjectIdentifier(usage) {
            if cached.second == second { return cached.snapshot }
            // Same records, a later second: only the live tail has moved.
            // Released from the cache first so the patch is in place.
            usageSnapshotCache = nil
            if cached.snapshot.replaceOverlay(with: tracker?.usageOverlaySessions() ?? []) {
                cached.second = second
                usageSnapshotCache = cached
                return cached.snapshot
            }
        }
        let snapshot = AppUsageSnapshot(archive: usage, tracker: tracker)
        usageSnapshotCache = (ObjectIdentifier(usage), revision, second, snapshot)
        usageSnapshotComputeCount &+= 1
        return snapshot
    }
    /// How many snapshots were actually built. Verification reads it.
    var usageSnapshotComputeCount = 0
    var usageSnapshotCache: (usageID: ObjectIdentifier, revision: Int, second: Int,
                             snapshot: AppUsageSnapshot)?

    func focusedActiveSeconds(on day: Date,
                              usageSnapshot: AppUsageSnapshot? = nil) -> TimeInterval {
        guard let snapshot = usageSnapshot ?? effectiveUsageSnapshot else { return 0 }
        let calendar = Calendar.current
        let includesRunning = engine.state != .idle
            && calendar.isDate(day, inSameDayAs: now())
        return FocusedActiveTime.seconds(
            on: day, records: engine.archive.records, usage: snapshot.sessions,
            running: includesRunning ? engine.runningSpan : nil,
            runningWork: includesRunning ? engine.elapsedToday() : nil,
            calendar: calendar)
    }

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

    // MARK: - Derived state

    private func apply(_ state: SessionState) {
        self.state = state
        _ = applyLongAwayResult()
        canUndoCorrection = lastCorrection != nil || engine.canUndoAwayDecision
        if case .awaitingUserDecision(let away, _) = state {
            pendingAwayRange = engine.pendingAwayRange
            pendingAway = away
        } else {
            pendingAwayRange = nil
            pendingAway = nil
        }
        refresh()
        onAutomationStateChanged?()
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
        schedulesTicker && ticks ? startTicker() : stopTicker()
    }

    /// Attaches the background usage tracker. Optional: the focus loop works
    /// fully without it, and the gallery drives the store without one.
    func attach(tracker: AppUsageTracker, usage: AppUsageArchive) {
        self.usage?.onDidChange = nil
        self.tracker?.onDidTransition = nil
        self.tracker = tracker
        self.usage = usage
        usage.onDidChange = { [weak self, weak tracker] in
            guard let self else { return }
            if tracker?.isTransitioning == true {
                self.glanceArchiveRefreshPending = true
                self.dashboardArchiveRefreshPending = true
                self.insightsRefreshPending = true
                self.reviewLiveTailRefreshPending = true
            } else {
                self.archiveUsageDidChange()
            }
        }
        tracker.onDidTransition = { [weak self] in self?.trackerDidTransition() }
        self.isTrackingEnabled = tracker.isEnabled
        refresh()
    }

    /// Consume synchronous archive callbacks only after the tracker has reached
    /// its final lifecycle state. This keeps Running Now, the live figures and
    /// the ticker on one post-transition frame.
    private func trackerDidTransition() {
        withRefreshTransaction {
            // Set before the minute refresh: if that path rebuilds visible
            // Insights it clears this flag, avoiding a second rebuild when the
            // transaction is consumed. Same-minute mutations remain pending.
            insightsRefreshPending = true
            updateTimeDrivenFigures()
            updateTicker()
            glanceArchiveRefreshPending = true
            dashboardArchiveRefreshPending = true
            // App use alone patches the days it touched; a session change
            // already pending keeps its full rebuild.
            if reviewVisible {
                refreshReview(rebuildingHistory: reviewRefreshPending)
            } else { reviewLiveTailRefreshPending = true }
        }
    }

    /// Wakes are machine events. Keep sampling on the existing ticker, but do
    /// not let the HID reset count as a return.
    func noteMachineWake() {
        powerCoverageLapsed = true
        presenceGate.noteMachineWake()
        deferredAutomationPending = true
    }

    /// Captures the current frontmost app without delivering an activation. A
    /// later unlock may reveal a newer app than an earlier workspace notice, so
    /// both pending candidates are updated together before confirmation.
    func prepareTrackingResume(bundleID: String?, name: String) {
        withRefreshTransaction {
            tracker?.prepareToResume(bundleID: bundleID, name: name)
            if presenceGate.isAwaitingConfirmation {
                pendingWakeActivation = (bundleID, name)
            }
        }
    }

    /// Unlock and explicit returns are direct proof of presence. A waiting app
    /// candidate begins at this instant; an already-active tracker is unchanged.
    @discardableResult
    func confirmPresence(at moment: Date) -> Bool {
        var releasesAutomation = false
        withRefreshTransaction {
            presenceGate.confirm(at: moment)
            tracker?.confirmPresence(at: moment)
            if let pendingWakeActivation {
                engine.transition(on: .appActivated(bundleID: pendingWakeActivation.bundleID,
                                                    name: pendingWakeActivation.name))
                _ = applyLongAwayResult()
                self.pendingWakeActivation = nil
            }
            if deferredAutomationPending {
                deferredAutomationPending = false
                releasesAutomation = true
            }
        }
        if releasesAutomation { onDeferredAutomationReady?() }
        return releasesAutomation
    }

    /// Workspace activation is not proof of presence after wake. The tracker and
    /// coordinator candidates still follow the latest app, while engine state
    /// and automation remain untouched until the gate is confirmed.
    @discardableResult
    func handleApplicationActivation(bundleID: String?, name: String) -> Bool {
        var delivered = false
        withRefreshTransaction {
            if presenceGate.isAwaitingConfirmation {
                tracker?.prepareToResume(bundleID: bundleID, name: name)
                pendingWakeActivation = (bundleID, name)
            } else {
                tracker?.appActivated(bundleID: bundleID, name: name)
                engine.transition(on: .appActivated(bundleID: bundleID, name: name))
                _ = applyLongAwayResult()
                delivered = true
            }
        }
        return delivered
    }

    /// Recomputes everything the surfaces display. One pass over each archive.
    func refresh() {
        withRefreshTransaction {
            // Fold the in-flight stretch in first, or the frontmost app always looks
            // idle in its own menu.
            tracker?.flush()
            // First, so every figure below is computed under the current settings.
            applyPreferences()
            let moment = now()
            refreshTypical(at: moment)
            refreshThread()
            refreshContinuations()
            refreshLiveFigures(at: moment)
            reconcilePowerBoundaries()
            refreshSessionMetadataRetention()

            weekBars = engine.archive.weekBars()
            // A recent name that is only a category's name repeats the
            // category picker beside the field, so it is not offered.
            let categoryNames = Set(WorkType.allCases.map { SavedActivities.key($0.displayName) })
            quickStarts = ActivityChoices.merging(engine.store.recentActivities,
                engine.archive.quickStarts(limit: ActivityChoices.limit))
                .filter { !categoryNames.contains(SavedActivities.key($0.name)) }
            savedActivities = engine.store.savedActivities
            // A running session shows its own category; while idle, the one the
            // user picked for the next session stays picked.
            if engine.state != .idle { workType = engine.activeWorkType }
            automaticActivityRecord = engine.activeAutomaticAction.map {
                AutomaticActivityRecord(action: $0, resultingRecordID: engine.activeRecordID)
            }
            previousSession = engine.archive.records.last
            isTrackingEnabled = tracker?.isEnabled ?? false
            glanceArchiveRefreshPending = true
            dashboardArchiveRefreshPending = true
            if reviewVisible {
                reviewLiveTailRefreshPending = false
                refreshReview()
            } else { reviewRefreshPending = true }
            if insightsVisible { refreshInsights() } else { insightsRefreshPending = true }
            refreshBreak()
            updateTicker()
        }
    }

    /// Every figure that moves second by second, in one place.
    ///
    /// These used to be split: the ticker advanced `elapsed` while `goal`,
    /// `streak` and `longestToday` were only rebuilt on a state change. With the
    /// popover open — exactly when someone is comparing them — the goal bar sat
    /// frozen at whatever it read when the panel opened while the timer directly
    /// beneath it counted on, so the two disagreed by however long you looked.
    private func refreshLiveFigures(at moment: Date? = nil) {
        let moment = moment ?? now()
        // Subscribers can synchronously correct evidence during publication.
        // Cache the frame we read, not a newer revision raised by an observer.
        let consumedFrame = liveFrame(at: moment)
        let usageSnapshot = effectiveUsageSnapshot
        // `engine.state`, not the published mirror: `state` is updated on an
        // async hop, and several callers refresh synchronously right after
        // mutating the engine, when the mirror still says `.idle`.
        let inFlight = engine.elapsedToday()
        // Each write is guarded: a `@Published` assignment notifies every
        // observer even when the value is equal, and this runs every second.
        publish(\.elapsed, engine.elapsed)
        // Gated on state: the engine's `elapsed` keeps counting from the last
        // start after a stop, because nothing reads it when idle — this does.
        publish(\.threadElapsed, engine.state == .idle ? 0 : threadBaseSeconds + elapsed)
        publish(\.todayTotal, engine.todayTotal)
        publish(\.sessionsToday, engine.sessionsToday)
        publish(\.longestToday, engine.longestToday)
        publish(\.streak, engine.archive.currentStreak(includingToday: inFlight))
        publish(\.streakBest, engine.archive.bestStreak())
        publish(\.goal, GoalProgress(goal: engine.store.dailyGoal,
                            achieved: DailyGoal(archive: engine.archive,
                                                goal: engine.store.dailyGoal,
                                                // Only today's records: the goal
                                                // clips to today, and history is uncapped.
                                                usage: usageSnapshot?.sessions(touching: moment) ?? [],
                                                usageAccurateFrom: usageSnapshot?.accurateFrom,
                                                running: engine.runningSpan,
                                                runningWork: inFlight,
                                                now: { moment },
                                                windowDays: engine.store.paceWindowDays)
                                .achievedToday(),
                            typical: cachedTypical))
        // Re-read rather than adding the open stretch to a cached total. The
        // cached version missed every segment that opened *and closed* between
        // refreshes, so the figure went backwards on each app switch.
        if let usageSnapshot {
            publish(\.trackedToday, usageSnapshot.total(on: moment))
        }
        lastLiveFrame = consumedFrame
    }

    /// The runtime copies of preferences, so a change in Settings — which ends
    /// in `refresh()` — applies at once instead of at the next launch.
    private func applyPreferences() {
        engine.archive.streakMinimum = engine.store.streakMinimum
        engine.archive.quickStartWindowDays = engine.store.suggestionWindowDays
        publish(\.menuBarShowsTime, engine.store.menuBarShowsTime)
        // Only while idle: during a session the picker shows that session's
        // category, and a new default waits until the session ends.
        let defaultWorkType = engine.store.defaultWorkType
        if engine.state == .idle, defaultWorkType != appliedDefaultWorkType {
            appliedDefaultWorkType = defaultWorkType
            workType = defaultWorkType
        }
    }

    private func publish<Value: Equatable>(_ property: ReferenceWritableKeyPath<SessionStore, Value>,
                                           _ value: Value) {
        if self[keyPath: property] != value { self[keyPath: property] = value }
    }

    private func refreshTypical(at moment: Date) {
        let usageSnapshot = effectiveUsageSnapshot
        cachedTypical = DailyGoal(archive: engine.archive,
                                  goal: engine.store.dailyGoal,
                                  usage: usageSnapshot?.sessions ?? [],
                                  usageAccurateFrom: usageSnapshot?.accurateFrom,
                                  running: engine.runningSpan,
                                  now: { moment },
                                  windowDays: engine.store.paceWindowDays).typical()
        cachedTypicalMinute = Calendar.current.dateInterval(of: .minute,
                                                            for: moment)?.start
    }

    /// The time-driven part of the one existing ticker. Historical pace is
    /// recalculated once on each local minute boundary; the inexpensive live
    /// figures continue to move every second.
    func updateTimeDrivenFigures() {
        withRefreshTransaction {
            let moment = now()
            let frame = liveFrame(at: moment)
            let minute = Calendar.current.dateInterval(of: .minute, for: moment)?.start
            let minuteChanged = minute != cachedTypicalMinute
            guard frame != lastLiveFrame || minuteChanged else { return }
            if minuteChanged { refreshTypical(at: moment) }
            refreshLiveFigures(at: moment)
            let revision = evidenceRevision
            if dashboardEvidenceRevision != revision { dashboardArchiveRefreshPending = true }
            // App use alone is patched into the days it touched; anything
            // else is a full rebuild. Read before the tracker's own refresh,
            // so this decides which one a checkpoint gets.
            if reviewEvidenceRevision?.sameArchive(as: revision) != true {
                reviewRefreshPending = true
            } else if reviewEvidenceRevision != revision {
                reviewLiveTailRefreshPending = true
            }
            // Open tails genuinely advance each second; an idle archive does
            // not. Keep live data current without republishing large unchanged
            // Dashboard/History read models at rest.
            let hasLiveTail = engine.state != .idle || tracker?.currentBundleID != nil
            if hasLiveTail && dashboardVisible { dashboardLiveTailRefreshPending = true }
            if hasLiveTail && reviewVisible {
                reviewLiveTailRefreshPending = true
            }
            if minuteChanged && insightsVisible { refreshInsights() }
        }
    }

    // MARK: - Break reminders

    /// Continuous computer use, session or not: the case that hurts is grinding
    /// for hours without ever pressing Start.
    private func refreshBreak() {
        guard let usageSnapshot = effectiveUsageSnapshot,
              engine.store.remindersEnabled,
              remindersPausedByCategory == nil else {
            breakCountdown = 0
            isBreakDue = false
            nextBreakTier = nil
            return
        }
        let moment = Date()
        let result = BreakReminder.evaluate(usageSnapshot.sessions, now: moment,
                                            last: engine.store.lastBreakNotice,
                                            tiers: BreakTier.allCases.filter(engine.store.enabledBreakTiers.contains))
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

    /// The running category that has asked not to be interrupted, or nil.
    var remindersPausedByCategory: WorkType? {
        guard engine.state != .idle, !engine.activeWorkType.remindsBreaks else { return nil }
        return engine.activeWorkType
    }

    /// How long an absence has to be before the app asks about it rather than
    /// quietly leaving it out.
    var breakThreshold: TimeInterval { engine.breakThreshold }

    /// And how long before it stops asking and simply ends the session.
    var longAwayCap: TimeInterval { engine.store.longAwayCap }

    /// `Look away in 3m`, or `Break due` once one is. Names the kind of break so
    /// a thirty-second look-away is not mistaken for a quarter of an hour off.
    var breakLabel: String {
        guard remindersEnabled else { return "Reminders off" }
        if let paused = remindersPausedByCategory { return "No reminders during \(paused.displayName)" }
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
            confirmPresence(at: since)
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

    /// The app's one repeating timer: it observes presence, drives engine
    /// transitions, persists checkpoints, updates live figures and evaluates
    /// breaks. It is operational state machinery, not a cosmetic title timer.
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
                if self.tracker?.openSeconds(
                    exceeds: TimeInterval(SessionStore.flushEverySeconds)) == true {
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
            self.updateTimeDrivenFigures()
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

    /// The sole start/stop route for the global shortcut. An unresolved Away
    /// question is evidence awaiting classification, not a running state the
    /// shortcut may stop. The coordinator uses the returned route to re-present
    /// the existing answer surface; no second decision UI is introduced.
    @discardableResult
    func performSessionHotKeyAction() -> SessionHotKeyActionResult {
        guard !hasUnresolvedAwayDecision else { return .showAwayDecision }
        if engine.state == .idle {
            // The category the picker shows, as the Start button would use.
            guard replaceSession(workType: workType, intent: "") else { return .saveFailed }
            refresh()
            return .started
        }
        let origin = (engine.activeThreadID, engine.sessionStartDate)
        let stopped = engine.stop()
        let finalisationPending = stopped && engine.awayDecisionError != nil
        if !stopped || finalisationPending { retainEndingRetry(origin: origin) }
        refresh()
        return stopped ? (finalisationPending ? .stoppedPendingFinalisation : .stopped) : .saveFailed
    }

    /// Pressing Start continues a session already running on the same kind of
    /// work — including one the app started by itself — and only begins a new
    /// one when the work type differs. Background recording is unaffected
    /// either way: app usage is captured all day regardless of sessions.
    func start() {
        guard !hasUnresolvedAwayDecision else { return }
        if engine.wouldAdopt(workType: workType, intent: intent) {
            engine.adopt(intent: intent)
        } else {
            guard replaceSession(workType: workType, intent: intent) else { return }
        }
        engine.store.rememberActivity(name: intent, workType: workType)
        // Remember the pairing of the app in front and the category chosen,
        // so starting from that app next time suggests this category.
        engine.store.rememberCategoryChoice(workType, for: tracker?.currentBundleID)
        intent = ""
        refresh()
    }

    func startQuick(_ quick: QuickStart) {
        guard !hasUnresolvedAwayDecision else { return }
        workType = quick.workType
        if engine.wouldAdopt(workType: quick.workType, intent: quick.name) {
            engine.adopt(intent: quick.name)
        } else {
            guard replaceSession(workType: quick.workType, intent: quick.name) else { return }
        }
        engine.store.rememberActivity(name: quick.name, workType: quick.workType)
        intent = ""
        refresh()
    }

    /// Drives the Start button's label, so the button says what it will do.
    var startWouldContinue: Bool { engine.wouldAdopt(workType: workType, intent: intent) }

    // MARK: - Saved activities

    /// Recent names not already pinned, for the menu's second group.
    var recentActivities: [QuickStart] {
        SavedActivities.recents(quickStarts, excluding: savedActivities)
    }

    /// Whether one more can be pinned.
    var canPinActivity: Bool { savedActivities.count < SavedActivities.limit }

    /// Adds or updates a pinned activity. A matching id replaces in place; a
    /// new one goes at the end. False when the list is full or the name is
    /// blank or already pinned under another id.
    @discardableResult
    func saveActivity(_ activity: SavedActivity) -> Bool {
        var items = engine.store.savedActivities
        let name = SavedActivities.normalisedName(activity.name)
        guard !name.isEmpty, activity.workType.countsAsFocus else { return false }
        let taken = items.contains { $0.id != activity.id && SavedActivities.key($0.name) == SavedActivities.key(name) }
        guard !taken else { return false }
        if let index = items.firstIndex(where: { $0.id == activity.id }) {
            items[index] = SavedActivity(id: activity.id, name: name, workType: activity.workType)
        } else {
            guard items.count < SavedActivities.limit else { return false }
            items.append(SavedActivity(id: activity.id, name: name, workType: activity.workType))
        }
        engine.store.savedActivities = items
        savedActivities = engine.store.savedActivities
        return true
    }

    /// Pins a recent name as it was last used.
    @discardableResult
    func pinActivity(_ quick: QuickStart) -> Bool {
        saveActivity(SavedActivity(name: quick.name, workType: quick.workType))
    }

    func removeSavedActivity(id: UUID) {
        engine.store.savedActivities = engine.store.savedActivities.filter { $0.id != id }
        savedActivities = engine.store.savedActivities
    }

    /// Moves one row up or down by one place.
    func moveSavedActivity(id: UUID, up: Bool) {
        var items = engine.store.savedActivities
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
        engine.store.savedActivities = items
        savedActivities = engine.store.savedActivities
    }

    /// Fills the field from a pinned activity. Never starts anything.
    func chooseActivity(_ activity: SavedActivity) {
        intent = activity.name
        workType = activity.startableWorkType
    }

    func stop() {
        guard !hasUnresolvedAwayDecision else { return }
        let thread = engine.activeThreadID, start = engine.sessionStartDate
        engine.stop()
        if let error = engine.awayDecisionError {
            publishCorrectionError(error)
            correctionRetry = .ending(threadID: thread, sessionStart: start)
        } else {
            publishCorrectionError(nil)
            correctionRetry = nil
        }
        refresh()
    }

    private func retainEndingRetry(origin: (threadID: UUID, sessionStart: Date)) {
        publishCorrectionError(engine.awayDecisionError)
        correctionRetry = .ending(threadID: origin.threadID, sessionStart: origin.sessionStart)
    }

    /// Every app-level replacement retains the originating save action before
    /// changing live identity. Callers perform their existing eligibility gate
    /// first, and only activate apps/clear drafts/backdate after true success.
    @discardableResult
    func replaceSession(workType: WorkType, intent: String, threadID: UUID = UUID(), isAuto: Bool = false) -> Bool {
        let origin = (engine.activeThreadID, engine.sessionStartDate)
        let started = engine.start(workType: workType, intent: intent, threadID: threadID, isAuto: isAuto)
        let retry = SessionCorrectionRetry.ending(threadID: origin.0, sessionStart: origin.1)
        let unfinishedEnding = engine.awayDecisionError != nil
            && engine.decisionHistory.document.pending.map { retry.matches($0) } == true
        if !started || unfinishedEnding { retainEndingRetry(origin: origin) }
        if !started { refresh() }
        return started
    }

    func togglePause() {
        guard !hasUnresolvedAwayDecision else { return }
        let resumable = !engine.state.isRunning && engine.state != .idle
        engine.transition(on: resumable ? .manualResume : .manualPause)
        _ = applyLongAwayResult()
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
        if applyLongAwayResult(resumeTracking: true) != false { onAwayEnded?() }
        refresh()
    }

    @discardableResult
    func applyLongAwayResult(resumeTracking: Bool = false) -> Bool? {
        guard let result = engine.lastLongAwayTransition else { return nil }
        let shouldResumeTracking: Bool
        if case .longAway(let current, let retained)? = correctionRetry, current == result.request {
            shouldResumeTracking = resumeTracking || retained
        } else {
            shouldResumeTracking = resumeTracking
        }
        switch result.outcome {
        case .completed:
            if case .longAway(let current, _)? = correctionRetry, current == result.request {
                publishCorrectionError(nil)
                correctionRetry = nil
            }
        case .pendingFinalisation(let error), .refused(let error):
            publishCorrectionError(error)
            correctionRetry = .longAway(result.request, resumeTracking: shouldResumeTracking)
        }
        return result.outcome.applied
    }

    /// True while the user has declared themselves away, as opposed to having
    /// paused a session they are still sitting in front of.
    var isAway: Bool {
        if case .paused(.away) = state { return true }
        return false
    }

    /// `label` names a break in the user's words ("dinner"); it is ignored for
    /// any other answer.
    @discardableResult
    func resolve(_ decision: UserDecision, label: String? = nil, expectedID: UUID? = nil) -> Bool {
        applyAwayDecision(decision, label: label, reviewing: false, expectedID: expectedID)
    }

    var pendingAwaySaveError: String? {
        guard case .awayDecision(_, _, let reviewing, let id)? = correctionRetry,
              !reviewing, engine.pendingDecisionID == id else { return nil }
        return correctionError
    }

    @discardableResult
    func retryPendingAwayDecision(expectedID: UUID?) -> Bool {
        guard let expectedID, engine.pendingDecisionID == expectedID,
              case .awayDecision(let decision, let label, let reviewing, let id)? = correctionRetry,
              !reviewing, id == expectedID else { return false }
        return applyAwayDecision(decision, label: label, reviewing: false, expectedID: expectedID)
    }

    @discardableResult
    func applyAwayDecision(_ decision: UserDecision, label: String? = nil, reviewing: Bool,
                           expectedID: UUID? = nil) -> Bool {
        let currentID = reviewing ? (expectedID.flatMap { engine.awayDecision(id: $0)?.id }
            ?? (expectedID == nil ? engine.lastAwayDecision?.id : nil)) : engine.pendingDecisionID
        guard let id = currentID, expectedID == nil || expectedID == id else {
            if reviewing || expectedID != nil {
                publishCorrectionError("That interval was retired or changed. The current record was not changed.")
                correctionRetry = nil
            }
            return false
        }
        let saved = reviewing ? engine.reviseAwayDecision(decision, label: label, expectedID: id)
            : engine.decide(decision, label: label)
        guard saved else {
            if let error = engine.awayDecisionError {
                publishCorrectionError(error)
                correctionRetry = .awayDecision(decision, label: label, reviewing: reviewing, expectedID: id)
            }
            return false
        }
        correctionRetry = nil
        publishCorrectionError(nil)
        publishCanUndoCorrection(engine.lastAwayDecision?.isResolved == true)
        apply(engine.state)
        return true
    }

    @discardableResult
    func undoAwayDecision(expectedID: UUID? = nil) -> Bool {
        guard let id = expectedID.flatMap({ engine.awayDecision(id: $0)?.id })
            ?? (expectedID == nil ? engine.lastAwayDecision?.id : nil) else {
            if expectedID != nil {
                publishCorrectionError("That Undo belongs to an earlier action. The current record was not changed.")
                correctionRetry = nil
            }
            return false
        }
        guard engine.undoAwayDecision(expectedID: id) else {
            publishCorrectionError(engine.awayDecisionError ?? "Finish the current away decision before undoing an earlier one.")
            correctionRetry = .awayUndo(id)
            return false
        }
        correctionRetry = nil
        publishCorrectionError(nil)
        publishCanUndoCorrection(false)
        apply(engine.state)
        return true
    }

    /// Names the break a resolved away decision wrote, and republishes the day.
    @discardableResult
    func nameBreak(decisionID: UUID, titled name: String) -> Bool {
        guard engine.nameBreak(decisionID: decisionID, to: name) else {
            publishCorrectionError(engine.awayDecisionError ?? "The break could not be renamed.")
            return false
        }
        publishCorrectionError(nil)
        apply(engine.state)
        return true
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
