import Foundation

extension SessionStore {

    /// Concise, factual bullets for an explicit local day. These deliberately
    /// keep logged focus, recorded app use and qualifying goal credit separate;
    /// the day headline already owns the total-focus sentence.
    func storyDaySummaryFacts(entries: [DayEntry], apps: [AppRank],
                              goalCredit: TimeInterval,
                              goal: TimeInterval) -> [String] {
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
            let stretchCount = sessions.reduce(0) { $0 + $1.stretches }
            facts.append("\(sessions.count == 1 ? "One focus session" : "\(sessions.count) focus sessions") across \(stretchCount == 1 ? "one recorded stretch" : "\(stretchCount) recorded stretches").")
        }
        if let leading = apps.first, leading.total > 0 {
            facts.append("Most recorded app use was in \(leading.appName) (\(Tokens.preciseDuration(leading.total))).")
        }
        if goalCredit > 0, goal > 0 {
            facts.append("\(Tokens.preciseDuration(goalCredit)) qualified towards the \(Tokens.preciseDuration(goal)) daily goal.")
        }
        if !breaks.isEmpty {
            let named = breaks.map(\.name).filter { !$0.isEmpty && $0 != "Break" }
            if named.isEmpty {
                facts.append("\(breaks.count == 1 ? "One recorded break" : "\(breaks.count) recorded breaks"), not counted as focus.")
            } else {
                facts.append("Recorded break: \(named.joined(separator: ", ")); not counted as focus.")
            }
        }
        return facts
    }

    /// The selected day — or week, or month — in words, from the same figures
    /// the rest of the page shows. Rebuilt on every dashboard refresh, so on
    /// today it keeps pace with the clock and on a past day it is that day's.
    func refreshSummary(rollup: PeriodRollup, day: Date) {
        let calendar = Calendar.current
        let goal = engine.store.dailyGoal
        if period == .day {
            let sessions = daySessions.compactMap { entry -> DaySession? in
                if case .session(let session) = entry { return session }
                return nil
            }
            let rests = daySessions.compactMap { entry -> RestEntry? in
                if case .rest(let rest) = entry { return rest }
                return nil
            }
            let previous = calendar.date(byAdding: .day, value: -1, to: day)
            summarySentences = SummaryText.day(DaySummaryInput(
                day: day,
                isToday: isToday,
                tracked: trackedForSelectedDay,
                firstSeen: timelineSegments.map(\.start).min(),
                lastSeen: timelineSegments.map(\.end).max(),
                focused: isToday ? todayTotal : focusedForSelectedDay,
                goal: goal,
                goalAchieved: isToday ? self.goal.achieved : focusedActiveForSelectedDay,
                sessions: sessions,
                rests: rests,
                apps: rankedApps,
                peak: rhythmPeak,
                insideSessionShare: focusQuality.insideSessionShare,
                switchesPerStretch: focusQuality.switchesPerSession,
                workTypes: focusQuality.byWorkType,
                previousTracked: trackedYesterday,
                previousFocused: previous.map { engine.archive.workSeconds(on: $0) } ?? 0))
            return
        }

        var focused: TimeInterval = 0
        var sessions = 0
        var goalMetDays = 0
        let usageSnapshot = effectiveUsageSnapshot
        for periodDay in rollup.days {
            let work = engine.archive.workSeconds(on: periodDay.date)
            focused += work
            sessions += engine.archive.threadCount(on: periodDay.date)
            if goal > 0,
               focusedActiveSeconds(on: periodDay.date,
                                    usageSnapshot: usageSnapshot) >= goal {
                goalMetDays += 1
            }
        }
        let busiest = rollup.days.max { $0.tracked < $1.tracked }
        summarySentences = SummaryText.period(PeriodSummaryInput(
            period: period,
            containsToday: rollup.days.contains { calendar.isDateInToday($0.date) },
            tracked: periodSummary.tracked,
            activeDays: periodSummary.activeDays,
            totalDays: periodSummary.totalDays,
            averagePerActiveDay: periodSummary.averagePerActiveDay,
            previousTracked: previousPeriodTracked,
            focused: focused,
            sessions: sessions,
            goal: goal,
            goalMetDays: goalMetDays,
            busiestDay: busiest?.date,
            busiestTracked: busiest?.tracked ?? 0,
            longestSitting: periodSummary.longest.map { ($0.appName, $0.attended, $0.start) },
            apps: periodAppGroups.prefix(2).map { ($0.appName, $0.total, $0.share) },
            appCount: periodAppGroups.count,
            workTypes: workTypeShares))
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
