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
        let rows = entries.compactMap { entry -> (span: DateInterval, credited: [String: TimeInterval])? in
            guard case .session(let session) = entry, session.workType.countsAsFocus,
                  let credited = sessionActivity(for: session)?.credited else { return nil }
            return (DateInterval(start: session.start, end: max(session.start, session.end)), credited)
        }
        // The ring's figure worked out afresh: today's published goal moves only on a tick, and a
        // stale one would cap the rows for the whole minute this is held.
        let value = DailyGoalList.focusByPurpose(rows: rows, ring: focusedActiveSeconds(on: day))
        focusByPurposeCache = (day, evidenceRevision, minute, overrides, value)
        return value
    }

    /// The activity targets in use, with the day's count of each.
    func activityTargets(on day: Date) -> [(id: UUID, purpose: AppPurpose, goal: TimeInterval, achieved: TimeInterval)] {
        let targets = DailyGoalList.activityTargets(goalItems)
        guard !targets.isEmpty else { return [] }
        let credit = focusByPurpose(on: day)
        return targets.map { ($0.id, $0.purpose, $0.goal, credit[$0.purpose.rawValue] ?? 0) }
    }
}
