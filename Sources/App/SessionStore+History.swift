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
        let found = DashboardStats(sessions: engine.archive, usage: usage,
                                   usageSnapshot: effectiveUsageSnapshot)
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
    }

    // MARK: - Sessions of the day

    func clearSession() {
        selectedSession = nil
        sessionAppRanks = []
        sessionTracked = 0
    }

    /// Apps used inside the given spans on the selected day. The story opens
    /// entries independently, so it cannot use the single-selection cache.
    func appRanks(within spans: [DateInterval]) -> [AppRank] {
        guard let usage, !spans.isEmpty else { return [] }
        return DashboardStats(sessions: engine.archive, usage: usage,
                              usageSnapshot: effectiveUsageSnapshot)
            .rankedApps(for: selectedDay, within: spans)
    }

    func clearTimelineSelection() {
        selectedSegment = nil
    }

    /// Grouped sittings for one app on the selected day.
    func sessions(for bundleID: String) -> [AppSession] {
        guard let usage else { return [] }
        let grouped = DashboardStats(sessions: engine.archive, usage: usage,
                                     usageSnapshot: effectiveUsageSnapshot)
            .sessions(for: selectedDay, bundleID: bundleID)
            .sorted { $0.start > $1.start }
        return Array(grouped.prefix(engine.store.menuSessionCount))
    }

    /// Minutes per hour for one app, for the drill-down strip.
    func hourlyBuckets(for bundleID: String) -> [HourBucket] {
        guard let usage else { return [] }
        return DashboardStats(sessions: engine.archive, usage: usage,
                              usageSnapshot: effectiveUsageSnapshot)
            .hourlyBuckets(for: selectedDay, bundleID: bundleID)
    }

    /// `9:02 am – 4:41 pm` for one app on the selected day.
    func span(for bundleID: String) -> (start: Date, end: Date)? {
        guard let usage else { return nil }
        return DashboardStats(sessions: engine.archive, usage: usage,
                              usageSnapshot: effectiveUsageSnapshot)
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
            insightsRefreshPending = true
            reviewLiveTailRefreshPending = true
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
        if dashboardVisible, dashboardArchiveRefreshPending || dashboardLiveTailRefreshPending {
            let liveOnly = !dashboardArchiveRefreshPending
            dashboardArchiveRefreshPending = false
            dashboardLiveTailRefreshPending = false
            rebuildDashboard(liveOnly: liveOnly)
        }
        if reviewVisible, reviewRefreshPending || reviewLiveTailRefreshPending {
            let liveTailOnly = !reviewRefreshPending
            reviewRefreshPending = false
            reviewLiveTailRefreshPending = false
            refreshReview(rebuildingHistory: !liveTailOnly)
        }
        if insightsVisible, insightsRefreshPending {
            insightsRefreshPending = false
            refreshInsights()
        }
        refreshTransactionDepth = 0
        // A synchronous observer may have requested another pass while values
        // were publishing. Coalesce that work into the next single pass.
        if glanceArchiveRefreshPending
            || (dashboardVisible && (dashboardArchiveRefreshPending || dashboardLiveTailRefreshPending))
            || (reviewVisible && (reviewRefreshPending || reviewLiveTailRefreshPending))
            || (insightsVisible && insightsRefreshPending) {
            consumePendingSurfaceRefreshes()
        }
    }

    /// The popover's archive-derived slice: today only, with the continuation
    /// rows it presents. It remains live without touching selected-day/period
    /// dashboard state while that window is hidden.
    private func rebuildGlance() {
        guard let usage else { return }
        let today = Date()
        let usageSnapshot = effectiveUsageSnapshot
        let stats = DashboardStats(sessions: engine.archive, usage: usage,
                                   usageSnapshot: usageSnapshot)
        glanceApps = stats.rankedApps(for: today)
        glanceInsights = stats.insights(for: today)
        glanceTimeline = stats.timeline(for: today)
        glanceBrackets = stats.focusSpans(for: today).map { ($0.start, $0.end) }
        glanceLayout = TimelineLayout(segments: glanceTimeline)
        threadsToday = ThreadStats(sessions: engine.archive, usage: usage,
                                   usageSnapshot: usageSnapshot,
                                   purposeOverrides: engine.store.purposeOverrides,
                                   continueWindow: engine.store.continueWindow)
            .threads(on: today, running: runningThread())
    }

    /// Rebuilds every full dashboard figure from the two archives in one pass.
    /// Called only by the visibility gate above.
    private func rebuildDashboard(liveOnly: Bool = false) {
        guard let usage else { return }
        let day = Calendar.current.startOfDay(for: selectedDay)
        let live = liveOnly && period == .day && dashboardReadModelDay == day
            && dashboardEvidenceRevision == evidenceRevision
        if live, let bounds = SessionRecord.dayBounds(day, calendar: .current) {
            let changingFocus = engine.runningSpan.map { $0.start < bounds.end && $0.end > bounds.start } ?? false
            let changingUsage = (tracker?.usageOverlaySessions() ?? []).contains {
                $0.start < bounds.end && $0.end > bounds.start
            }
            guard changingFocus || changingUsage else { return }
        }
        dashboardEvidenceRevision = evidenceRevision
        dashboardReadModelDay = day
        // A live refresh is the Day view each second, and reads only that day:
        // its records, not the whole uncapped history. A full rebuild also
        // reads other days (sparklines, yesterday, the first recorded day).
        let usageSnapshot = live
            ? effectiveUsageSnapshot?.restricted(to: day)
            : effectiveUsageSnapshot
        let stats = DashboardStats(sessions: engine.archive, usage: usage,
                                   usageSnapshot: usageSnapshot, now: now)
        let periods = PeriodStats(sessions: engine.archive, usage: usage,
                                  usageSnapshot: usageSnapshot, calendar: periodCalendar, now: now)
        // Keep this in step with `sessionsToday`: without it the same screen
        // reads "1 session today" and "No sessions yet today".
        let countsRunning = state != .idle && dayOffset == 0

        rankedApps = stats.rankedApps(for: day)
        timelineSegments = stats.timeline(for: day)
        cachedWindow = stats.timelineWindow(for: day)
        timelineLayout = TimelineLayout(segments: timelineSegments)
        focusBrackets = stats.focusSpans(for: day).map { ($0.start, $0.end) }
        var qualityStats = stats
        qualityStats.activeWorkType = engine.activeWorkType
        focusQuality = qualityStats.focusQuality(
            for: day,
            runningSeconds: countsRunning ? engine.elapsedToday() : nil,
            runningThreadID: countsRunning ? engine.activeThreadID : nil)
        trackedForSelectedDay = stats.trackedTotal(for: day)
        focusedActiveForSelectedDay = live && isToday ? goal.achieved
            : focusedActiveSeconds(on: day, usageSnapshot: usageSnapshot)
        if !live {
            insights = stats.insights(for: day)
            trackedYesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)
                .map { stats.trackedTotal(for: $0) } ?? 0
            sessionsForSelectedDay = engine.archive.threadCount(on: day)
            focusedForSelectedDay = engine.archive.workSeconds(on: day)
            let longest = engine.archive.longestThread(on: day)
            longestForSelectedDay = longest?.seconds ?? 0
            // Unnamed work is named by its type, as the Sessions card and the
            // summary name it.
            longestNameForSelectedDay = longest.map { $0.workType.sessionTitle(named: $0.name) }
            earliestDay = stats.earliestRecordedDay()
            let selectedBounds = periods.bounds(for: period, containing: day)
            let accuracyEpoch = usageSnapshot?.accurateFrom ?? usage.metadata.accurateFrom
            if usage.containsUsage(in: DateInterval(start: selectedBounds.start,
                                                    end: selectedBounds.end),
                                                    before: accuracyEpoch) {
                selectedDayIntegrityNote = "App usage from before "
                    + "\(Tokens.longDate(accuracyEpoch)) was preserved "
                    + "and may include unattended time."
            } else {
                selectedDayIntegrityNote = nil
            }
        }

        // A month is 31 day-slices, each one pass over the usage array. One
        // rollup call walks them once; asking for the pieces separately walked
        // them three times and cost 16 MB of churn.
        daySessions = SessionDigest.entries(records: engine.archive.records(on: day),
                                            running: isToday ? runningThread() : nil,
                                            now: now(), day: day)
        // A selection that no longer matches the day's rows is stale.
        if let selected = selectedSession,
           !daySessions.contains(where: { $0.id == selected.id }) {
            clearSession()
        }

        let rollup = periods.rollup(for: period, containing: day)
        periodDays = rollup.days
        periodLog = rollup.log
        periodAppGroups = PeriodStats.appGroups(from: rollup.log)
        periodDayTotals = rollup.dayTotals
        periodSummary = rollup.summary
        if !live {
            previousPeriodTracked = periods.previousPeriodTracked(for: period, containing: day)
        }

        // Charts. The rhythm is the day's segments re-cut by the hour; the
        // sparklines are one figure per day across the period (or the last
        // seven days on Day); the donut is the work-type split of whatever is
        // selected. All from the same passes the figures above already made.
        rhythm = cachedWindow.map { Rhythm.hours(segments: timelineSegments, window: $0) } ?? []
        rhythmPeak = Rhythm.peakLabel(rhythm) { DateFormats.hourLabel($0) }
        if live {
            if let last = sparks.tracked.indices.last { sparks.tracked[last] = trackedForSelectedDay }
            workTypeShares = focusQuality.byWorkType
            refreshSummary(rollup: rollup, day: day)
            noteDashboardReadModelRebuild(full: false)
            return
        }
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
            workTypeShares = Self.reviewWorkTypes(from: rollup.days)
        }
        refreshSummary(rollup: rollup, day: day)
        refreshRunningApps(stats: stats, day: day)
        noteDashboardReadModelRebuild()
    }

    /// The apps open now, and "Earlier today": apps with usage that are not
    /// running now, so the two sections never repeat an app.
    private func refreshRunningApps(stats: DashboardStats, day: Date) {
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

        let runningIDs = Set(runningApps.map(\.bundleID))
        earlierToday = rankedApps
            .filter { !runningIDs.contains($0.bundleID) }
            .prefix(engine.store.menuAppCount)
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

    // MARK: - Per-app history

    /// Whether an app is running right now, so its session can be continued.
    func isRunning(bundleID: String) -> Bool {
        applicationIsRunning(bundleID)
    }

    /// The live session expressed as a thread, or nil when idle. Kept in step
    /// with `sessionsToday`: a running session counts everywhere or nowhere.
    func runningThread() -> RunningThread? {
        guard engine.state != .idle else { return nil }
        return RunningThread(recordID: engine.activeRecordID, threadID: engine.activeThreadID,
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
        return RunningThread(recordID: running.recordID, threadID: running.threadID, name: running.name,
                             workType: running.workType, start: start, worked: worked)
    }

    /// The primary and side apps a thread was worked in.
    func threadApps(_ thread: ThreadSummary) -> ThreadApps {
        guard let usage else { return .none }
        return ThreadStats(sessions: engine.archive, usage: usage,
                           usageSnapshot: effectiveUsageSnapshot,
                           purposeOverrides: engine.store.purposeOverrides,
                           continueWindow: engine.store.continueWindow)
            .apps(for: thread, on: Date())
    }

    /// One archive-wide continuation projection per refresh. The grouped
    /// summaries and index remain stable until archive evidence changes.
    func refreshContinuations() {
        let records = engine.archive.records
        let index = ContinuationPolicy.Index(records: records)
        let active = runningThread()
        continuationCandidates = ThreadStats(sessions: engine.archive, usage: usage,
                                             usageSnapshot: effectiveUsageSnapshot,
                                             purposeOverrides: engine.store.purposeOverrides,
                                             now: now,
                                             continueWindow: engine.store.continueWindow)
            .continuationThreads(running: active)
        continuationIndex = index
    }

    /// Focus reads grouped summaries, not archive records. Current time and
    /// active ownership are still evaluated here before anything is displayed.
    var continuableThreads: [ThreadSummary] {
        guard let index = continuationIndex else { return [] }
        let active = runningThread()
        let moment = now()
        return continuationCandidates.filter { thread in
            guard let canonical = canonicalRecord(for: thread, index: index) else { return false }
            return index.isEligible(canonical, active: active, now: moment)
        }
    }

    /// Resumes earlier work as a new segment of the same thread, and restores
    /// the context it was done in: if the thread's primary app is still
    /// running, it comes forward. If it was quit during the break, nothing is
    /// launched — reopening an app the user deliberately closed would be worse
    /// than doing nothing.
    func continueThread(_ thread: ThreadSummary) {
        let records = engine.archive.records
        let index = ContinuationPolicy.Index(records: records)
        guard !hasUnresolvedAwayDecision, !thread.isRunning,
              let canonical = canonicalRecord(for: thread, index: index),
              index.isEligible(canonical, active: runningThread(), now: now()) else { return }
        let primary = threadApps(thread).primary?.bundleID
        guard replaceSession(workType: canonical.workType, intent: canonical.name,
                             threadID: canonical.threadID) else { return }
        if let primary, isRunning(bundleID: primary) {
            activateApplication(primary, true)
        }
        refresh()
    }

    /// Continues work on an app: brings it forward and starts a focus session
    /// labelled with it. Refuses when the app is not running — there is nothing
    /// to continue.
    func continueApp(_ summary: AppUsageSummary) {
        guard !hasUnresolvedAwayDecision,
              isRunning(bundleID: summary.bundleID) else { return }
        guard replaceSession(workType: engine.categories.suggestedWorkType(for: summary.bundleID),
                             intent: summary.appName) else { return }
        activateApplication(summary.bundleID, false)
        refresh()
    }

    func setTrackingEnabled(_ enabled: Bool) {
        engine.store.isUsageTrackingEnabled = enabled
        tracker?.setEnabled(enabled)
        isTrackingEnabled = enabled
        refresh()
        onAutomationStateChanged?()
    }

    var menuSessionCount: Int { engine.store.menuSessionCount }

    /// What this session's recording shows, as prose composed only from the
    /// segments that actually intersect it. Nil when nothing was recorded
    /// inside the session, which the surface says in its own words.
    func sessionShape(_ session: DaySession) -> String? {
        storySessionDetail(session).text
    }

    // MARK: - Correcting a recorded session

    /// The focus sessions a recorded break can be counted into: those on the
    /// break's own day, nearest to it first, one per session. The whole
    /// archive made a menu of hundreds of look-alike rows.
    func legacyFocusTargets(for rest: RestEntry, calendar: Calendar = .current) -> [SessionRecord] {
        func distance(_ record: SessionRecord) -> TimeInterval {
            record.end <= rest.start ? rest.start.timeIntervalSince(record.end)
                : max(0, record.start.timeIntervalSince(rest.end))
        }
        var threads = Set<UUID>()
        return engine.archive.records
            .filter { $0.workType.countsAsFocus && $0.end > $0.start
                && calendar.isDate($0.start, inSameDayAs: rest.start) }
            .sorted { distance($0) == distance($1) ? $0.start < $1.start : distance($0) < distance($1) }
            .filter { threads.insert($0.threadID).inserted }
    }

    /// `Browsing · Deep work · 2:24 pm – 3:11 pm`: the time tells apart
    /// sessions that share a name.
    static func legacyFocusTargetLabel(_ record: SessionRecord) -> String {
        let time = DateFormats.australian("h:mm a")
        return "\(record.name.isEmpty ? "Unnamed session" : record.name) · \(record.workType.displayName) · "
            + "\(time.string(from: record.start)) – \(time.string(from: record.end))"
    }

    func legacyBreakRecord(id: UUID) -> SessionRecord? {
        engine.archive.records.first { $0.id == id && $0.workType == .breakTime }
    }

    /// Names a break that no away answer recorded. The name is a correction
    /// to its record, so the story offers Undo for it like any rename.
    @discardableResult
    func renameBreak(recordID: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let record = legacyBreakRecord(id: recordID) else { return false }
        let titled = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        return applyCorrection(threadID: record.threadID, correction: .rename(titled))
    }

    /// Re-answers a break the away question recorded: the answer is undone
    /// and the new one saved over the same interval, counted into the session
    /// the absence interrupted or left uncounted. Undo on the new answer
    /// reopens the question, where "Call it a break" restores the break.
    @discardableResult
    func changeBreak(_ receipt: AwayDecisionReceipt, to decision: UserDecision) -> Bool {
        guard receipt.decision == .tookBreak, decision == .mergeTime || decision == .continueSession,
              undoAwayDecision(expectedID: receipt.id),
              let reopened = engine.lastAwayDecision, !reopened.isResolved,
              reopened.range == receipt.range else { return false }
        return applyAwayDecision(decision, reviewing: true, expectedID: reopened.id)
    }

    @discardableResult
    func reclassifyLegacyBreak(recordID: UUID, decision: UserDecision, focusTargetID: UUID? = nil,
                              expectedRecord: SessionRecord? = nil, expectedTarget: SessionRecord? = nil) -> Bool {
        guard let original = legacyBreakRecord(id: recordID),
              expectedRecord == nil || expectedRecord == original,
              expectedTarget == nil || engine.archive.records.contains(expectedTarget!) else {
            publishCorrectionError("The confirmed record or focus target changed. Review it before trying again.")
            return false
        }
        let target = focusTargetID.flatMap { id in engine.archive.records.first { $0.id == id } }
        let saved = engine.reclassifyLegacyBreak(recordID: recordID, decision: decision, focusTargetID: focusTargetID)
        publishCorrectionError(saved ? nil : engine.awayDecisionError ?? "This break changed. Its newer evidence was preserved.")
        if saved { correctionRetry = nil }
        else { correctionRetry = .legacy(record: original, decision: decision, target: target) }
        refresh()
        return saved
    }

    /// Renames the work a session belongs to. The name is the thread's, so
    /// every stretch of that work carries the correction.
    @discardableResult
    func renameSession(_ session: DaySession, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            publishCorrectionError("Enter a session name before saving the correction.")
            return false
        }
        return applyCorrection(threadID: session.threadID, correction: .rename(trimmed))
    }

    /// The name a recorded break carries now, or nil while it is still the
    /// unnamed default. Read from the archive, so a later rename shows.
    func breakName(for receipt: AwayDecisionReceipt) -> String? {
        guard receipt.decision == .tookBreak, let id = receipt.insertedRecord?.id,
              let record = engine.archive.records.first(where: { $0.id == id }) else { return nil }
        let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "Break" ? nil : name
    }

    /// Whether the break behind this receipt is a record that can take a name.
    func canNameBreak(for receipt: AwayDecisionReceipt) -> Bool {
        guard receipt.decision == .tookBreak, let id = receipt.insertedRecord?.id else { return false }
        return engine.archive.records.contains { $0.id == id }
    }

    /// Names a break after the fact: what the away prompt's field does, for a
    /// break that was answered with the button or from the story.
    @discardableResult
    func nameBreak(for receipt: AwayDecisionReceipt, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let titled = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        return nameBreak(decisionID: receipt.id, titled: titled)
    }

    /// Reclassifies the work a session belongs to. Correcting a session to a
    /// break removes it from focus, which is the point: the record should say
    /// what happened.
    @discardableResult
    func setWorkType(_ workType: WorkType, for session: DaySession) -> Bool {
        applyCorrection(threadID: session.threadID, correction: .workType(workType))
    }

    /// The same, by thread, for corrections made outside a session's card:
    /// the goal tile's tidy-up of names spelled like a category.
    @discardableResult
    func setWorkType(_ workType: WorkType, threadID: UUID) -> Bool {
        applyCorrection(threadID: threadID, correction: .workType(workType))
    }

    /// Clears a session's own name, so it is titled by its category. Only
    /// that tidy-up asks for this; a person renaming must give a name.
    @discardableResult
    func clearSessionName(threadID: UUID) -> Bool {
        applyCorrection(threadID: threadID, correction: .rename(""))
    }

    /// Whether this session can be taken out of the record right now: nothing
    /// running on its thread, and no away question pending.
    func canRemoveSession(_ session: DaySession) -> Bool {
        removalBlockReason(for: session) == nil
            && engine.archive.records.contains { $0.threadID == session.threadID }
    }

    /// Why Remove is offered but not yet possible, in the user's terms. Nil
    /// when nothing stands in the way. A stretch of the thread that is
    /// running now is the usual reason: the live stretch is not in the
    /// archive yet, so removing the rest would leave a session in two minds.
    func removalBlockReason(for session: DaySession) -> String? {
        if hasUnresolvedAwayDecision {
            return "Answer the away question first."
        }
        if session.isRunning || (engine.state != .idle && engine.activeThreadID == session.threadID) {
            return "This session is running now. End it, then remove it."
        }
        return nil
    }

    /// Takes every stretch of the session out of the archive. The span then
    /// reads as time outside sessions — the app use stays, the claim that it
    /// was focus goes — and the story offers Undo, which restores the very
    /// same records.
    @discardableResult
    func removeSession(_ session: DaySession) -> Bool {
        guard canRemoveSession(session) else {
            publishCorrectionError("This session is running or waiting on an answer, so it cannot be removed yet.")
            return false
        }
        guard engine.prepareCorrection() else {
            publishCorrectionError(engine.awayDecisionError); return false
        }
        let before = engine.snapshot()
        let removed = engine.archive.records.filter { $0.threadID == session.threadID }
        guard let first = removed.first else { publishCorrectionError(nil); return false }
        var receipt = SessionStoreCorrectionState(
            sequence: (before.correctionGeneration ?? 0) + 1,
            threadID: session.threadID, correction: .removed, archiveSnapshot: nil,
            originalFields: .init(name: first.name, workType: first.workType),
            archiveRecordIDs: Set(removed.map(\.id)))
        receipt.removedRecords = removed
        guard engine.commitCorrection(before: before, removing: removed, adding: [],
                                      fields: corrections + [receipt]) else {
            publishCorrectionError(engine.awayDecisionError)
            correctionRetry = .correction(threadID: session.threadID, correction: .removed)
            return false
        }
        publishCanUndoCorrection(true)
        publishCorrectionError(nil)
        correctionRetry = nil
        refresh()
        return true
    }

    /// Retries either the failed save or a failed undo against the same narrow
    /// record IDs. No caller needs to reconstruct potentially stale evidence.
    @discardableResult
    func retryLastCorrection() -> Bool {
        guard let retry = correctionRetry else { return false }
        if let pending = engine.decisionHistory.document.pending {
            guard retry.matches(pending) else {
                // A current End/discard can be waiting behind an older action
                // whose archive effects are already committed. Retry that
                // exact current intent; its normal write boundary finalises
                // the older journal before attempting its own terminal write.
                if engine.decisionHistory.pendingAfterIsCommitted(in: engine.archive),
                   (pending.after.correctionGeneration ?? 0) <= engine.decisionHistoryRevision,
                   let completed = retryCurrentTerminalIntent(retry) { return completed }
                publishCorrectionError("That Retry belongs to a different action. The pending correction was preserved.")
                return false
            }
            guard engine.prepareCorrection() else {
                publishCorrectionError(engine.awayDecisionError); return false
            }
            if engine.decisionHistoryRevision == pending.after.correctionGeneration {
                correctionRetry = nil
                publishCorrectionError(nil)
                refresh()
                return true
            }
        }
        switch retry {
        case .correction(let threadID, let correction):
            return applyCorrection(threadID: threadID, correction: correction)
        case .undo(let state):
            return undo(state)
        case .awayUndo(let id):
            return undoAwayDecision(expectedID: id)
        case .awayDecision(let decision, let label, let reviewing, let id):
            return applyAwayDecision(decision, label: label, reviewing: reviewing, expectedID: id)
        case .legacy(let record, let decision, let target):
            return reclassifyLegacyBreak(recordID: record.id, decision: decision, focusTargetID: target?.id,
                                        expectedRecord: record, expectedTarget: target)
        case .ending, .discarding, .longAway:
            return retryCurrentTerminalIntent(retry) ?? false
        }
    }

    private func retryCurrentTerminalIntent(_ retry: SessionCorrectionRetry) -> Bool? {
        switch retry {
        case .ending(let thread, let start):
            guard engine.state != .idle, engine.activeThreadID == thread, engine.sessionStartDate == start else {
                publishCorrectionError("That Retry belongs to an earlier session. Current work was preserved.")
                return false
            }
            stop()
            return engine.state == .idle && engine.awayDecisionError == nil
        case .discarding(let thread, let start, let resumeTracking):
            guard engine.state != .idle, engine.activeThreadID == thread, engine.sessionStartDate == start else {
                publishCorrectionError("That Retry belongs to an earlier automatic session. Current work was preserved.")
                return false
            }
            return undoAutoSession(resumeTracking: resumeTracking)
        case .longAway(let request, let resumeTracking):
            _ = engine.retryLongAwayTransition(request)
            let applied = applyLongAwayResult(resumeTracking: resumeTracking) ?? false
            if applied && resumeTracking { onAwayEnded?() }
            refresh()
            return applied && engine.awayDecisionError == nil
        default: return nil
        }
    }

    @discardableResult
    func undoLastCorrection() -> Bool {
        if engine.lastAwayDecision?.isResolved == true,
           (engine.lastAwayDecision?.sequence ?? 0) >= (lastCorrection?.sequence ?? 0) { return undoAwayDecision() }
        guard let state = lastCorrection else { return false }
        return undo(state)
    }

    @discardableResult
    func undoCorrection(expectedID: UUID) -> Bool {
        guard let correction = corrections.first(where: { $0.id == expectedID }) else {
            publishCorrectionError("That correction is no longer available. Later work was preserved.")
            return false
        }
        return undo(correction)
    }

    func correctionScopeNote(expectedID: UUID) -> String? {
        guard let correction = corrections.first(where: { $0.id == expectedID }) else { return nil }
        let records = engine.archive.records.filter { $0.threadID == correction.threadID }
        let count = records.count + (engine.state != .idle && engine.activeThreadID == correction.threadID ? 1 : 0)
        guard count > 1 else { return nil }
        return "Undo affects this field in all \(count) stretches of the session, including any on other days. Timing and other fields are unchanged."
    }

    private func applyCorrection(threadID: UUID, correction: SessionCorrection) -> Bool {
        guard engine.prepareCorrection() else {
            publishCorrectionError(engine.awayDecisionError); return false
        }
        let before = engine.snapshot()
        let archiveRecordIDs = Set(engine.archive.records
            .filter { $0.threadID == threadID }
            .map(\.id))
        let activeBefore: SessionStoreCorrectionState.ActiveFields?
        if engine.state != .idle, engine.activeThreadID == threadID {
            activeBefore = .init(name: engine.sessionName, workType: engine.activeWorkType)
        } else {
            activeBefore = nil
        }

        var removed: [SessionRecord] = [], added: [SessionRecord] = []
        for record in engine.archive.records where record.threadID == threadID {
            var changed = record
            switch correction {
            case .rename(let name): changed.name = name
            case .workType(let type): changed.workType = type
            case .removed: continue   // has its own path, `removeSession`
            }
            if changed != record { removed.append(record); added.append(changed) }
        }
        let archiveSnapshot: SessionArchiveCorrectionSnapshot? = removed.isEmpty ? nil : .init(
            threadID: threadID, correction: correction, fields: removed.map {
                .init(recordID: $0.id, name: $0.name, workType: $0.workType)
            })
        let activeChanged: Bool = activeBefore.map { value in
            switch correction {
            case .rename(let name): return value.name != name
            case .workType(let type): return value.workType != type
            case .removed: return false
            }
        } ?? false
        guard archiveSnapshot != nil || activeChanged else {
            publishCorrectionError(nil)
            correctionRetry = nil
            return false
        }

        guard let originalFields = activeBefore ?? archiveSnapshot?.fields.first.map({
            SessionStoreCorrectionState.ActiveFields(name: $0.name, workType: $0.workType)
        }) else {
            // The success branches above necessarily carry a prior field value;
            // keep this fail-closed guard rather than inventing one for Undo.
            publishCorrectionError("Could not retain the original correction value.")
            return false
        }

        let receipt = SessionStoreCorrectionState(sequence: (before.correctionGeneration ?? 0) + 1,
                               threadID: threadID, correction: correction,
                               archiveSnapshot: archiveSnapshot,
                               originalFields: originalFields,
                               archiveRecordIDs: archiveRecordIDs)
        engine.stageActiveCorrection(correction, threadID: threadID)
        guard engine.commitCorrection(before: before, removing: removed, adding: added,
                                      fields: corrections + [receipt]) else {
            publishCorrectionError(engine.awayDecisionError)
            correctionRetry = .correction(threadID: threadID, correction: correction)
            return false
        }
        publishCanUndoCorrection(true)
        publishCorrectionError(nil)
        correctionRetry = nil
        refresh()
        return true
    }

    private func undo(_ state: SessionStoreCorrectionState) -> Bool {
        guard engine.prepareCorrection(), corrections.contains(where: { $0.id == state.id }) else {
            publishCorrectionError(engine.awayDecisionError ?? "That correction was already undone.")
            return false
        }
        let before = engine.snapshot()
        if state.correction == .removed {
            // Put the records back exactly as they were, provided nothing has
            // since taken their identity.
            let records = state.removedRecords ?? []
            let present = Set(engine.archive.records.map(\.id))
            guard !records.isEmpty, records.allSatisfy({ !present.contains($0.id) }) else {
                publishCorrectionError("That session is already back, or its stretches were rewritten since.")
                return false
            }
            guard engine.commitCorrection(before: before, removing: [], adding: records,
                                          fields: corrections.filter { $0.id != state.id }) else {
                publishCorrectionError(engine.awayDecisionError)
                correctionRetry = .undo(state)
                return false
            }
            publishCanUndoCorrection(!corrections.isEmpty || engine.canUndoAwayDecision)
            publishCorrectionError(nil)
            correctionRetry = nil
            refresh()
            return true
        }
        let originals = Dictionary(uniqueKeysWithValues: (state.archiveSnapshot?.fields ?? []).map { ($0.recordID, $0) })
        let existingIDs = Set(engine.archive.records.map(\.id))
        guard Set(originals.keys).isSubset(of: existingIDs) else {
            publishCorrectionError("An originally corrected record is not currently available. Restore its classification before undoing this field.")
            correctionRetry = .undo(state)
            return false
        }
        var removed: [SessionRecord] = [], added: [SessionRecord] = []
        for record in engine.archive.records where record.threadID == state.threadID {
            guard let original = originals[record.id] ?? (!state.archiveRecordIDs.contains(record.id)
                ? .init(recordID: record.id, name: state.originalFields.name, workType: state.originalFields.workType) : nil)
            else { continue }
            var changed = record
            switch state.correction {
            case .rename(let expected):
                guard record.name == expected || record.name == original.name else { return correctionConflict(state) }
                changed.name = original.name
            case .workType(let expected):
                guard record.workType == expected || record.workType == original.workType else { return correctionConflict(state) }
                changed.workType = original.workType
            case .removed: continue
            }
            if changed != record { removed.append(record); added.append(changed) }
        }
        if engine.state != .idle, engine.activeThreadID == state.threadID {
            switch state.correction {
            case .rename(let expected):
                guard engine.sessionName == expected || engine.sessionName == state.originalFields.name else {
                    return correctionConflict(state)
                }
                engine.stageActiveCorrection(.rename(state.originalFields.name), threadID: state.threadID)
            case .workType(let expected):
                guard engine.activeWorkType == expected || engine.activeWorkType == state.originalFields.workType else {
                    return correctionConflict(state)
                }
                engine.stageActiveCorrection(.workType(state.originalFields.workType), threadID: state.threadID)
            case .removed: break
            }
        }
        guard engine.commitCorrection(before: before, removing: removed, adding: added,
                                      fields: corrections.filter { $0.id != state.id }) else {
            publishCorrectionError(engine.awayDecisionError)
            correctionRetry = .undo(state)
            return false
        }
        publishCanUndoCorrection(!corrections.isEmpty || engine.canUndoAwayDecision)
        publishCorrectionError(nil)
        correctionRetry = nil
        refresh()
        return true
    }

    private func correctionConflict(_ state: SessionStoreCorrectionState) -> Bool {
        publishCorrectionError("This field changed after the correction. Its newer value was preserved.")
        correctionRetry = .undo(state)
        return false
    }

    /// Starts a new stretch of the same work. Continuing never reopens a closed
    /// record — it starts a new one on the same thread, so a long gap is never
    /// rendered as worked time.
    func continueSession(_ session: DaySession) {
        guard !hasUnresolvedAwayDecision, !session.isRunning,
              let canonical = canonicalRecord(for: session),
              ContinuationPolicy.isEligible(canonical, records: engine.archive.records,
                                            active: runningThread(), now: now()) else { return }
        guard replaceSession(workType: canonical.workType, intent: canonical.name,
                             threadID: canonical.threadID) else { return }
        refresh()
    }

    /// Whether the thread this session belongs to has a stretch running now.
    func isThreadRunning(_ threadID: UUID) -> Bool {
        engine.state != .idle && engine.activeThreadID == threadID
    }

    /// Whether this session can be continued right now.
    func canContinue(_ session: DaySession) -> Bool {
        guard !hasUnresolvedAwayDecision, !session.isRunning,
              let canonical = canonicalRecord(for: session) else { return false }
        return ContinuationPolicy.isEligible(canonical, records: engine.archive.records,
                                             active: runningThread(), now: now())
    }

    /// An expired row may still seed an intentionally new session, but it must
    /// never bypass the continuation guard by silently retaining its thread.
    func canStartNewSession(_ session: DaySession) -> Bool {
        !hasUnresolvedAwayDecision && !session.isRunning
            && newSessionSource(for: session)?.workType.countsAsFocus == true
    }

    func startNewSession(from session: DaySession) {
        guard canStartNewSession(session),
              let source = newSessionSource(for: session) else { return }
        guard replaceSession(workType: source.workType, intent: source.name) else { return }
        refresh()
    }

    /// Resolves a displayed Story row to its last actual stretch. A stale row
    /// carries that stretch's archive ID even when chronology clips it at
    /// midnight. A legacy grouped row without that ID is accepted only if its
    /// displayed end/name/type still describe the latest stretch.
    private func canonicalRecord(for session: DaySession) -> SessionRecord? {
        let records = engine.archive.records
        if let direct = records.first(where: {
            $0.id == session.id && $0.threadID == session.threadID && $0.workType.countsAsFocus
        }) {
            return direct
        }
        guard let canonical = ContinuationPolicy.latest(records.filter {
            $0.threadID == session.threadID && $0.workType.countsAsFocus
        }), session.end == canonical.end, session.workType == canonical.workType,
           ContinuationPolicy.activityKey(name: session.name, workType: session.workType)
               == ContinuationPolicy.activityKey(name: canonical.name, workType: canonical.workType)
        else { return nil }
        return canonical
    }

    private func newSessionSource(for session: DaySession) -> SessionRecord? {
        engine.archive.records.first(where: { $0.id == session.id && $0.threadID == session.threadID })
            ?? canonicalRecord(for: session)
    }

    /// A Focus row is a snapshot. Its summary must still describe the archive's
    /// latest record for that thread before it may be used as an action.
    private func canonicalRecord(for thread: ThreadSummary,
                                 index: ContinuationPolicy.Index) -> SessionRecord? {
        guard let canonical = index.latestByThread[thread.threadID], canonical.end == thread.lastEnd,
           canonical.workType == thread.workType,
           ContinuationPolicy.activityKey(name: canonical.name, workType: canonical.workType)
               == ContinuationPolicy.activityKey(name: thread.name, workType: thread.workType)
        else { return nil }
        return canonical
    }
}
