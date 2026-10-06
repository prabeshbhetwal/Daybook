import Foundation

// MARK: - Dashboard value types

struct TimelineSegment: Identifiable, Equatable {
    let id: UUID
    let bundleID: String
    let appName: String
    let start: Date
    let end: Date
    /// Stable within a day: the busiest app takes 0. 6 means "Other".
    let colorIndex: Int
    /// Carried through from the raw stretch so grouping can tell a detour from
    /// a real break.
    var endReason: UsageEndReason = .appSwitch

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct AppRank: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let total: TimeInterval
    let share: Double
    let longest: TimeInterval
    var id: String { bundleID }
}

/// Plain input so `Core` never imports AppKit and the tests need no real processes.
struct RunningAppInput: Equatable {
    let bundleID: String
    let appName: String
    let launched: Date?
    /// How long this app has been frontmost in the current unbroken stretch, or
    /// nil when it is not the one in front. Process uptime was what this used to
    /// carry, which made `Now: Claude 6h 50m` sit above `Claude 53m` in the same
    /// panel and mean something unrelated.
    var stretchSeconds: TimeInterval?
}

struct RunningApp: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let launched: Date?
    /// Seconds in the current unbroken stretch, or nil when this app is not the
    /// one in front.
    let openFor: TimeInterval?
    var id: String { bundleID }
}

struct FocusQuality: Equatable {
    let byWorkType: [WorkTypeShare]
    let insideSessionShare: Double
    let switchesPerSession: Double
    let sessionCount: Int
    /// Focus time that no app recording covers — a session ran, but usage was
    /// not being observed. Derived by subtraction from the same overlap that
    /// produces `insideSessionShare`, so the two can never disagree.
    var unrecordedFocusSeconds: TimeInterval = 0
}

struct WorkTypeShare: Identifiable, Equatable {
    let workType: WorkType
    let seconds: TimeInterval
    let share: Double
    var id: String { workType.rawValue }

    /// Each positive total as a share of their sum, largest first. Ties keep
    /// `WorkType.ordered`'s order.
    static func shares(from seconds: [WorkType: TimeInterval]) -> [WorkTypeShare] {
        let total = seconds.values.reduce(0, +)
        return WorkType.ordered(seconds.keys).compactMap { type in
            guard let value = seconds[type], value > 0 else { return nil }
            return WorkTypeShare(workType: type, seconds: value, share: total > 0 ? value / total : 0)
        }
        .sorted { $0.seconds > $1.seconds }
    }
}

struct Insight: Identifiable, Equatable {
    let id: String
    let headline: String
    let detail: String
    let symbolName: String
}

// MARK: - Computation

/// Everything the dashboard displays, computed from the two archives. Pure and
/// headless: no SwiftUI, no AppKit, injected clock. The three defects this
/// replaces were all computation bugs, which a view test would never have caught.
struct DashboardStats {

    private let sessions: SessionArchive
    private let usage: AppUsageArchive
    private let usageSnapshot: AppUsageSnapshot?
    private let now: () -> Date
    private let calendar: Calendar

    /// The day's segments, clipped, ranked and coloured once. Before this,
    /// `clippedUsage` ran again inside every query — four full scans of the usage
    /// array per refresh, each allocating its own tuples.
    private final class DaySliceCache {
        var day: Date?
        /// Archive revision when the slice was built. Count is insufficient:
        /// an open checkpoint is corrected in place under its stable UUID.
        var sourceRevision = -1
        var segments: [TimelineSegment] = []
        var ranks: [AppRank] = []
    }
    private let cache = DaySliceCache()

    /// Work type of the running session, folded into the work-type split.
    var activeWorkType: WorkType = .deepWork

    init(sessions: SessionArchive,
         usage: AppUsageArchive,
         usageSnapshot: AppUsageSnapshot? = nil,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.sessions = sessions
        self.usage = usage
        self.usageSnapshot = usageSnapshot
        self.calendar = calendar
        self.now = now
    }

