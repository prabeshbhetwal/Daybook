import Foundation

/// Activity goals: coding (or writing and AI, or design) counted in any focus
/// session, whatever the session is filed under.
extension SessionStore {
    /// The day's focus by purpose raw value: each focus session row's credited
    /// seconds from its phases' shape, capped at the ring. Held until the
    /// evidence changes, and for today or a day the running session reaches,
    /// until the minute turns over, like the rail's figures it is drawn beside.
    func focusByPurpose(on requested: Date) -> [String: TimeInterval] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: requested)
        let minute = calendar.isDate(day, inSameDayAs: now()) || engine.runningSpan != nil
            ? Int(now().timeIntervalSinceReferenceDate / 60) : 0
        // A changed app category moves time between activities with no new evidence.
        let overrides = SessionActivityShape.digest(engine.store.purposeOverrides)
        if let cached = focusByPurposeCache, cached.day == day, cached.revision == evidenceRevision,
           cached.minute == minute, cached.overrides == overrides {
            return cached.value
        }
        // The digest alone, as the projection builds its rows: the whole projection (stats, details,
        // timeline) is far more than a day's session rows, and a miss comes with every app switch.
        let runningTouchesDay = calendar.dateInterval(of: .day, for: day).map { bounds in
            engine.runningSpan.map { $0.end > bounds.start && $0.start < bounds.end } ?? false
        } ?? false
        let entries = SessionDigest.entries(records: engine.archive.records,
                                            running: runningTouchesDay ? runningThread() : nil,
                                            now: now(), day: day, calendar: calendar)
        // Slices, not whole rows: a paused stretch covers nothing, and a row that folds an Unsorted
        // stretch with a focus one it was continued into counts the focus one.
        let rows = entries.flatMap { entry -> [(span: DateInterval, credited: [String: TimeInterval])] in
            guard case .session(let session) = entry else { return [] }
            let focus = focusIntervals(of: session)
            guard !focus.isEmpty, let shape = sessionActivity(for: session) else { return [] }
            return DailyGoalList.focusSlices(credited: shape.credited, phases: shape.phases,
                                             span: DateInterval(start: session.start, end: max(session.start, session.end)),
                                             focus: focus)
        }
        // The ring's figure worked out afresh: today's published goal moves only on a tick, and a
        // stale one would cap the rows for the whole minute this is held.
        let value = DailyGoalList.focusByPurpose(rows: rows, ring: focusedActiveSeconds(on: day))
        focusByPurposeCache = (day, evidenceRevision, minute, overrides, value)
        return value
    }

    /// The spans of a row's stretches filed under a category that counts as focus. A row's own
    /// category is its first stretch's, so each record is asked for its own.
    func focusIntervals(of session: DaySession) -> [DateInterval] {
        let records = engine.archive.records.filter { session.recordIDs.contains($0.id) }
        let counted = records.filter { $0.workType.countsAsFocus }
            .map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        // A stretch with no record yet is the running one: it counts as the session now running is filed.
        let recorded = records.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        let unrecorded = session.spans.filter { span in !recorded.contains { $0.intersects(span) } }
        let runningCounts = session.isRunning ? engine.activeWorkType.countsAsFocus : session.workType.countsAsFocus
        return counted + (runningCounts ? unrecorded : [])
    }

    /// The activity targets in use, with the day's count of each. A closed day with a saved result
    /// shows what was recorded, so recategorising an app today cannot turn a met goal missed.
    func activityTargets(on day: Date) -> [(id: UUID, purpose: AppPurpose, goal: TimeInterval, achieved: TimeInterval)] {
        let targets = DailyGoalList.activityTargets(goalItems)
        guard !targets.isEmpty else { return [] }
        let calendar = Calendar.current
        let saved = calendar.startOfDay(for: day) < calendar.startOfDay(for: now())
            ? engine.store.goalResultsByDay[DailyGoalList.dayKey(day, calendar: calendar)] ?? [] : []
        let unsaved = targets.contains { target in !saved.contains { $0.goalID == target.id } }
        let credit = unsaved ? focusByPurpose(on: day) : [:]
        return targets.map { target in
            if let result = saved.first(where: { $0.goalID == target.id }) {
                return (target.id, target.purpose, result.amount, result.counted)
            }
            return (target.id, target.purpose, target.goal, credit[target.purpose.rawValue] ?? 0)
        }
    }
}
