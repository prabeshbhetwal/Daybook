import SwiftUI

// The store's timeline and per-app history: hover and selection on the day
// band, per-app sessions and buckets, threads and continuing them. Split from
// `SessionStore+Dashboard.swift` for size only — same object, same rules.
extension SessionStore {

    // MARK: - Timeline inspection

    /// `fraction` is the pointer's position across the band, 0...1. Nil clears.
    /// `glance` is the menu bar's band: today's coordinates and today's
    /// segments, whatever day the dashboard is browsing.
    func hoverTimeline(at fraction: Double?, glance: Bool = false) {
        guard let fraction, let layout = glance ? glanceLayout : timelineLayout, let usage,
              // Over an elided separator there is nothing to name.
              let date = layout.date(at: min(max(fraction, 0), 1)) else {
            if hoveredSegment != nil { hoveredSegment = nil }
            return
        }
        let found = DashboardStats(sessions: engine.archive, usage: usage)
            .segment(at: date, on: glance ? Date() : selectedDay)
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

    /// A rhythm bar: select the first stretch inside that hour, so the
    /// timeline's detail row opens on it.
    func selectHour(_ hour: Date) {
        let end = hour.addingTimeInterval(3_600)
        guard let segment = timelineSegments.first(where: { $0.end > hour && $0.start < end }),
              let layout = timelineLayout,
              let fraction = layout.fraction(for: max(segment.start, hour).addingTimeInterval(1))
        else { return }
        if selectedSegment?.id == segment.id { return }
        selectTimeline(at: fraction)
    }

    // MARK: - Sessions of the day

    /// Narrow the page to one session. Clicking the selected one again clears.
    func selectSession(_ session: DaySession) {
        if selectedSession?.id == session.id { clearSession(); return }
        selectedSession = session
        guard let usage else { return }
        let stats = DashboardStats(sessions: engine.archive, usage: usage)
        sessionAppRanks = stats.rankedApps(for: selectedDay, within: session.spans)
        sessionTracked = stats.trackedTotal(for: selectedDay, within: session.spans)
    }

    func clearSession() {
        selectedSession = nil
        sessionAppRanks = []
        sessionTracked = 0
    }

    func hoverSession(_ session: DaySession?) { hoveredSession = session }
    func highlightApp(_ bundleID: String?) { highlightedBundleID = bundleID }

    /// The session, if any, the timeline should frame: the selected one, else
    /// the hovered one.
    var framedSession: DaySession? { selectedSession ?? hoveredSession }

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

    // MARK: - Surface refresh transactions

    /// Archive callbacks are synchronous. Nest them inside the caller's refresh
    /// and publish each surface at most once when the outer transaction ends.
    func withRefreshTransaction(_ body: () -> Void) {
        refreshTransactionDepth += 1
        body()
        refreshTransactionDepth -= 1
        if refreshTransactionDepth == 0 { consumePendingSurfaceRefreshes() }
    }

    func archiveUsageDidChange() {
        withRefreshTransaction {
            glanceArchiveRefreshPending = true
            dashboardArchiveRefreshPending = true
        }
    }

    /// Requests a selected-day/period rebuild. When the window is hidden the
    /// request remains pending until appearance; callers never bypass the gate.
    func refreshDashboard() {
        withRefreshTransaction { dashboardArchiveRefreshPending = true }
    }

    private func consumePendingSurfaceRefreshes() {
        guard refreshTransactionDepth == 0 else { return }
        refreshTransactionDepth = 1
        if glanceArchiveRefreshPending {
            glanceArchiveRefreshPending = false
            rebuildGlance()
        }
        if dashboardVisible, dashboardArchiveRefreshPending {
            dashboardArchiveRefreshPending = false
            rebuildDashboard()
        }
        refreshTransactionDepth = 0
        // A synchronous observer may have requested another pass while values
        // were publishing. Coalesce that work into the next single pass.
        if glanceArchiveRefreshPending
            || (dashboardVisible && dashboardArchiveRefreshPending) {
            consumePendingSurfaceRefreshes()
        }
    }

    /// The popover's archive-derived slice: today only, with the continuation
    /// rows it presents. It remains live without touching selected-day/period
    /// dashboard state while that window is hidden.
    private func rebuildGlance() {
        guard let usage else { return }
        let today = Date()
        let stats = DashboardStats(sessions: engine.archive, usage: usage)
        glanceApps = stats.rankedApps(for: today)
        glanceInsights = stats.insights(for: today)
        glanceTimeline = stats.timeline(for: today)
        glanceBrackets = stats.focusSpans(for: today).map { ($0.start, $0.end) }
        glanceLayout = TimelineLayout(segments: glanceTimeline)
        threadsToday = ThreadStats(sessions: engine.archive, usage: usage,
                                   purposeOverrides: engine.store.purposeOverrides)
            .threads(on: today, running: runningThread())
    }

    /// Rebuilds every full dashboard figure from the two archives in one pass.
    /// Called only by the visibility gate above.
    private func rebuildDashboard() {
        guard let usage else { return }
        let stats = DashboardStats(sessions: engine.archive, usage: usage)
        let day = selectedDay

        rankedApps = stats.rankedApps(for: day)
        timelineSegments = stats.timeline(for: day)
        cachedWindow = stats.timelineWindow(for: day)
        timelineLayout = TimelineLayout(segments: timelineSegments)
        focusBrackets = stats.focusSpans(for: day).map { ($0.start, $0.end) }
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
        sessionsForSelectedDay = engine.archive.threadCount(on: day)
        focusedForSelectedDay = engine.archive.workSeconds(on: day)
        let longest = engine.archive.longestThread(on: day)
        longestForSelectedDay = longest?.seconds ?? 0
        // Unnamed work is named by its type, as the Sessions card and the
        // summary name it.
        longestNameForSelectedDay = longest.map { $0.name.isEmpty ? $0.workType.displayName : $0.name }
        earliestDay = stats.earliestRecordedDay()
        let selectedBounds = PeriodStats(sessions: engine.archive, usage: usage)
            .bounds(for: period, containing: day)
        if usage.containsUsage(in: DateInterval(start: selectedBounds.start,
                                                end: selectedBounds.end),
                               before: usage.metadata.accurateFrom) {
            selectedDayIntegrityNote = "App usage from before "
                + "\(Tokens.longDate(usage.metadata.accurateFrom)) was preserved "
                + "and may include unattended time."
        } else {
            selectedDayIntegrityNote = nil
        }

        // A month is 31 day-slices, each one pass over the usage array. One
        // rollup call walks them once; asking for the pieces separately walked
        // them three times and cost 16 MB of churn.
        daySessions = SessionDigest.entries(records: engine.archive.records(on: day),
                                            running: isToday ? runningThread(on: day) : nil,
                                            now: Date(), day: day)
        // A selection that no longer matches the day's rows is stale.
        if let selected = selectedSession,
           !daySessions.contains(where: { $0.id == selected.id }) {
            clearSession()
        }

        let rollup = PeriodStats(sessions: engine.archive, usage: usage)
            .rollup(for: period, containing: day)
        periodDays = rollup.days
        periodLog = rollup.log
        periodAppGroups = PeriodStats.appGroups(from: rollup.log)
        periodDayTotals = rollup.dayTotals
        periodSummary = rollup.summary
        previousPeriodTracked = PeriodStats(sessions: engine.archive, usage: usage)
            .previousPeriodTracked(for: period, containing: day)

        // Charts. The rhythm is the day's segments re-cut by the hour; the
        // sparklines are one figure per day across the period (or the last
        // seven days on Day); the donut is the work-type split of whatever is
        // selected. All from the same passes the figures above already made.
        rhythm = cachedWindow.map { Rhythm.hours(segments: timelineSegments, window: $0) } ?? []
        rhythmPeak = Rhythm.peakLabel(rhythm) { DayTimelineView.hourLabel($0) }
        let calendar = Calendar.current
        let sparkDays: [Date] = period == .day
            ? (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: day) }
            : rollup.days.map(\.date)
        sparks = KPISparks(
            tracked: sparkDays.map { stats.trackedTotal(for: $0) },
            focused: sparkDays.map { engine.archive.workSeconds(on: $0) },
            sessions: sparkDays.map { Double(engine.archive.threadCount(on: $0)) },
            quality: sparkDays.map { stats.focusQuality(for: $0).byWorkType.first?.share ?? 0 })
        if period == .day {
            workTypeShares = focusQuality.byWorkType
        } else {
            var seconds: [WorkType: TimeInterval] = [:]
            for periodDay in rollup.days {
                for share in periodDay.byWorkType { seconds[share.workType, default: 0] += share.seconds }
            }
            let total = seconds.values.reduce(0, +)
            workTypeShares = WorkType.allCases.compactMap { type in
                guard let value = seconds[type], value > 0 else { return nil }
                return WorkTypeShare(workType: type, seconds: value,
                                     share: total > 0 ? value / total : 0)
            }.sorted { $0.seconds > $1.seconds }
        }
        refreshSummary(rollup: rollup, day: day)

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
                                           ? tracker?.currentStretchSeconds() : nil)
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

    }

    /// Window lifecycle gate for archive-driven refreshes. A hidden dashboard
    /// retains its last rendered state until it appears, then consumes at most
    /// one pending refresh however many checkpoints changed underneath it.
    func setDashboardVisible(_ visible: Bool) {
        withRefreshTransaction {
            dashboardVisible = visible
            if visible { dashboardArchiveRefreshPending = true }
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
            // This stretch's start; the thread's history is its own line.
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
    func runningThread() -> RunningThread? {
        guard state != .idle else { return nil }
        return RunningThread(threadID: engine.activeThreadID,
                             name: engine.sessionName,
                             workType: engine.activeWorkType,
                             start: engine.sessionStartDate,
                             worked: engine.elapsed)
    }

    /// The live thread's literal overlap with a selected day. A session begun
    /// before midnight must not render its earlier hours in today's card.
    func runningThread(on day: Date,
                       now: Date = Date(),
                       calendar: Calendar = .current) -> RunningThread? {
        guard let running = runningThread(),
              let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return nil }
        let end = min(now, bounds.end)
        let start = max(running.start, bounds.start)
        guard end >= start else { return nil }
        let fullSpan = max(0, now.timeIntervalSince(running.start))
        let worked: TimeInterval
        if fullSpan > 0 {
            worked = running.worked * (end.timeIntervalSince(start) / fullSpan)
        } else {
            worked = running.worked
        }
        return RunningThread(threadID: running.threadID, name: running.name,
                             workType: running.workType, start: start, worked: worked)
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
}
