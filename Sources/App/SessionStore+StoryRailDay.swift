import Foundation

/// What the dashboard's rail shows for one day: the goal, the ranked apps
/// and the rhythm by hour. The dashboard keeps these for the day it shows;
/// History asks for any other day and gets the same figures, built from the
/// same evidence the same way.
struct StoryRailDay: Equatable {
    let goal: GoalProgress
    let apps: [AppRank]
    let rhythm: [RhythmHour]
    let rhythmPeak: String?
}

extension SessionStore {
    /// One day's rail figures, cached until the evidence changes (and, for
    /// today, until the minute turns over).
    func storyRailDay(on requested: Date) -> StoryRailDay {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: requested)
        let isCurrentDay = calendar.isDate(day, inSameDayAs: now())
        let minute = isCurrentDay ? Int(now().timeIntervalSinceReferenceDate / 60) : 0
        if let cached = storyRailDayCache, cached.day == day, cached.revision == evidenceRevision,
           cached.minute == minute {
            return cached.reading
        }
        let reading: StoryRailDay
        if let usage {
            let snapshot = effectiveUsageSnapshot
            let stats = DashboardStats(sessions: engine.archive, usage: usage, usageSnapshot: snapshot, now: now)
            let segments = stats.timeline(for: day)
            let rhythm = stats.timelineWindow(for: day).map { Rhythm.hours(segments: segments, window: $0) } ?? []
            reading = StoryRailDay(
                goal: isCurrentDay ? goal
                    : GoalProgress(goal: engine.store.dailyGoal,
                                   achieved: focusedActiveSeconds(on: day, usageSnapshot: snapshot), typical: nil),
                apps: stats.rankedApps(for: day),
                rhythm: rhythm,
                rhythmPeak: Rhythm.peakLabel(rhythm) { DateFormats.hourLabel($0) })
        } else {
            reading = StoryRailDay(goal: GoalProgress(goal: engine.store.dailyGoal, achieved: 0, typical: nil),
                                   apps: [], rhythm: [], rhythmPeak: nil)
        }
        storyRailDayCache = (day, evidenceRevision, minute, reading)
        return reading
    }
}