    /// Truncates to the containing hour. `Calendar.date(bySetting:)` searches
    /// *forward* — for 9:45 it returns 10:00 — which silently put usage in the
    /// wrong hour.
    private func startOfHour(_ date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// The first calendar-hour boundary after `date`: the next whole wall-clock
    /// hour, or a sooner daylight-saving change. Stepping a fixed 3,600 s leaves
    /// the grid after a 30-minute change, and Foundation's `.hour` intervals
    /// overlap there, so the grid is walked boundary to boundary. Always later
    /// than `date`, so a loop over it makes progress.
    private func nextHourBoundary(after date: Date) -> Date {
        var next = calendar.nextDate(after: date, matching: DateComponents(minute: 0, second: 0),
                                     matchingPolicy: .nextTime) ?? date.addingTimeInterval(3_600)
        if let change = calendar.timeZone.nextDaylightSavingTimeTransition(after: date),
           change < next {
            next = change
        }
        return next > date ? next : date.addingTimeInterval(3_600)
    }

    // MARK: Day bounds

    private func bounds(of day: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Usage clipped to the day. A session spanning midnight contributes its
    /// overlap to each day and is never counted twice.
    private func clippedUsage(for day: Date) -> [(session: AppUsageSession,
                                                  start: Date, end: Date)] {
        let (dayStart, dayEnd) = bounds(of: day)
        return sourceSessions.compactMap { session in
            let start = max(session.start, dayStart)
            let end = min(session.end, dayEnd)
            guard end > start else { return nil }
            return (session, start, end)
        }
    }

    // MARK: The day slice — computed once, shared by every query

    private func build(for day: Date) {
        let clipped = clippedUsage(for: day)
        let total = clipped.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        var totals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        for entry in clipped {
            let seconds = entry.end.timeIntervalSince(entry.start)
            let existing = totals[entry.session.bundleID]
            totals[entry.session.bundleID] = (
                name: entry.session.appName,
                total: (existing?.total ?? 0) + seconds,
                longest: max(existing?.longest ?? 0, seconds))
        }

        // Built with an explicit loop: the chained map/sort over a tuple-valued
        // dictionary exceeded the type checker's budget.
        var ranks: [AppRank] = []
        ranks.reserveCapacity(totals.count)
        for (bundleID, value) in totals {
            // Guard the empty day: 0/0 would publish NaN into the UI.
            let share: Double = total > 0 ? value.total / total : 0
            ranks.append(AppRank(bundleID: bundleID,
                                 appName: value.name,
                                 total: value.total,
                                 share: share,
                                 longest: value.longest))
        }
        ranks.sort { left, right in
            left.total == right.total ? left.bundleID < right.bundleID
                                      : left.total > right.total
        }

        var indexByBundle: [String: Int] = [:]
        for (offset, rank) in ranks.enumerated() {
            indexByBundle[rank.bundleID] = min(offset, 6)
        }

        cache.ranks = ranks
        cache.segments = clipped
            .map { entry in
                TimelineSegment(id: entry.session.id,
                                bundleID: entry.session.bundleID,
                                appName: entry.session.appName,
                                start: entry.start,
                                end: entry.end,
                                colorIndex: indexByBundle[entry.session.bundleID] ?? 6,
                                endReason: entry.session.endReason)
            }
            .sorted { $0.start < $1.start }
        cache.day = day
        cache.sourceRevision = sourceRevision
    }

    private func ensure(_ day: Date) {
        if let cached = cache.day,
           calendar.isDate(cached, inSameDayAs: day),
           cache.sourceRevision == sourceRevision {
            return
        }
        build(for: day)
    }

    // MARK: Totals and rankings

    func trackedTotal(for day: Date) -> TimeInterval {
        ensure(day)
        return cache.segments.reduce(0) { $0 + $1.seconds }
    }

    /// Apps used inside the given spans of the day — what a session was worked
    /// in. Same ranking rule as the day's, over the intersection only.
    func rankedApps(for day: Date, within spans: [DateInterval]) -> [AppRank] {
        ensure(day)
        var totals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        var overall: TimeInterval = 0
        for segment in cache.segments {
            for span in spans {
                let start = max(segment.start, span.start)
                let end = min(segment.end, span.end)
                guard end > start else { continue }
                let seconds = end.timeIntervalSince(start)
                overall += seconds
                let existing = totals[segment.bundleID]
                totals[segment.bundleID] = (segment.appName,
                                            (existing?.total ?? 0) + seconds,
                                            max(existing?.longest ?? 0, seconds))
            }
        }
        return totals.map { bundleID, value in
            AppRank(bundleID: bundleID, appName: value.name, total: value.total,
                    share: overall > 0 ? value.total / overall : 0, longest: value.longest)
        }
        .sorted { $0.total == $1.total ? $0.bundleID < $1.bundleID : $0.total > $1.total }
    }

    /// Hands-on seconds inside the given spans of the day.
    func trackedTotal(for day: Date, within spans: [DateInterval]) -> TimeInterval {
        rankedApps(for: day, within: spans).reduce(0) { $0 + $1.total }
    }

    func rankedApps(for day: Date) -> [AppRank] {
        ensure(day)
        return cache.ranks
    }

    func timeline(for day: Date) -> [TimelineSegment] {
        ensure(day)
        return cache.segments
    }

    // MARK: Stretch grouping and hit-testing

    /// Every stretch of one app on one day, in order.
    func stretches(for day: Date, bundleID: String) -> [TimelineSegment] {
        timeline(for: day).filter { $0.bundleID == bundleID }
    }

    /// First start to last end for one app — the "9:02 am – 4:41 pm" span.
    func span(for day: Date, bundleID: String) -> (start: Date, end: Date)? {
        let mine = stretches(for: day, bundleID: bundleID)
        guard let first = mine.map(\.start).min(), let last = mine.map(\.end).max() else {
            return nil
        }
        return (first, last)
    }

    /// The segment covering an instant, for hover hit-testing. A gap returns nil.
    func segment(at date: Date, on day: Date) -> TimelineSegment? {
        timeline(for: day).first { $0.start <= date && date < $0.end }
    }

    /// One app's day grouped into sessions.
    func sessions(for day: Date, bundleID: String) -> [AppSession] {
        let all = timeline(for: day)
        return AppSessionGrouper.group(all.filter { $0.bundleID == bundleID },
                                       others: all.filter { $0.bundleID != bundleID })
    }

    /// Minutes per hour for one app, aligned to the timeline window so the strip
    /// and the band above it line up. The hours are the day's calendar hours,
    /// walked boundary to boundary from midnight: a daylight-saving change that
    /// moves the clock by 30 minutes (Lord Howe) leaves a 30-minute hour, never
    /// a bar that stepped off the grid and dropped the rest of the day.
    func hourlyBuckets(for day: Date, bundleID: String) -> [HourBucket] {
        guard let window = timelineWindow(for: day) else { return [] }
        let mine = stretches(for: day, bundleID: bundleID)
        var buckets: [HourBucket] = []
        var hour = calendar.startOfDay(for: day)
        while hour < window.end && buckets.count < 48 {
            let next = nextHourBoundary(after: hour)
            if next > window.start {
                let seconds = mine.reduce(0) { $0 + Self.overlap($1.start, $1.end, hour, next) }
                buckets.append(HourBucket(hour: hour, seconds: seconds))
            }
            hour = next
        }
        return buckets
    }

    /// Earliest day with any record, used to bound the date stepper.
    func earliestRecordedDay() -> Date? {
        let usageStart = sourceSessions.map(\.start).min()
        let sessionStart = sessions.records.map(\.start).min()
        let earliest = [usageStart, sessionStart].compactMap { $0 }.min()
        return earliest.map { calendar.startOfDay(for: $0) }
    }

    private var sourceSessions: [AppUsageSession] {
        usageSnapshot?.sessions ?? usage.sessions
    }

    private var sourceRevision: Int {
        usageSnapshot?.revision ?? usage.revision
    }

    /// The adaptive drawing window: an hour either side of the day's data,
    /// rounded outward, so an eight-hour day fills the width.
    func timelineWindow(for day: Date) -> (start: Date, end: Date)? {
        let segments = timeline(for: day)
        guard let first = segments.map(\.start).min(),
              let last = segments.map(\.end).max() else { return nil }
        let (dayStart, dayEnd) = bounds(of: day)

        // Snap outward to whole hours so the grid is uniform.
        var start = startOfHour(first)
        var end = startOfHour(last)
        if end < last { end = end.addingTimeInterval(3_600) }

        // Four minutes of data must not render as one block on a one-hour axis.
        let minimum = FocusConstants.minimumTimelineSpan
        if end.timeIntervalSince(start) < minimum {
            end = start.addingTimeInterval(minimum)
        }
        if end > dayEnd {
            end = dayEnd
            start = max(dayStart, end.addingTimeInterval(-minimum))
        }
        return (max(dayStart, start), end)
    }

    // MARK: Focus sessions

    /// Records with work on this day, not merely those that ended on it.
    func focusSessions(for day: Date) -> [SessionRecord] {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return [] }
        return sessions.records.compactMap { record in
            guard record.workType.countsAsFocus else { return nil }
            let work = record.workSeconds(in: bounds)
            guard work > 0 else { return nil }
            var clipped = record
            clipped.start = max(record.start, bounds.start)
            clipped.end = min(record.end, bounds.end)
            clipped.workSeconds = work
            return clipped
        }
    }

    /// The parts of each session that fall inside the day, merged so overlapping
    /// records cannot count the same second twice. Intersecting raw record spans
    /// against day-clipped usage was scoring a whole morning as "inside a
    /// session" whenever one record happened to span the previous night.
    private func focusRanges(for day: Date) -> [(start: Date, end: Date)] {
        let clipped = focusSessions(for: day)
            .map { (start: $0.start, end: $0.end) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        var merged: [(start: Date, end: Date)] = []
        for range in clipped {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Focus-only spans within the requested day, merged for timeline brackets.
    /// Breaks do not create a focus bracket or take part in any focus calculation.
    func focusSpans(for day: Date) -> [DateInterval] {
        focusRanges(for: day).map { DateInterval(start: $0.start, end: $0.end) }
    }

    /// - Parameter runningSeconds: work banked by a session still in flight. Passing
    ///   it keeps this in step with `sessionsToday`; without it the same screen can
    ///   read "1 session today" and "No sessions yet today".
    /// - Parameter runningThreadID: canonical identity of that in-flight thread,
    ///   preventing an archived earlier stretch of the same thread counting twice.
    func focusQuality(for day: Date,
                      runningSeconds: TimeInterval? = nil,
                      runningThreadID: UUID? = nil) -> FocusQuality {
        ensure(day)
        let records = focusSessions(for: day)
        let clipped = cache.segments.map { (session: $0, start: $0.start, end: $0.end) }
        let tracked = clipped.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        // Overlap between tracked time and time inside a focus session.
        let focused = focusRanges(for: day)
        var inside: TimeInterval = 0
        for entry in clipped {
            for range in focused { inside += Self.overlap(entry.start, entry.end, range.start, range.end) }
        }
        // The ranges are already merged, so their total is the focused span
        // counted once. What usage never saw is the remainder.
        let focusedSpan = focused.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let unrecorded = max(0, focusedSpan - inside)

        var byType: [WorkType: TimeInterval] = [:]
        for record in records {
            // This day's share, so a session split by midnight does not report
            // both of its days as full days of that work type.
            byType[record.workType, default: 0]
                += record.workSeconds(on: day, calendar: calendar)
        }
        if let runningSeconds, runningSeconds > 0, activeWorkType.countsAsFocus {
            byType[activeWorkType, default: 0] += runningSeconds
        }
        let shares = WorkTypeShare.shares(from: byType)

        // The same rule as the range overload, so one body of evidence reads the
        // same from either: a resumed thread is one thread, whatever the gap.
        var rangesByThread: [UUID: [DateInterval]] = [:]
        for record in records where record.end > record.start {
            rangesByThread[record.threadID, default: []]
                .append(DateInterval(start: record.start, end: record.end))
        }
        let switches = Self.appSwitches(
            in: rangesByThread,
            usage: cache.segments.map { ($0.bundleID, $0.start, $0.end) })

        let threadIDs = Set(records.map(\.threadID))
        let runningCount: Int
        if runningSeconds != nil, activeWorkType.countsAsFocus {
            runningCount = runningThreadID.map(threadIDs.contains) == true ? 0 : 1
        } else {
            runningCount = 0
        }
        let count = threadIDs.count + runningCount
        return FocusQuality(
            byWorkType: shares,
            insideSessionShare: tracked > 0 ? min(1, inside / tracked) : 0,
            switchesPerSession: count == 0 ? 0 : Double(switches) / Double(count),
            sessionCount: count,
            unrecordedFocusSeconds: unrecorded)
    }

    /// Canonical quality for a multi-day evidence range. Unlike summing daily
    /// `FocusQuality` values, this keeps one denominator entry per thread across
    /// local midnight and resumed stretches, then derives app transitions from
    /// the ordered usage identities that intersect that thread anywhere in the
    /// selected range.
    ///
    /// Running work preserves the daily contract: it contributes work type and
    /// one deduplicated thread identity, while app-intersection/switch evidence
    /// remains based on closed canonical ranges until that stretch is archived.
    func focusQuality(for days: [Date],
                      runningSeconds: TimeInterval? = nil,
                      runningThreadID: UUID? = nil) -> FocusQuality {
        var seenDays: Set<Date> = []
        let dayIntervals: [DateInterval] = days.compactMap { day in
            let start = calendar.startOfDay(for: day)
            guard seenDays.insert(start).inserted,
                  let bounds = SessionRecord.dayBounds(start, calendar: calendar) else {
                return nil
            }
            return DateInterval(start: bounds.start, end: bounds.end)
        }
        .sorted { $0.start < $1.start }
        guard !dayIntervals.isEmpty else {
            return FocusQuality(byWorkType: [], insideSessionShare: 0,
                                switchesPerSession: 0, sessionCount: 0)
        }

        var byType: [WorkType: TimeInterval] = [:]
        var threadIDs: Set<UUID> = []
        var rangesByThread: [UUID: [DateInterval]] = [:]
        for record in sessions.records where record.workType.countsAsFocus {
            for bounds in dayIntervals {
                let worked = record.workSeconds(in: (start: bounds.start, end: bounds.end))
                guard worked > 0 else { continue }
                byType[record.workType, default: 0] += worked
                threadIDs.insert(record.threadID)
                let start = max(record.start, bounds.start)
                let end = min(record.end, bounds.end)
                if end > start {
                    rangesByThread[record.threadID, default: []]
                        .append(DateInterval(start: start, end: end))
                }
            }
        }

        var anonymousRunningCount = 0
        if let runningSeconds, activeWorkType.countsAsFocus {
            if runningSeconds > 0 {
                byType[activeWorkType, default: 0] += runningSeconds
            }
            if let runningThreadID { threadIDs.insert(runningThreadID) }
            else { anonymousRunningCount = 1 }
        }

        let shares = WorkTypeShare.shares(from: byType)

        let orderedUsage = sourceSessions
            .filter { session in
                dayIntervals.contains { interval in
                    session.start < interval.end && session.end > interval.start
                }
            }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                return $0.id.uuidString < $1.id.uuidString
            }

        var tracked: TimeInterval = 0
        for session in orderedUsage {
            for interval in dayIntervals {
                tracked += Self.overlap(session.start, session.end, interval.start, interval.end)
            }
        }

        let allFocusRanges = Self.mergeRanges(rangesByThread.values.flatMap { $0 })
        var inside: TimeInterval = 0
        for session in orderedUsage {
            for range in allFocusRanges {
                inside += Self.overlap(session.start, session.end, range.start, range.end)
            }
        }
        // Focused time the usage record never saw, clipped to the range so a
        // thread crossing its edge does not contribute time outside it.
        var focusedSpan: TimeInterval = 0
        for range in allFocusRanges {
            for interval in dayIntervals {
                focusedSpan += Self.overlap(range.start, range.end, interval.start, interval.end)
            }
        }
        let unrecorded = max(0, focusedSpan - inside)

        let switches = Self.appSwitches(
            in: rangesByThread,
            usage: orderedUsage.map { ($0.bundleID, $0.start, $0.end) })

        let count = threadIDs.count + anonymousRunningCount
        return FocusQuality(
            byWorkType: shares,
            insideSessionShare: tracked > 0 ? min(1, inside / tracked) : 0,
            switchesPerSession: count > 0 ? Double(switches) / Double(count) : 0,
            sessionCount: count,
            unrecordedFocusSeconds: unrecorded)
    }

    /// Identity CHANGES among the usage inside each thread's canonical focus
    /// ranges, `usage` in time order. The first app observed is context, not a
    /// switch, and a same-app checkpoint split is persistence detail rather
    /// than interruption evidence. A thread resumed after a gap is still one
    /// thread, so the change from the app it left to the app it came back to
    /// counts.
    private static func appSwitches(in rangesByThread: [UUID: [DateInterval]],
                                    usage: [(bundleID: String, start: Date, end: Date)]) -> Int {
        var switches = 0
        for ranges in rangesByThread.values {
            let canonicalRanges = mergeRanges(ranges)
            var previousBundleID: String?
            for entry in usage where canonicalRanges.contains(where: {
                entry.start < $0.end && entry.end > $0.start
            }) {
                if let previousBundleID, previousBundleID != entry.bundleID {
                    switches += 1
                }
                previousBundleID = entry.bundleID
            }
        }
        return switches
    }

    /// Seconds two spans share; zero when they do not meet, or when either
    /// runs backwards. `DateInterval.intersection` would trap on the latter.
    private static func overlap(_ startA: Date, _ endA: Date, _ startB: Date, _ endB: Date) -> TimeInterval {
        max(0, min(endA, endB).timeIntervalSince(max(startA, startB)))
    }

    private static func mergeRanges(_ ranges: [DateInterval]) -> [DateInterval] {
        let ordered = ranges.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for range in ordered {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start, end: max(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    // MARK: Running apps

    func runningNow(from inputs: [RunningAppInput]) -> [RunningApp] {
        inputs
            // No launch date means nothing useful can be said: Finder is started
            // at login, runs permanently, and its row could only ever read
            // "since login". Excluded rather than listed uninformatively.
            .compactMap { input -> RunningApp? in
                guard input.launched != nil else { return nil }
                return RunningApp(bundleID: input.bundleID,
                                  appName: input.appName,
                                  launched: input.launched,
                                  openFor: input.stretchSeconds)
            }
            // The app you are actually in leads; the rest keep a stable order so
            // the list does not reshuffle on every refresh.
            .sorted {
                ($0.openFor ?? -1, $1.appName) > ($1.openFor ?? -1, $0.appName)
            }
    }

    // MARK: Insights — each gated, never fabricated

    func insights(for day: Date) -> [Insight] {
        // Focus quality already states the work-type split, and repeating a figure
        // makes the reader distrust both copies.
        [longestStretch(day), insideSession(day), versusYesterday(day)]
            .compactMap { $0 }
    }

    private func longestStretch(_ day: Date) -> Insight? {
        guard let top = timeline(for: day).max(by: { $0.seconds < $1.seconds }),
              top.seconds > 0 else { return nil }
        // The headline names the measure; the detail carries the evidence.
        // "Longest stretch / Claude, 10m" said neither what nor when.
        return Insight(id: "longest-stretch",
                       headline: "Longest stretch in one app",
                       detail: "\(DurationText.compact(top.seconds)) in \(top.appName), "
                             + DateFormats.clockRange(top.start, top.end),
                       symbolName: "arrow.up.right")
    }

    private func insideSession(_ day: Date) -> Insight? {
        let quality = focusQuality(for: day)
        // A flat 0% teaches nothing; hide it rather than print a useless number.
        guard quality.sessionCount > 0,
              trackedTotal(for: day) > 0,
              quality.insideSessionShare > 0 else { return nil }
        let tracked = trackedTotal(for: day)
        return Insight(id: "inside-session",
                       headline: "\(DurationText.percent(quality.insideSessionShare)) of tracked time was in a focus session",
                       detail: "\(DurationText.compact(tracked * quality.insideSessionShare)) "
                             + "of \(DurationText.compact(tracked)) tracked",
                       symbolName: "target")
    }

    private func versusYesterday(_ day: Date) -> Insight? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
        let todayTotal = trackedTotal(for: day)
        let yesterdayTotal = trackedTotal(for: yesterday)
        guard todayTotal > 0, yesterdayTotal > 0 else { return nil }
        let delta = todayTotal - yesterdayTotal
        let direction = delta >= 0 ? "more" : "less"
        // A delta without its baseline is not an insight: carry both sides.
        return Insight(id: "vs-yesterday",
                       headline: "\(DurationText.compact(abs(delta))) \(direction) than yesterday",
                       detail: "\(DurationText.compact(todayTotal)) today, "
                             + "\(DurationText.compact(yesterdayTotal)) yesterday",
                       symbolName: delta >= 0 ? "chart.line.uptrend.xyaxis"
                                              : "chart.line.downtrend.xyaxis")
    }
}

/// One app's day: total plus every individual stretch, for the Earlier today
/// section and the expanded Top-apps row.
struct AppDayHistory: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let total: TimeInterval
    let colorIndex: Int
    /// Grouped sittings, newest first — not raw stretches.
    let sessions: [AppSession]
    var id: String { bundleID }
}
