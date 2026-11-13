import Foundation

extension SessionStore {

    /// How the day's figures were made, for a reader who wants the method.
    /// The totals, the busiest app and the goal credit are already on the
    /// page, and the On this Mac card explains goal credit, so none of that is
    /// restated; what is said here is how the other measures count, plus the
    /// two facts shown nowhere else (stretches, break names).
    static func storyDaySummaryFacts(entries: [DayEntry], apps: [AppRank]) -> [String] {
        let sessions = entries.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        let breaks = entries.compactMap { entry -> RestEntry? in
            if case .rest(let rest) = entry { return rest }
            return nil
        }
        var facts: [String] = []
        if !sessions.isEmpty {
            facts.append("Recorded focus is session time with pauses and uncounted absences left out, "
                         + "clipped to this day.")
            let stretchCount = sessions.reduce(0) { $0 + $1.stretches }
            if stretchCount > sessions.count {
                let subject = sessions.count == 1 ? "The session" : "The \(sessions.count) sessions"
                facts.append("\(subject) ran as \(stretchCount) separate stretches; "
                             + "the gaps between them are not counted.")
            }
        }
        if apps.contains(where: { $0.total > 0 }) {
            facts.append("Recorded app use is whatever was in front on this Mac, "
                         + "in a session or not; it is never counted as focus.")
        }
        if !breaks.isEmpty {
            let named = breaks.map(\.name).filter { !$0.isEmpty && $0 != "Break" }
            facts.append(named.isEmpty
                ? "Recorded breaks are rest; they are never counted as focus."
                : "Recorded break: \(named.joined(separator: ", ")); not counted as focus.")
        }
        return facts
    }

    /// The goal as the selected day saw it: focused-active time on every day,
    /// with today's usual pace only. A finished day has no "usual by now", so
    /// `aheadBy` is nil and no pace clause is written.
    var selectedDayGoal: GoalProgress {
        guard !isToday else { return goal }
        return GoalProgress(goal: engine.store.dailyGoal,
                            achieved: focusedActiveForSelectedDay, typical: nil)
    }
}
