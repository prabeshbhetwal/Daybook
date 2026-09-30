import Foundation

extension SessionEngine {
    // MARK: - Derived values (D1, D2)

    /// `elapsed = (now - sessionStart) - totalPaused - currentPauseSoFar`.
    /// The in-flight pause is subtracted live; it only lands in
    /// `totalPausedDuration` on exit from the paused state.
    var elapsed: TimeInterval {
        let gross = interval(from: sessionStartDate)
        let live = pauseStartDate.map { interval(from: $0) } ?? 0
        return max(0, gross - totalPausedDuration - live)
    }

    func elapsed(endingAt end: Date) -> TimeInterval {
        let clampedEnd = min(max(end, sessionStartDate), now())
        let gross = max(0, clampedEnd.timeIntervalSince(sessionStartDate))
        let livePause: TimeInterval
        if let pauseStartDate, clampedEnd > pauseStartDate {
            livePause = clampedEnd.timeIntervalSince(pauseStartDate)
        } else {
            livePause = 0
        }
        return max(0, gross - totalPausedDuration - livePause)
    }

    /// Counts the running session. Showing "42m focused" beside "0 sessions" is
    /// two truths on one screen.
    /// Sessions today, a session being a thread. The running stretch is a new
    /// session only when its thread has nothing in the archive today; after a
    /// break it continues one that is already counted.
    var sessionsToday: Int {
        let today = now()
        let archived = archive.threadCount(on: today)
        guard state != .idle, activeWorkType.countsAsFocus else { return archived }
        return archived + (archive.threadWork(activeThreadID, on: today) > 0 ? 0 : 1)
    }

    /// The longest session today, the running thread's earlier stretches and
    /// its live one added together.
    var longestToday: TimeInterval {
        let today = now()
        let archived = archive.longestThread(on: today)?.seconds ?? 0
        guard state != .idle, activeWorkType.countsAsFocus else { return archived }
        return max(archived, archive.threadWork(activeThreadID, on: today) + elapsedToday())
    }

    /// Today's completed work plus the part of the running session that happened
    /// today.
    var todayTotal: TimeInterval {
        archive.todayTotal() + elapsedToday()
    }

    /// The running session's work that belongs to today. A session begun before
    /// midnight must not donate last night's hours to this morning's goal bar —
    /// that is how a session left open across a night showed "18h 51m of 4h,
    /// goal met" before anyone had done a minute's work.
    /// The running session's span, for figures that intersect it with something
    /// else. Nil when idle.
    var runningSpan: (start: Date, end: Date)? {
        state == .idle ? nil : (start: sessionStartDate, end: now())
    }

    /// When the pending absence was, for the card and the prompts. Derived from
    /// the return moment already stamped in `decisionStartDate` and the length
    /// in the state, so it cannot disagree with the figure beside it.
    /// Whether answering "break" or "away" continues the running thread, or
    /// starts a new one because the user came back into different work. True
    /// outside a pending question.
    var returnKeepsThread: Bool {
        guard case .awaitingUserDecision = state else { return true }
        guard let returnedTo = currentAppBundleID, let left = departureApp,
              returnedTo != left else { return true }
        return threadContextMatcher?(returnedTo) ?? true
    }

    var pendingAwayRange: (start: Date, end: Date)? {
        guard case .awaitingUserDecision(let away, _) = state,
              let returnedAt = awayReturnedAt ?? decisionStartDate else { return nil }
        return (start: returnedAt.addingTimeInterval(-away), end: returnedAt)
    }

    func elapsedToday(calendar: Calendar = .current) -> TimeInterval {
        guard state != .idle, activeWorkType.countsAsFocus else { return 0 }
        let moment = now()
        let dayStart = calendar.startOfDay(for: moment)
        guard sessionStartDate < dayStart else { return elapsed }
        return elapsed(in: (start: dayStart, end: moment))
    }

    func elapsed(in range: (start: Date, end: Date)) -> TimeInterval {
        guard state != .idle, activeWorkType.countsAsFocus else { return 0 }
        let moment = now()
        let span = moment.timeIntervalSince(sessionStartDate)
        guard span > 0 else { return 0 }
        var spans = pausedSpans
        if let pauseStartDate, moment > pauseStartDate {
            spans.append(DateInterval(start: pauseStartDate, end: moment))
        }
        if let allocated = PauseAllocation.workSeconds(elapsed, start: sessionStartDate, end: moment,
                                                       range: range,
                                                       pausedSpans: spans,
                                                       pausedTotal: totalPausedDuration
                                                        + (pauseStartDate.map { interval(from: $0) } ?? 0)) {
            return allocated
        }
        let low = max(sessionStartDate, range.start), high = min(moment, range.end)
        guard high > low else { return 0 }
        return elapsed * min(1, max(0, high.timeIntervalSince(low) / span))
    }

    /// Wall-clock interval with backwards-skew clamping (D1).
    func interval(from date: Date) -> TimeInterval {
        let raw = now().timeIntervalSince(date)
        if raw < 0 {
            Diagnostics.log("clock skew: negative interval \(raw)s clamped to 0")
            return 0
        }
        return raw
    }
}
