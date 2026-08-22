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
    @Published private(set) var todayTotal: TimeInterval = 0
    @Published private(set) var streak = 0
    @Published private(set) var weekBars: [DayBar] = []
    @Published private(set) var quickStarts: [QuickStart] = []
    @Published private(set) var threadsToday: [ThreadSummary] = []
    @Published private(set) var goal = GoalProgress(
        goal: FocusConstants.defaultDailyGoal, achieved: 0, typical: nil)
    @Published private(set) var sessionsToday = 0
    @Published private(set) var longestToday: TimeInterval = 0
    @Published private(set) var pendingAway: TimeInterval?

    /// Two-way bound by the popover's intent field and work-type picker.
    @Published var intent: String = ""
    @Published var workType: WorkType = .deepWork

    /// Side effect for an unresolved absence (notification). The store owns the
    /// engine's single `onNeedsDecision` slot, so extra observers hang off here
    /// rather than overwriting it.
    var onAwayNeedsResolution: ((TimeInterval) -> Void)?

    /// Total tracked computer time today — distinct from `todayTotal`, which is
    /// focused-session time.
    @Published private(set) var trackedToday: TimeInterval = 0
    @Published private(set) var previousSession: SessionRecord?
    @Published private(set) var isTrackingEnabled = true

    // MARK: Dashboard

    @Published private(set) var rankedApps: [AppRank] = []
    @Published private(set) var timelineSegments: [TimelineSegment] = []
    @Published private(set) var focusBrackets: [(start: Date, end: Date)] = []
    @Published private(set) var runningApps: [RunningApp] = []
    @Published private(set) var insights: [Insight] = []
    /// Today's figures, for the menu bar. Separate from the day-scoped ones
    /// above because the dashboard may be browsing history while this panel must
    /// still answer "how am I doing right now". They shared one `dayOffset`, so
    /// stepping the dashboard back to Yesterday quietly re-scoped the menu bar
    /// too — and it stayed there until the process was quit.
    @Published private(set) var glanceApps: [AppRank] = []
    @Published private(set) var glanceInsights: [Insight] = []
    @Published private(set) var glanceTimeline: [TimelineSegment] = []
    @Published private(set) var focusQuality = FocusQuality(byWorkType: [],
                                                            insideSessionShare: 0,
                                                            switchesPerSession: 0,
                                                            sessionCount: 0)
    @Published private(set) var trackedForSelectedDay: TimeInterval = 0
    /// Baselines for the stat band's context lines: the day before the selected
    /// day, and the period before the selected period.
    @Published private(set) var trackedYesterday: TimeInterval = 0
    @Published private(set) var previousPeriodTracked: TimeInterval = 0
    /// The focus-session figures for a browsed day. On today the live ones are
    /// used instead, because they include the running session and move every
    /// second; these are rebuilt with the dashboard and cover the archive only.
    /// Without them the stat row on Yesterday read yesterday's Tracked beside
    /// today's Sessions, Focused and Longest — four figures, two days.
    @Published private(set) var sessionsForSelectedDay = 0
    @Published private(set) var focusedForSelectedDay: TimeInterval = 0
    @Published private(set) var longestForSelectedDay: TimeInterval = 0
    @Published private(set) var longestNameForSelectedDay: String?
    /// 0 = today, 1 = yesterday, and so on back through history.
    @Published private(set) var dayOffset = 0

    /// Timeline inspection. Both are single optionals, so hovering allocates nothing.
    @Published private(set) var hoveredSegment: TimelineSegment?
    @Published private(set) var selectedSegment: TimelineSegment?
    @Published private(set) var stretchesInSelectedHour: [TimelineSegment] = []
    /// Apps whose Top-apps row is expanded to show individual stretches.
    @Published private(set) var expandedApps: Set<String> = []
    /// Apps used today that are not running now, each with its stretches.
    @Published private(set) var earlierToday: [AppDayHistory] = []

    var timelineWindow: (start: Date, end: Date)? { cachedWindow }
    /// Owns every timeline coordinate. Views ask it for positions.
    private(set) var timelineLayout: TimelineLayout?
    /// Today's coordinates, for the menu bar. Same reason as `glanceApps`.
    private(set) var glanceLayout: TimelineLayout?

    // MARK: Periods
    @Published private(set) var periodDays: [PeriodDay] = []
    @Published private(set) var periodLog: [LogEntry] = []
    @Published private(set) var periodAppGroups: [LogAppGroup] = []
    @Published private(set) var periodDayTotals: [Date: TimeInterval] = [:]
    @Published private(set) var periodSummary = PeriodSummary(tracked: 0, activeDays: 0,
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

    /// Bounds of the selected period, for charts that must show empty days too.
    var periodBounds: (start: Date, end: Date)? {
        guard let usage else { return nil }
        let bounds = PeriodStats(sessions: engine.archive, usage: usage)
            .bounds(for: period, containing: selectedDay)
        // `end` is exclusive; charts want the last day that exists.
        return (bounds.start, bounds.end.addingTimeInterval(-1))
    }

    var period: TrackingPeriod {
        get { engine.store.trackingPeriod }
        set {
            engine.store.trackingPeriod = newValue
            refreshDashboard()
        }
    }

    /// Figures for the stat band, shaped by the selected period. Every card
    /// carries a context line; a bare number was the old row's failure.
    var statFigures: [StatFigure] {
        switch period {
        case .day:
            let sessions = isToday ? sessionsToday : sessionsForSelectedDay
            let focused = isToday ? todayTotal : focusedForSelectedDay
            let longest = isToday ? longestToday : longestForSelectedDay
            let longestName = isToday ? longestNameToday : longestNameForSelectedDay
            let tracked = trackedForSelectedDay
            let delta = SessionStore.deltaLine(tracked, against: trackedYesterday,
                                               label: "yesterday")
            let insideShare = focusQuality.insideSessionShare
            let top = focusQuality.byWorkType.first
            return [
                StatFigure(label: "Tracked", value: Tokens.duration(tracked),
                           detail: delta?.text,
                           tint: delta?.up == true ? Tokens.Palette.app(rank: 1) : nil),
                StatFigure(label: "Sessions", value: "\(sessions)",
                           detail: longest > 0
                               ? "longest \(Tokens.preciseDuration(longest))"
                                 + (longestName.map { " · \($0)" } ?? "")
                               : nil),
                StatFigure(label: "Focused", value: Tokens.duration(focused),
                           detail: tracked > 0 && focused > 0
                               ? "\(Int((insideShare * 100).rounded()))% of tracked" : nil),
                // The share is the number; the kind of work it was, and the
                // churn, are its context. "Deep work 100%" as a value
                // truncated on every card width that fits four across.
                StatFigure(label: "Quality",
                           value: top.map { "\(Int(($0.share * 100).rounded()))%" } ?? "—",
                           detail: top.map {
                               "\($0.workType.displayName) · "
                               + String(format: "%.1f switches / session",
                                        focusQuality.switchesPerSession)
                           })
            ]
        case .week, .month:
            let delta = SessionStore.deltaLine(periodSummary.tracked,
                                               against: previousPeriodTracked,
                                               label: period == .week ? "last week" : "last month")
            return [
                StatFigure(label: "Tracked", value: Tokens.duration(periodSummary.tracked),
                           detail: delta?.text,
                           tint: delta?.up == true ? Tokens.Palette.app(rank: 1) : nil),
                StatFigure(label: "Active days",
                           value: "\(periodSummary.activeDays) of \(periodSummary.totalDays)"),
                StatFigure(label: "Average / day",
                           value: Tokens.duration(periodSummary.averagePerActiveDay),
                           detail: "across active days"),
                StatFigure(label: "Longest stretch",
                           value: periodSummary.longest.map {
                               Tokens.preciseDuration($0.attended)
                           } ?? "—",
                           detail: periodSummary.longest?.appName)
            ]
        }
    }

    /// `+3h 5m vs yesterday`, or nil when there is no baseline — a delta
    /// against nothing is not information.
    static func deltaLine(_ value: TimeInterval, against baseline: TimeInterval,
                          label: String) -> (text: String, up: Bool)? {
        guard baseline > 0, value > 0 else { return nil }
        let delta = value - baseline
        guard abs(delta) >= 60 else { return ("same as \(label)", false) }
        return ((delta > 0 ? "+" : "−") + Tokens.duration(abs(delta)) + " vs \(label)",
                delta > 0)
    }

    /// What today's longest focus session was: the running one if it leads,
    /// else the archived record's intent. Nil when nothing has run.
    private var longestNameToday: String? {
        let archived = engine.archive.longestRecord(on: Date())
        let running = engine.elapsedToday()
        if state != .idle, running > 0, running >= (archived?.seconds ?? 0) {
            return activeIntent
        }
        guard let archived else { return nil }
        return archived.record.name.isEmpty ? "Focus session" : archived.record.name
    }

    /// True while the running session was started by the detector rather than
    /// by hand — the popover labels it, and only these may be undone.
    var isAutoSession: Bool { state != .idle && engine.activeIsAuto }

    /// Starts a session on the detector's behalf, backdated to when the
    /// qualifying stretch actually began.
    func startAutomatically(workType: WorkType, backdatedTo: Date, because: String) {
        engine.start(workType: workType, intent: "", isAuto: true)
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

    /// Calendar day-stepping, not 86 400-second arithmetic: on the two days a
    /// year that are 23 or 25 hours long, subtracting seconds lands the label
    /// on the wrong day for anyone browsing near midnight.
    var selectedDay: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
    }
    var dayLabel: String { Tokens.dayLabel(selectedDay) }
    var isToday: Bool { dayOffset == 0 }
    var canStepForward: Bool { dayOffset > 0 }
    var canStepBack: Bool {
        guard let earliest = earliestDay else { return false }
        return Calendar.current.startOfDay(for: selectedDay) > earliest
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

    private var cachedWindow: (start: Date, end: Date)?
    private var earliestDay: Date?
    /// The "usual pace" median. Recomputed on refresh rather than every tick:
    /// it walks fourteen days of history and only moves as the hour does.
    private var cachedTypical: TimeInterval?
    /// Counts ticks so the periodic archive flush can run at its own cadence.
    private var tick = 0
    /// Reads one integer per tick. No new timer: the engine is event-driven and
    /// this is the only signal it cannot be told about, because nothing posts a
    /// notification when you *stop* using a machine.
    private let idle = IdleMonitor()

    private let engine: SessionEngine
    private var tracker: AppUsageTracker?
    private var usage: AppUsageArchive?
    private var ticker: Timer?

    init(engine: SessionEngine) {
        self.engine = engine
        engine.onStateChanged = { [weak self] state in
            DispatchQueue.main.async { self?.apply(state) }
        }
        engine.onNeedsDecision = { [weak self] away, _ in
            DispatchQueue.main.async {
                self?.pendingAway = away
                self?.onAwayNeedsResolution?(away)
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
            pendingAway = away
        } else {
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
        if tracker?.currentBundleID != nil { return true }
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
            trackedToday = usage.totalToday() + (tracker?.openSeconds() ?? 0)
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

    func selectDay(offset: Int) {
        dayOffset = max(0, offset)
        clearTimelineSelection()
        refreshDashboard()
    }

    /// Negative steps go back in time. Bounded so navigation can never land on a
    /// day with no data behind it, or in the future.
    func stepDay(by delta: Int) {
        let proposed = dayOffset - delta
        guard proposed >= 0 else { return }
        if delta < 0, let earliest = earliestDay {
            let calendar = Calendar.current
            guard let candidate = calendar.date(byAdding: .day, value: -proposed,
                                                to: Date()),
                  calendar.startOfDay(for: candidate) >= earliest else { return }
        }
        selectDay(offset: proposed)
    }

    func goToToday() { selectDay(offset: 0) }

    // MARK: - Timeline inspection

    /// `fraction` is the pointer's position across the band, 0...1. Nil clears.
    func hoverTimeline(at fraction: Double?) {
        guard let fraction, let layout = timelineLayout, let usage,
              // Over an elided separator there is nothing to name.
              let date = layout.date(at: min(max(fraction, 0), 1)) else {
            if hoveredSegment != nil { hoveredSegment = nil }
            return
        }
        let found = DashboardStats(sessions: engine.archive, usage: usage)
            .segment(at: date, on: selectedDay)
        // Only publish on a real change, or every mouse move redraws the band.
        if found?.id != hoveredSegment?.id { hoveredSegment = found }
    }

    /// Clicking the same segment again closes it: the detail row is a toggle.
    func selectTimeline(at fraction: Double) {
        hoverTimeline(at: fraction)
        if selectedSegment?.id == hoveredSegment?.id {
            clearTimelineSelection()
            return
        }
        selectedSegment = hoveredSegment
        guard let selected = selectedSegment, let usage else {
            stretchesInSelectedHour = []
            return
        }
        // The chosen segment's hour, so the detail row stays bounded no matter
        // how busy the day was.
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: selected.start)?.start
            ?? selected.start
        let hourEnd = hourStart.addingTimeInterval(3_600)
        stretchesInSelectedHour = DashboardStats(sessions: engine.archive, usage: usage)
            .stretches(for: selectedDay, bundleID: selected.bundleID)
            .filter { $0.start < hourEnd && $0.end > hourStart }
    }

    func clearTimelineSelection() {
        selectedSegment = nil
        stretchesInSelectedHour = []
    }

    func toggleExpanded(_ bundleID: String) {
        if expandedApps.contains(bundleID) {
            expandedApps.remove(bundleID)
        } else {
            expandedApps.insert(bundleID)
        }
    }

    /// Grouped sittings for one app on the selected day.
    func sessions(for bundleID: String) -> [AppSession] {
        guard let usage else { return [] }
        return DashboardStats(sessions: engine.archive, usage: usage)
            .sessions(for: selectedDay, bundleID: bundleID)
            .sorted { $0.start > $1.start }
    }

    /// Minutes per hour for one app, for the drill-down strip.
    func hourlyBuckets(for bundleID: String) -> [HourBucket] {
        guard let usage else { return [] }
        return DashboardStats(sessions: engine.archive, usage: usage)
            .hourlyBuckets(for: selectedDay, bundleID: bundleID)
    }

    /// `9:02 am – 4:41 pm` for one app on the selected day.
    func span(for bundleID: String) -> (start: Date, end: Date)? {
        guard let usage else { return nil }
        return DashboardStats(sessions: engine.archive, usage: usage)
            .span(for: selectedDay, bundleID: bundleID)
    }

    /// Rebuilds every dashboard figure from the two archives in one pass.
    private func refreshDashboard() {
        guard let usage else { return }
        let stats = DashboardStats(sessions: engine.archive, usage: usage)
        let day = selectedDay

        rankedApps = stats.rankedApps(for: day)
        timelineSegments = stats.timeline(for: day)
        cachedWindow = stats.timelineWindow(for: day)
        timelineLayout = TimelineLayout(segments: timelineSegments)
        focusBrackets = stats.focusSessions(for: day).map { ($0.start, $0.end) }
        var qualityStats = stats
        qualityStats.activeWorkType = engine.activeWorkType
        focusQuality = qualityStats.focusQuality(
            for: day,
            // Keep this in step with `sessionsToday`: without it the same screen
            // reads "1 session today" and "No sessions yet today".
            runningSeconds: (state != .idle && dayOffset == 0) ? engine.elapsed : nil)
        insights = stats.insights(for: day)
        trackedForSelectedDay = stats.trackedTotal(for: day)
        trackedYesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)
            .map { stats.trackedTotal(for: $0) } ?? 0
        sessionsForSelectedDay = engine.archive.focusCount(on: day)
        focusedForSelectedDay = engine.archive.workSeconds(on: day)
        let longest = engine.archive.longestRecord(on: day)
        longestForSelectedDay = longest?.seconds ?? 0
        longestNameForSelectedDay = longest.map {
            $0.record.name.isEmpty ? "Focus session" : $0.record.name
        }
        earliestDay = stats.earliestRecordedDay()

        // A month is 31 day-slices, each one pass over the usage array. One
        // rollup call walks them once; asking for the pieces separately walked
        // them three times and cost 16 MB of churn.
        let threadStats = ThreadStats(sessions: engine.archive, usage: usage,
                                      purposeOverrides: engine.store.purposeOverrides)
        threadsToday = threadStats.threads(on: Date(), running: runningThread())

        let rollup = PeriodStats(sessions: engine.archive, usage: usage)
            .rollup(for: period, containing: day)
        periodDays = rollup.days
        periodLog = rollup.log
        periodAppGroups = PeriodStats.appGroups(from: rollup.log)
        periodDayTotals = rollup.dayTotals
        periodSummary = rollup.summary
        previousPeriodTracked = PeriodStats(sessions: engine.archive, usage: usage)
            .previousPeriodTracked(for: period, containing: day)

        let frontmost = tracker?.currentBundleID
        runningApps = stats.runningNow(from: NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier else { return nil }
                return RunningAppInput(bundleID: bundleID,
                                       appName: app.localizedName ?? bundleID,
                                       launched: app.launchDate,
                                       stretchSeconds: bundleID == frontmost
                                           ? tracker?.openSeconds() : nil)
            })

        // Earlier today: apps with usage that are not running now, so the two
        // sections never repeat an app.
        let runningIDs = Set(runningApps.map(\.bundleID))
        earlierToday = rankedApps
            .filter { !runningIDs.contains($0.bundleID) }
            .prefix(engine.store.menuSessionCount)
            .enumerated()
            .map { index, rank in
                AppDayHistory(bundleID: rank.bundleID,
                              appName: rank.appName,
                              total: rank.total,
                              colorIndex: min(index, 6),
                              sessions: stats.sessions(for: day, bundleID: rank.bundleID)
                                  .sorted { $0.start > $1.start })
            }

        // On today these are the same computation, so the second pass only runs
        // while the dashboard is browsing history.
        if dayOffset == 0 {
            glanceApps = rankedApps
            glanceInsights = insights
            glanceTimeline = timelineSegments
            glanceLayout = timelineLayout
        } else {
            let today = Date()
            glanceApps = stats.rankedApps(for: today)
            glanceInsights = stats.insights(for: today)
            glanceTimeline = stats.timeline(for: today)
            glanceLayout = TimelineLayout(segments: glanceTimeline)
        }
    }

    /// The first day with anything recorded — the calendar cannot reach behind
    /// it, because there is nothing there to show.
    var earliestSelectableDay: Date? { earliestDay }

    /// Jumps to a specific date. Clamped to the recorded range so the picker can
    /// never land the dashboard on a day it would refuse to step to.
    func selectDate(_ date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var target = calendar.startOfDay(for: date)
        if let earliest = earliestDay, target < earliest { target = earliest }
        if target > today { target = today }
        let days = calendar.dateComponents([.day], from: target, to: today).day ?? 0
        selectDay(offset: max(0, days))
    }

    /// `Refactor · Deep work · started 10:17 am`
    var activeSessionSubtitle: String {
        var parts = [activeIntent, engine.activeWorkType.displayName]
        if state != .idle {
            parts.append("started " + Tokens.timeOfDay(engine.sessionStartDate)
                .replacingOccurrences(of: "since ", with: ""))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Per-app history

    /// Whether an app is running right now, so its session can be continued.
    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// The live session expressed as a thread, or nil when idle. Kept in step
    /// with `sessionsToday`: a running session counts everywhere or nowhere.
    private func runningThread() -> RunningThread? {
        guard state != .idle else { return nil }
        return RunningThread(threadID: engine.activeThreadID,
                             name: engine.sessionName,
                             workType: engine.activeWorkType,
                             start: engine.sessionStartDate,
                             worked: engine.elapsed)
    }

    /// The primary and side apps a thread was worked in.
    func threadApps(_ thread: ThreadSummary) -> ThreadApps {
        guard let usage else { return .none }
        return ThreadStats(sessions: engine.archive, usage: usage,
                           purposeOverrides: engine.store.purposeOverrides)
            .apps(for: thread, on: Date())
    }

    /// Resumes earlier work as a new segment of the same thread, and restores
    /// the context it was done in: if the thread's primary app is still
    /// running, it comes forward. If it was quit during the break, nothing is
    /// launched — reopening an app the user deliberately closed would be worse
    /// than doing nothing.
    func continueThread(_ thread: ThreadSummary) {
        guard !thread.isRunning else { return }
        let primary = threadApps(thread).primary?.bundleID
        engine.start(workType: thread.workType, intent: thread.name,
                     threadID: thread.threadID)
        if let primary, isRunning(bundleID: primary) {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: primary)
                .first?
                .activate(options: .activateIgnoringOtherApps)
        }
        refresh()
    }

    /// Continues work on an app: brings it forward and starts a focus session
    /// labelled with it. Refuses when the app is not running — there is nothing
    /// to continue.
    func continueApp(_ summary: AppUsageSummary) {
        guard isRunning(bundleID: summary.bundleID) else { return }
        NSRunningApplication
            .runningApplications(withBundleIdentifier: summary.bundleID)
            .first?
            .activate(options: [])
        engine.start(workType: engine.categories.suggestedWorkType(for: summary.bundleID),
                     intent: summary.appName)
        refresh()
    }

    /// Total tracked time for an app today — what "time spent" means once a
    /// session has been continued one or more times.
    func totalToday(for bundleID: String) -> TimeInterval {
        guard let usage else { return 0 }
        let calendar = Calendar.current
        return usage.sessions
            .filter { $0.bundleID == bundleID && calendar.isDateInToday($0.end) }
            .reduce(0) { $0 + $1.seconds }
    }

    func setTrackingEnabled(_ enabled: Bool) {
        engine.store.isUsageTrackingEnabled = enabled
        tracker?.setEnabled(enabled)
        isTrackingEnabled = enabled
        refresh()
    }

    var menuSessionCount: Int { engine.store.menuSessionCount }

    /// How often the open usage stretch is written to disk, bounding what an
    /// unclean exit can lose.
    private static let flushEverySeconds = 60
    /// How often continuous use is re-checked against the break thresholds.
    private static let breakCheckSeconds = 5

    /// Cosmetic only, exactly like the AppKit build's title timer: it reads
    /// nothing the state machine consumes and drives no transition.
    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.engine.transition(on: .idleObserved(seconds: self.idle.idleSeconds()))
            // Nothing else writes the open stretch to disk on a schedule, so a
            // crash, a Force Quit or a `kill` took everything since the last app
            // switch with it — `applicationWillTerminate` does not run for any
            // of those. Bounded to a minute now, instead of unbounded.
            if self.tick % SessionStore.flushEverySeconds == 0,
               self.tracker?.openSeconds(exceeds:
                    TimeInterval(SessionStore.flushEverySeconds)) == true {
                self.tracker?.flush()
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

    func resolve(_ decision: UserDecision) {
        engine.transition(on: .decision(decision))
    }

    // MARK: - Presentation helpers

    var activeIntent: String {
        engine.sessionName.isEmpty ? "Focus session" : engine.sessionName
    }

    var isIdle: Bool { state == .idle }
    var isPaused: Bool { state.isPaused }
}
