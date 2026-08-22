import Foundation

extension SessionStore {

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
        for periodDay in rollup.days {
            let work = engine.archive.workSeconds(on: periodDay.date)
            focused += work
            sessions += engine.archive.threadCount(on: periodDay.date)
            if goal > 0, work >= goal { goalMetDays += 1 }
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

    /// The goal as the selected day saw it: live for today (hands-on time
    /// inside sessions, against your usual pace), the day's recorded session
    /// work for any other day — the same measure the calendar tints and the
    /// title band judge by. A finished day has no "usual by now", so
    /// `aheadBy` is nil and no pace clause is written.
    var selectedDayGoal: GoalProgress {
        guard !isToday else { return goal }
        return GoalProgress(goal: engine.store.dailyGoal, achieved: focusedForSelectedDay, typical: nil)
    }
}
