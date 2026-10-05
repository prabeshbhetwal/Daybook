import SwiftUI
import AppKit
import Combine

extension SessionStore {
    struct LiveFrame: Equatable {
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

    // MARK: - Derived state

    func apply(_ state: SessionState) {
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

    /// Turns the main run loop until every main-queue hop queued so far has
    /// run and this mirror shows the engine's state. The engine reaches the
    /// mirror on such a hop, so code that drives the engine directly waits
    /// here before reading the store. A fixed wait lost that race whenever
    /// the hop landed later than the wait. Call it on the main thread,
    /// outside a main-queue block.
    @discardableResult
    func catchUpWithEngine(timeout: TimeInterval = 2) -> Bool {
        let landed = RunLoopFlag()
        DispatchQueue.main.async { landed.isSet = true }
        return InstalledAppCatalog.turnRunLoop(until: { landed.isSet && state == engine.state },
                                               timeout: timeout)
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

    func updateTicker() {
        schedulesTicker && ticks ? startTicker() : stopTicker()
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
}
