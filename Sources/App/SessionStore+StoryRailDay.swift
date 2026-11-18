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
    /// The day in eight 3-hour blocks, with focus told apart from other use.
    var blocks: [RhythmBlock] = []
    /// Focus with app use recorded, per category id, as the daily goal counts
    /// it: what each category goal is measured against.
    var creditByCategory: [String: TimeInterval] = [:]
}

extension SessionStore {
    /// One day's rail figures, cached until the evidence changes (and, for
    /// today or any day the running session reaches into, until the minute
    /// turns over: yesterday's goal counts a session still open past midnight,
    /// and discarding that session must not leave its credit behind).
    func storyRailDay(on requested: Date) -> StoryRailDay {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: requested)
        let isCurrentDay = calendar.isDate(day, inSameDayAs: now())
        let runningTouchesDay = calendar.dateInterval(of: .day, for: day).map { bounds in
            engine.runningSpan.map { $0.end > bounds.start && $0.start < bounds.end } ?? false
        } ?? false
        let minute = isCurrentDay || runningTouchesDay ? Int(now().timeIntervalSinceReferenceDate / 60) : 0
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
                rhythmPeak: Rhythm.peakLabel(rhythm) { DateFormats.hourLabel($0) },
                blocks: rhythmBlocks(segments: segments, day: day, usage: snapshot?.sessions ?? usage.sessions),
                creditByCategory: categoryCredit(on: day, usage: snapshot?.sessions ?? usage.sessions))
        } else {
            reading = StoryRailDay(goal: GoalProgress(goal: engine.store.dailyGoal, achieved: 0, typical: nil),
                                   apps: [], rhythm: [], rhythmPeak: nil)
        }
        storyRailDayCache = (day, evidenceRevision, minute, reading)
        return reading
    }

    /// Eight credit calls, one per block, made once a minute at most: the
    /// reading above is cached on the evidence and the minute.
    private func rhythmBlocks(segments: [TimelineSegment], day: Date,
                              usage: [AppUsageSession]) -> [RhythmBlock] {
        let records = engine.archive.records
        let running = storyRunningSpan
        return Rhythm.blocks(segments: segments, day: day, now: now()) { block in
            storyCreditedFocusSeconds(in: block, records: records, usage: usage, running: running)
        }
    }

    /// Each category's credited focus on a day, by the same accounting as the
    /// day's goal, so a category row can never exceed the ring's figure.
    func categoryCredit(on day: Date, usage: [AppUsageSession]) -> [String: TimeInterval] {
        guard let bounds = SessionRecord.dayBounds(day, calendar: Calendar.current) else { return [:] }
        let interval = DateInterval(start: bounds.start, end: bounds.end)
        let records = engine.archive.records
        let running = storyRunningSpan
        var types = Set(records.filter {
            $0.workType.countsAsFocus && $0.workSeconds(in: (start: bounds.start, end: bounds.end)) > 0
        }.map(\.workType))
        if running != nil, engine.activeWorkType.countsAsFocus { types.insert(engine.activeWorkType) }
        var credit: [String: TimeInterval] = [:]
        for type in types {
            let seconds = storyCreditedFocusSeconds(
                in: interval, records: records.filter { $0.workType == type }, usage: usage,
                running: type == engine.activeWorkType ? running : nil)
            if seconds > 0 { credit[type.rawValue] = seconds }
        }
        return credit
    }
}
