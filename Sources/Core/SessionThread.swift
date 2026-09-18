import Foundation

/// One piece of work, across every segment of it worked today.
struct ThreadSummary: Identifiable, Equatable {
    let threadID: UUID
    let name: String
    let workType: WorkType
    let totalWorked: TimeInterval
    let segments: Int
    let firstStart: Date
    let lastEnd: Date
    let isRunning: Bool
    var id: UUID { threadID }
}

/// The live session as a thread, passed in rather than read from the engine so
/// `Core` stays free of the engine and the tests need no running state. Mirrors
/// how `focusQuality(for:runningSeconds:)` already takes the in-flight time.
struct RunningThread: Equatable {
    var recordID: UUID? = nil
    let threadID: UUID
    let name: String
    let workType: WorkType
    let start: Date
    let worked: TimeInterval
}

/// What a thread was worked *in*.
struct ThreadApps: Equatable {
    let primary: AppRank?
    let side: [AppRank]

    static let none = ThreadApps(primary: nil, side: [])
}

/// Groups the day's session records into threads and derives each thread's apps
/// from the usage archive.
///
/// Side apps are derived, never stored on the record: the usage archive already
/// holds that truth, and a stored copy would go stale the moment the grouping
/// rules changed.
struct ThreadStats {

    private let sessions: SessionArchive
    private let usage: AppUsageArchive?
    private let usageSnapshot: AppUsageSnapshot?
    private let overrides: [String: String]
    private let calendar: Calendar
    private let now: () -> Date
    private let continueWindow: TimeInterval

    init(sessions: SessionArchive,
         usage: AppUsageArchive? = nil,
         usageSnapshot: AppUsageSnapshot? = nil,
         purposeOverrides: [String: String] = [:],
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         continueWindow: TimeInterval = FocusConstants.continueWindow) {
        self.continueWindow = continueWindow
        self.sessions = sessions
        self.usage = usage
        self.usageSnapshot = usageSnapshot
        self.overrides = purposeOverrides
        self.calendar = calendar
        self.now = now
    }

    private struct Accumulator {
        var name: String
        var workType: WorkType
        var worked: TimeInterval
        var segments: Int
        var first: Date
        var last: Date
        var live: Bool
    }

    /// Newest last-end first. The running session, if any, is folded into its
    /// thread — or becomes a thread of its own if it is new work.
    func threads(on day: Date, running: RunningThread?) -> [ThreadSummary] {
        // Recent work, not the calendar day. `records(on:)` returns anything
        // that *overlaps* the day, so just after midnight it offered a session
        // begun the previous evening — and by the following afternoon it was
        // still offering it.
        let cutoff = now().addingTimeInterval(-continueWindow)

        // Rest is not resumable: a break record stays on the timeline and in
        // the log, but offering to "continue" it would start the Break session
        // the picker deliberately no longer offers.
        return summaries(records: sessions.records(on: day).filter {
            $0.end >= cutoff && $0.workType.countsAsFocus
        }, running: running)
    }

    /// Archive-wide threads for the Focus continuation source. Eligibility is
    /// assessed separately; this deliberately retains every recorded stretch
    /// in an eligible thread rather than turning the one-hour action window
    /// into a six-hour accounting cap.
    func continuationThreads(running: RunningThread?) -> [ThreadSummary] {
        summaries(records: sessions.records.filter(\.workType.countsAsFocus), running: running)
    }

