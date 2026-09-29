import Foundation

/// Focus figures for Story prose and tiles. They deliberately do not reuse
/// `PeriodSummary`: that type describes observed app use and remains the
/// source for tracked bars and tracked averages.
struct StoryFocusSummary: Equatable {
    let focused: TimeInterval
    let activeDays: Int
    let averagePerActiveDay: TimeInterval
    /// An actual focus stretch, never a resumed thread total.
    let longestStretch: TimeInterval
    let longestName: String?
}

/// The evidence split behind Story's "On this Mac" tile. `tracked` is only
/// observed app use; focus work that cannot be credited by that evidence is a
/// separate qualification rather than being folded into the headline.
struct StoryUsageBreakdown: Equatable {
    let tracked: TimeInterval
    let insideSessions: TimeInterval
    let outsideSessions: TimeInterval
    let uncoveredFocus: TimeInterval
}

extension SessionStore {

    /// A reversible classification is itself dated History evidence even when
    /// its classified record has been removed. It never contributes fabricated
    /// focus, app use or a session count.
    func storyHistoryDaysIncludingDecisionReceipts(_ days: [HistoryDay],
                                                    calendar: Calendar = .current) -> [HistoryDay] {
        var result = days
        for receipt in engine.awayDecisions {
            var day = calendar.startOfDay(for: receipt.range.start)
            var visited = 0
            while day < receipt.range.end && visited < HistoryStats.maximumCalendarDaysPerRecord {
                visited += 1
                if !result.contains(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                    result.append(HistoryDay(date: day, tracked: 0, focused: 0,
                                             sessions: 0, appBundleIDs: [],
                                             workTypes: [receipt.workType]))
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    /// Declared focus attributable to one local day, including a running
    /// stretch where it intersects that day. The live projection is never
    /// written to `SessionArchive`.
    func storyFocusedSeconds(on day: Date) -> TimeInterval {
        let calendar = Calendar.current
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        return storyFocusedSeconds(in: DateInterval(start: bounds.start, end: bounds.end))
    }

    /// Focused seconds per category on a day, live stretch included, for the
    /// category goals under Focus time. Same accounting as the day's total,
    /// split by what each stretch was filed under.
    func storyCategorySeconds(on day: Date) -> [WorkType: TimeInterval] {
        let calendar = Calendar.current
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return [:] }
        let interval = (start: bounds.start, end: bounds.end)
        var seconds: [WorkType: TimeInterval] = [:]
        for record in engine.archive.records where record.workType.countsAsFocus {
            let worked = record.workSeconds(in: interval)
            if worked > 0 { seconds[record.workType, default: 0] += worked }
        }
        if engine.state != .idle, engine.activeWorkType.countsAsFocus {
            let start = max(engine.sessionStartDate, bounds.start)
            let end = min(now(), bounds.end)
            if end > start {
                let live = min(engine.elapsed, end.timeIntervalSince(start))
                if live > 0 { seconds[engine.activeWorkType, default: 0] += live }
            }
        }
        return seconds
    }

    /// Focus sessions are threads. A resumed thread with an archived earlier
    /// stretch and a running stretch remains one session on each affected day.
    func storySessionCount(on day: Date) -> Int {
        let calendar = Calendar.current
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        var threadIDs = Set(engine.archive.records.compactMap { record -> UUID? in
            guard record.workType.countsAsFocus,
                  record.workSeconds(in: bounds) > 0 else { return nil }
            return record.threadID
        })
        if storyRunningFocusSeconds(in: DateInterval(start: bounds.start, end: bounds.end)) > 0 {
            threadIDs.insert(engine.activeThreadID)
        }
        return threadIDs.count
    }

    /// The longest actual focus stretch on one local day. Resumed pieces keep
    /// one thread identity for session counts, but are never added together
    /// under a stretch label.
    func storyLongestStretch(on day: Date) -> TimeInterval {
        let calendar = Calendar.current
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        return storyLongestFocusStretch(
            in: DateInterval(start: bounds.start, end: bounds.end))?.seconds ?? 0
    }

    /// Story's focused-period values for the currently published Review range.
    /// The range is derived even before Review has published rows, so focus-only
    /// periods remain meaningful with an otherwise empty usage archive.
    var storyFocusSummary: StoryFocusSummary {
        let bounds = storyReviewBounds()
        let calendar = Calendar.current
        var days: [Date] = []
        var cursor = bounds.start
        while cursor < bounds.end && days.count < 40 {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        let focusedByDay = days.map { storyFocusedSeconds(on: $0) }
        let activeDays = focusedByDay.filter { $0 > 0 }.count
        let focused = focusedByDay.reduce(0, +)
        let longest = storyLongestFocusStretch(in: bounds)
        return StoryFocusSummary(
            focused: focused,
            activeDays: activeDays,
            averagePerActiveDay: activeDays > 0 ? focused / Double(activeDays) : 0,
            longestStretch: longest?.seconds ?? 0,
            longestName: longest?.name)
    }

    /// Evidence accounting for one explicit interval. Inside/outside classify
    /// observed app use by literal temporal membership in declared session
    /// spans. Credited focus is deliberately separate: it only determines the
    /// uncovered-work qualification below and never rewrites observed use.
    func storyUsageBreakdown(in interval: DateInterval) -> StoryUsageBreakdown {
        guard interval.duration > 0 else {
            return StoryUsageBreakdown(tracked: 0, insideSessions: 0,
                                       outsideSessions: 0, uncoveredFocus: 0)
        }
        let records = engine.archive.records
        let usageSessions = effectiveUsageSnapshot?.sessions ?? usage?.sessions ?? []
        let running = storyRunningSpan
        let runningWork = storyRunningFocusSeconds(in: interval)
        let focusRecords = records.filter { $0.workType.countsAsFocus }
        let focused = storyFocusedSeconds(in: interval)
        let credited = storyCreditedFocusSeconds(in: interval,
                                                 records: records,
                                                 usage: usageSessions,
                                                 running: running)

        let focusRanges = mergedStoryRanges(
            focusRecords.compactMap { record -> StoryRange? in
                guard record.workSeconds(in: (start: interval.start, end: interval.end)) > 0 else {
                    return nil
                }
                return StoryRange(start: record.start, end: record.end)
            } + (runningWork > 0 ? running.map { [StoryRange(start: $0.start, end: $0.end)] } ?? [] : []),
            clippedTo: interval)

        var tracked: TimeInterval = 0
        var rawInside: TimeInterval = 0
        for session in usageSessions {
            let start = max(session.start, interval.start)
            let end = min(session.end, interval.end)
            guard end > start else { continue }
            tracked += end.timeIntervalSince(start)
            for range in focusRanges {
                let overlapStart = max(start, range.start)
                let overlapEnd = min(end, range.end)
                if overlapEnd > overlapStart {
                    rawInside += overlapEnd.timeIntervalSince(overlapStart)
                }
            }
        }
        let inside = max(0, rawInside)
        return StoryUsageBreakdown(
            tracked: tracked,
            insideSessions: inside,
            outsideSessions: max(0, tracked - inside),
            uncoveredFocus: max(0, focused - credited))
    }

    /// Day convenience so Story Day never has to reimplement local boundaries.
    func storyUsageBreakdown(on day: Date) -> StoryUsageBreakdown {
        let calendar = Calendar.current
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else {
            return StoryUsageBreakdown(tracked: 0, insideSessions: 0,
                                       outsideSessions: 0, uncoveredFocus: 0)
        }
        return storyUsageBreakdown(in: DateInterval(start: bounds.start, end: bounds.end))
    }

    /// Evidence accounting for the current Review period.
    var storyUsageBreakdown: StoryUsageBreakdown {
        storyUsageBreakdown(in: storyReviewBounds())
    }

    /// Adds the in-flight projection to every local day it intersects in the
    /// canonical History result. No archive record is invented, and existing
    /// archive/app identities survive.
    func storyHistoryDaysIncludingRunning(_ days: [HistoryDay]) -> [HistoryDay] {
        let calendar = Calendar.current
        guard let running = storyRunningSpan else { return days }

        var result = days
        var day = calendar.startOfDay(for: running.start)
        let finalDay = calendar.startOfDay(for: running.end)
        var guardRail = 0
        while day <= finalDay && guardRail < HistoryStats.maximumCalendarDaysPerRecord {
            guardRail += 1
            let contributed = storyRunningFocusSeconds(on: day)
            if contributed > 0 {
                if let index = result.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                    let existing = result[index]
                    var workTypes = existing.workTypes
                    workTypes.insert(engine.activeWorkType)
                    result[index] = HistoryDay(date: existing.date,
                                               tracked: existing.tracked,
                                               focused: existing.focused + contributed,
                                               sessions: storySessionCount(on: day),
                                               appBundleIDs: existing.appBundleIDs,
                                               workTypes: workTypes,
                                               focusByWorkType: existing.focusByWorkType
                                                   .merging([engine.activeWorkType: contributed], uniquingKeysWith: +))
                } else {
                    result.append(HistoryDay(date: day, tracked: 0, focused: contributed,
                                             sessions: storySessionCount(on: day),
                                             appBundleIDs: [], workTypes: [engine.activeWorkType],
                                             focusByWorkType: [engine.activeWorkType: contributed]))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.sorted { $0.date > $1.date }
    }

    /// The interval published by Review, including focus-only periods before
    /// a tracked rollup has produced an entry for every day.
    func storyReviewBounds() -> DateInterval {
        let calendar = Calendar.current
        if let first = reviewDays.map(\.date).min(),
           let last = reviewDays.map(\.date).max(),
           let end = calendar.date(byAdding: .day, value: 1, to: last) {
            return DateInterval(start: first, end: end)
        }
        let anchor = reviewAnchor ?? calendar.startOfDay(for: now())
        let start = calendar.startOfDay(for: anchor)
        let component: Calendar.Component = reviewPeriod == .month ? .month : .weekOfYear
        let interval = calendar.dateInterval(of: component, for: start)
        let end = interval?.end ?? calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: interval?.start ?? start, end: end)
    }

    private struct StoryRange {
        var start: Date
        var end: Date
    }

    var storyRunningSpan: (start: Date, end: Date)? {
        guard engine.state != .idle, engine.activeWorkType.countsAsFocus else { return nil }
        return engine.runningSpan
    }

    private func storyFocusedSeconds(in interval: DateInterval) -> TimeInterval {
        let archived = engine.archive.records.reduce(0) { total, record in
            guard record.workType.countsAsFocus else { return total }
            return total + record.workSeconds(in: (start: interval.start, end: interval.end))
        }
        return archived + storyRunningFocusSeconds(in: interval)
    }

    func storyRunningFocusSeconds(on day: Date) -> TimeInterval {
        let calendar = Calendar.current
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        return storyRunningFocusSeconds(in: DateInterval(start: bounds.start, end: bounds.end))
    }

    /// Uses the engine's pause-aware live allocation, matching archived records.
    /// It is an ephemeral calculation, not a synthetic session record.
    func storyRunningFocusSeconds(in interval: DateInterval) -> TimeInterval {
        guard storyRunningSpan != nil else { return 0 }
        return engine.elapsed(in: (start: interval.start, end: interval.end))
    }

    /// Credit is calculated in canonical local-day slices. A paused span can
    /// cross midnight: capping it only once over a week would let observed use
    /// on one day consume another day's allocated work and erase that day's
    /// missing-coverage qualification.
    private func storyCreditedFocusSeconds(in interval: DateInterval,
                                           records: [SessionRecord],
                                           usage: [AppUsageSession],
                                           running: (start: Date, end: Date)?) -> TimeInterval {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: interval.start)
        var credited: TimeInterval = 0
        var guardRail = 0
        while cursor < interval.end && guardRail < HistoryStats.maximumCalendarDaysPerRecord {
            guardRail += 1
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let start = max(cursor, interval.start)
            let end = min(nextDay, interval.end)
            if end > start {
                let slice = DateInterval(start: start, end: end)
                credited += FocusedActiveTime.seconds(
                    in: slice,
                    records: records,
                    usage: usage,
                    running: running,
                    runningWork: storyRunningFocusSeconds(in: slice))
            }
            cursor = nextDay
        }
        return credited
    }

    private func storyLongestFocusStretch(in interval: DateInterval)
        -> (seconds: TimeInterval, name: String, start: Date)? {
        var candidates: [(seconds: TimeInterval, name: String, start: Date)] = []
        for record in engine.archive.records where record.workType.countsAsFocus {
            let seconds = record.workSeconds(in: (start: interval.start, end: interval.end))
            guard seconds > 0 else { continue }
            candidates.append((seconds: seconds,
                               name: record.workType.sessionTitle(named: record.name),
                               start: max(record.start, interval.start)))
        }
        if let running = storyRunningSpan {
            let seconds = storyRunningFocusSeconds(in: interval)
            if seconds > 0 {
                candidates.append((seconds: seconds,
                                   name: engine.sessionName.isEmpty
                                       ? engine.activeWorkType.displayName : engine.sessionName,
                                   start: max(running.start, interval.start)))
            }
        }
        return candidates.max { left, right in
            left.seconds == right.seconds ? left.start > right.start : left.seconds < right.seconds
        }
    }

    private func mergedStoryRanges(_ ranges: [StoryRange], clippedTo interval: DateInterval)
        -> [StoryRange] {
        let clipped = ranges.compactMap { range -> StoryRange? in
            let start = max(range.start, interval.start)
            let end = min(range.end, interval.end)
            return end > start ? StoryRange(start: start, end: end) : nil
        }
        .sorted { $0.start < $1.start }
        var result: [StoryRange] = []
        for range in clipped {
            if let last = result.last, range.start <= last.end {
                result[result.count - 1].end = max(last.end, range.end)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
