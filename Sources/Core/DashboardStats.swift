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
}

struct WorkTypeShare: Identifiable, Equatable {
    let workType: WorkType
    let seconds: TimeInterval
    let share: Double
    var id: String { workType.rawValue }
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
    private let now: () -> Date
    private let calendar: Calendar

    /// The day's segments, clipped, ranked and coloured once. Before this,
    /// `clippedUsage` ran again inside every query — four full scans of the usage
    /// array per refresh, each allocating its own tuples.
    private final class DaySliceCache {
        var day: Date?
        /// Archive size when the slice was built. Without this the cache serves
        /// stale data after the tracker records a new stretch — a trap, since
        /// nothing would fail loudly.
        var sourceCount = -1
        var segments: [TimelineSegment] = []
        var ranks: [AppRank] = []
    }
    private let cache = DaySliceCache()

    /// Work type of the running session, folded into the work-type split.
    var activeWorkType: WorkType = .deepWork

    init(sessions: SessionArchive,
         usage: AppUsageArchive,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.sessions = sessions
        self.usage = usage
        self.calendar = calendar
        self.now = now
    }

    /// Truncates to the containing hour. `Calendar.date(bySetting:)` searches
    /// *forward* — for 9:45 it returns 10:00 — which silently put usage in the
    /// wrong hour.
    private func startOfHour(_ date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
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
        return usage.sessions.compactMap { session in
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
        cache.sourceCount = usage.sessions.count
    }

    private func ensure(_ day: Date) {
        if let cached = cache.day,
           calendar.isDate(cached, inSameDayAs: day),
           cache.sourceCount == usage.sessions.count {
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
    /// and the band above it line up.
    func hourlyBuckets(for day: Date, bundleID: String) -> [HourBucket] {
        var totals: [Date: TimeInterval] = [:]
        for stretch in stretches(for: day, bundleID: bundleID) {
            var cursor = stretch.start
            while cursor < stretch.end {
                let hour = startOfHour(cursor)
                let hourEnd = hour.addingTimeInterval(3_600)
                let slice = min(stretch.end, hourEnd).timeIntervalSince(cursor)
                totals[hour, default: 0] += max(0, slice)
                cursor = hourEnd
            }
        }
        guard let window = timelineWindow(for: day) else { return [] }
        var buckets: [HourBucket] = []
        var hour = window.start
        while hour < window.end && buckets.count < 48 {
            buckets.append(HourBucket(hour: hour, seconds: totals[hour] ?? 0))
            hour = hour.addingTimeInterval(3_600)
        }
        return buckets
    }

    /// Earliest day with any record, used to bound the date stepper.
    func earliestRecordedDay() -> Date? {
        let usageStart = usage.sessions.map(\.start).min()
        let sessionStart = sessions.records.map(\.start).min()
        let earliest = [usageStart, sessionStart].compactMap { $0 }.min()
        return earliest.map { calendar.startOfDay(for: $0) }
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
        sessions.records.filter { $0.workSeconds(on: day, calendar: calendar) > 0 }
    }

    /// The parts of each session that fall inside the day, merged so overlapping
    /// records cannot count the same second twice. Intersecting raw record spans
    /// against day-clipped usage was scoring a whole morning as "inside a
    /// session" whenever one record happened to span the previous night.
    private func focusRanges(for day: Date) -> [(start: Date, end: Date)] {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return [] }
        let clipped = focusSessions(for: day)
            .map { (start: max($0.start, bounds.start), end: min($0.end, bounds.end)) }
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

    /// - Parameter runningSeconds: work banked by a session still in flight. Passing
    ///   it keeps this in step with `sessionsToday`; without it the same screen can
    ///   read "1 session today" and "No sessions yet today".
    func focusQuality(for day: Date, runningSeconds: TimeInterval? = nil) -> FocusQuality {
        ensure(day)
        let records = focusSessions(for: day)
        let clipped = cache.segments.map { (session: $0, start: $0.start, end: $0.end) }
        let tracked = clipped.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        // Overlap between tracked time and time inside a focus session.
        let focused = focusRanges(for: day)
        var inside: TimeInterval = 0
        for entry in clipped {
            for range in focused {
                let start = max(entry.start, range.start)
                let end = min(entry.end, range.end)
                if end > start { inside += end.timeIntervalSince(start) }
            }
        }

        var byType: [WorkType: TimeInterval] = [:]
        for record in records {
            // This day's share, so a session split by midnight does not report
            // both of its days as full days of that work type.
            byType[record.workType, default: 0]
                += record.workSeconds(on: day, calendar: calendar)
        }
        if let runningSeconds, runningSeconds > 0 {
            byType[activeWorkType, default: 0] += runningSeconds
        }
        let typeTotal = byType.values.reduce(0, +)
        let shares = WorkType.allCases.compactMap { type -> WorkTypeShare? in
            guard let seconds = byType[type], seconds > 0 else { return nil }
            return WorkTypeShare(workType: type,
                                 seconds: seconds,
                                 share: typeTotal > 0 ? seconds / typeTotal : 0)
        }
        .sorted { $0.seconds > $1.seconds }

        // App switches that happened while a session was running.
        let switches = clipped.filter { entry in
            focused.contains { $0.start <= entry.start && entry.start < $0.end }
        }.count

        let count = records.count + (runningSeconds != nil ? 1 : 0)
        return FocusQuality(
            byWorkType: shares,
            insideSessionShare: tracked > 0 ? min(1, inside / tracked) : 0,
            switchesPerSession: count == 0 ? 0 : Double(switches) / Double(count),
            sessionCount: count)
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
        // `deepWorkShare` is deliberately absent: the Focus quality section already
        // states it, and repeating a figure makes the reader distrust both copies.
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
                       detail: "\(durationPhrase(top.seconds)) in \(top.appName), "
                             + clockRange(top.start, top.end),
                       symbolName: "arrow.up.right")
    }

    private func insideSession(_ day: Date) -> Insight? {
        let quality = focusQuality(for: day)
        // A flat 0% teaches nothing; hide it rather than print a useless number.
        guard quality.sessionCount > 0,
              trackedTotal(for: day) > 0,
              quality.insideSessionShare > 0 else { return nil }
        let tracked = trackedTotal(for: day)
        let percent = Int((quality.insideSessionShare * 100).rounded())
        return Insight(id: "inside-session",
                       headline: "\(percent)% of tracked time was in a focus session",
                       detail: "\(durationPhrase(tracked * quality.insideSessionShare)) "
                             + "of \(durationPhrase(tracked)) tracked",
                       symbolName: "target")
    }

    private func deepWorkShare(_ day: Date) -> Insight? {
        let quality = focusQuality(for: day)
        guard let deep = quality.byWorkType.first(where: { $0.workType == .deepWork }),
              deep.share > 0 else { return nil }
        return Insight(id: "deep-work-share",
                       headline: "Deep work \(Int((deep.share * 100).rounded()))%",
                       detail: "of your session time today",
                       symbolName: "brain.head.profile")
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
                       headline: "\(durationPhrase(abs(delta))) \(direction) than yesterday",
                       detail: "\(durationPhrase(todayTotal)) today, "
                             + "\(durationPhrase(yesterdayTotal)) yesterday",
                       symbolName: delta >= 0 ? "chart.line.uptrend.xyaxis"
                                              : "chart.line.downtrend.xyaxis")
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// `Core` cannot import the Design layer, so it carries its own formatter.
    private func clockRange(_ start: Date, _ end: Date) -> String {
        "\(clock(start)) – \(clock(end))"
    }

    /// A clock time that cannot be split by a line wrap. The only space in
    /// "11:25 am" is the one before the meridiem, and breaking there left a line
    /// ending "11:25" and the next beginning "am – 11:31 am", which reads as a
    /// different time entirely.
    private func clock(_ date: Date) -> String {
        DashboardStats.clockFormatter.string(from: date)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// Core cannot import the Design layer, so it carries its own phrasing.
    private func durationPhrase(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
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