    private func summaries(records: [SessionRecord], running: RunningThread?) -> [ThreadSummary] {
        var order: [UUID] = []
        var byThread: [UUID: Accumulator] = [:]
        for record in records.sorted(by: {
            if $0.end != $1.end { return $0.end < $1.end }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id.uuidString < $1.id.uuidString
        }) {
            if var existing = byThread[record.threadID] {
                existing.worked += record.workSeconds
                existing.segments += 1
                existing.first = min(existing.first, record.start)
                existing.name = record.name
                existing.workType = record.workType
                existing.last = max(existing.last, record.end)
                byThread[record.threadID] = existing
            } else {
                order.append(record.threadID)
                byThread[record.threadID] = Accumulator(name: record.name,
                                                        workType: record.workType,
                                                        worked: record.workSeconds,
                                                        segments: 1,
                                                        first: record.start,
                                                        last: record.end,
                                                        live: false)
            }
        }
        if let running {
            let end = now()
            if var existing = byThread[running.threadID] {
                existing.worked += running.worked
                existing.segments += 1
                existing.first = min(existing.first, running.start)
                existing.name = running.name
                existing.workType = running.workType
                existing.last = max(existing.last, end)
                existing.live = true
                byThread[running.threadID] = existing
            } else {
                order.append(running.threadID)
                byThread[running.threadID] = Accumulator(name: running.name,
                                                         workType: running.workType,
                                                         worked: running.worked,
                                                         segments: 1,
                                                         first: running.start,
                                                         last: end,
                                                         live: true)
            }
        }
        return order.compactMap { id -> ThreadSummary? in
            guard let entry = byThread[id] else { return nil }
            return ThreadSummary(threadID: id,
                                 name: entry.name,
                                 workType: entry.workType,
                                 totalWorked: entry.worked,
                                 segments: entry.segments,
                                 firstStart: entry.first,
                                 lastEnd: entry.last,
                                 isRunning: entry.live)
        }
        .sorted {
            if $0.lastEnd != $1.lastEnd { return $0.lastEnd > $1.lastEnd }
            return $0.threadID.uuidString > $1.threadID.uuidString
        }
    }

    /// Primary app and side apps for a thread, measured over the union of its
    /// segments' time ranges.
    func apps(for thread: ThreadSummary, on day: Date) -> ThreadApps {
        let ranges = segmentRanges(for: thread, on: day)
        guard !ranges.isEmpty else { return .none }

        var totals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        for session in usageSnapshot?.sessions ?? usage?.sessions ?? [] {
            var attended: TimeInterval = 0
            var longest: TimeInterval = 0
            for range in ranges {
                let start = max(session.start, range.start)
                let end = min(session.end, range.end)
                guard end > start else { continue }
                let overlap = end.timeIntervalSince(start)
                attended += overlap
                longest = max(longest, overlap)
            }
            guard attended > 0 else { continue }
            var entry = totals[session.bundleID] ?? (session.appName, 0, 0)
            entry.name = session.appName
            entry.total += attended
            entry.longest = max(entry.longest, longest)
            totals[session.bundleID] = entry
        }
        guard !totals.isEmpty else { return .none }

        let overall = totals.values.reduce(0) { $0 + $1.total }
        var ranks: [AppRank] = []
        for (bundleID, entry) in totals {
            ranks.append(AppRank(bundleID: bundleID,
                                 appName: entry.name,
                                 total: entry.total,
                                 share: overall > 0 ? entry.total / overall : 0,
                                 longest: entry.longest))
        }
        ranks.sort { $0.total > $1.total }

        // The tool the work was done *in* is the focused-purpose app, not
        // necessarily the one with the most minutes: a browser open beside an
        // editor all afternoon is support, not subject. Purpose is resolved at
        // `.active`, since these ranges are time the user declared as work.
        let primary = ranks.first {
            PurposeMap.purpose(for: $0.bundleID, activity: .active,
                               overrides: overrides).isFocused
        } ?? ranks.first

        let side = ranks.filter {
            $0.bundleID != primary?.bundleID && $0.total >= FocusConstants.sideAppMinimum
        }
        return ThreadApps(primary: primary, side: side)
    }

    private func segmentRanges(for thread: ThreadSummary,
                               on day: Date) -> [(start: Date, end: Date)] {
        var ranges = sessions.records(on: day)
            .filter { $0.threadID == thread.threadID }
            .map { (start: $0.start, end: $0.end) }
        if thread.isRunning {
            // The live segment: from the thread's last recorded end, or its own
            // start if there is none, up to now.
            ranges.append((start: ranges.last?.end ?? thread.firstStart, end: now()))
        }
        return ranges
    }
}
