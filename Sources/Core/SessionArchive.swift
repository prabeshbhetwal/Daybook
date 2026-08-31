import Foundation

/// Local-only session history. A plain Codable JSON file in Application Support —
/// `UserDefaults` is a preferences store and its old 50-record ring held about a
/// week, far too little for streaks. Nothing here is ever transmitted.
final class SessionArchive {

    private enum WriteResult {
        case success
        case failure(String)
    }

    private let directory: URL
    private let fileURL: URL
    private let now: () -> Date
    private let calendar: Calendar
    private let capacity: Int
    /// Testable write boundary. Normal production instances leave this nil and
    /// use Foundation's atomic file replacement below.
    private let writeOverride: (([SessionRecord]) -> String?)?
    private var cache: [SessionRecord]

    init(directory: URL = SessionArchive.defaultDirectory,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         capacity: Int = FocusConstants.archiveCapacity,
         writeOverride: (([SessionRecord]) -> String?)? = nil) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("sessions.json")
        self.now = now
        self.calendar = calendar
        self.capacity = capacity
        self.writeOverride = writeOverride
        self.cache = []
        self.cache = load()
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("FocusContinuity", isDirectory: true)
    }

    // MARK: - Storage

    var records: [SessionRecord] { cache }

    func append(_ record: SessionRecord) {
        cache.append(record)
        if cache.count > capacity {
            cache.removeFirst(cache.count - capacity)
        }
        save()
    }

    /// Renames every record in a thread. Segments of one piece of work share a
    /// thread and a name, so renaming a stretch renames the work rather than
    /// splitting it into two differently-named halves. Returns whether anything
    /// changed, so a caller can skip a refresh it does not need.
    @discardableResult
    func rename(thread: UUID, to name: String) -> Bool {
        if case .applied = apply(.rename(name), toThread: thread) { return true }
        return false
    }

    /// Reclassifies every record in a thread. This is a correction to the
    /// record, so it moves the thread's time between the day's totals exactly
    /// as if it had been logged that way — including out of focus entirely when
    /// the correction is that it was rest.
    @discardableResult
    func setWorkType(_ workType: WorkType, forThread thread: UUID) -> Bool {
        if case .applied = apply(.workType(workType), toThread: thread) { return true }
        return false
    }

    /// Saves a complete candidate before exposing it through `records`. A
    /// correction therefore cannot claim success, change cache, or trigger a
    /// derived refresh when the durable write was refused.
    func apply(_ correction: SessionCorrection,
               toThread thread: UUID) -> SessionArchiveCorrectionResult {
        var candidate = cache
        var fields: [SessionArchiveCorrectionSnapshot.Fields] = []
        var changed = false

        for index in candidate.indices where candidate[index].threadID == thread {
            let record = candidate[index]
            switch correction {
            case .rename(let proposed):
                let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .unchanged }
                guard record.name != trimmed else { continue }
                fields.append(.init(recordID: record.id, name: record.name,
                                    workType: record.workType))
                candidate[index].name = trimmed
                changed = true
            case .workType(let proposed):
                guard record.workType != proposed else { continue }
                fields.append(.init(recordID: record.id, name: record.name,
                                    workType: record.workType))
                candidate[index].workType = proposed
                changed = true
            }
        }

        guard changed else { return .unchanged }
        switch write(candidate) {
        case .success:
            cache = candidate
            return .applied(.init(threadID: thread, correction: correction, fields: fields))
        case .failure(let error):
            return .failed(error)
        }
    }

    /// Restores the originally corrected records and any later continuations in
    /// one candidate/write. Only the field the correction touched is changed;
    /// timing, other fields and unrelated records remain evidence, not state to
    /// be rolled back.
    func restore(correction: SessionCorrection, inThread thread: UUID,
                 snapshot: SessionArchiveCorrectionSnapshot?,
                 recordsPresentAtCorrection recordIDs: Set<UUID>,
                 originalFields: (name: String, workType: WorkType))
        -> SessionArchiveCorrectionResult {
        let recordedOriginals = Dictionary(uniqueKeysWithValues: (snapshot?.fields ?? []).map {
            ($0.recordID, $0)
        })
        var candidate = cache
        var fields: [SessionArchiveCorrectionSnapshot.Fields] = []
        var changed = false
        for index in candidate.indices where candidate[index].threadID == thread {
            let record = candidate[index]
            let restore: SessionArchiveCorrectionSnapshot.Fields?
            if let original = recordedOriginals[record.id] {
                restore = original
            } else if !recordIDs.contains(record.id) {
                restore = .init(recordID: record.id, name: originalFields.name,
                                workType: originalFields.workType)
            } else {
                restore = nil
            }
            guard let restore else { continue }
            switch correction {
            case .rename:
                guard record.name != restore.name else { continue }
                fields.append(.init(recordID: record.id, name: record.name, workType: record.workType))
                candidate[index].name = restore.name
            case .workType:
                guard record.workType != restore.workType else { continue }
                fields.append(.init(recordID: record.id, name: record.name, workType: record.workType))
                candidate[index].workType = restore.workType
            }
            changed = true
        }
        guard changed else { return .unchanged }
        switch write(candidate) {
        case .success:
            cache = candidate
            return .applied(.init(threadID: thread, correction: correction, fields: fields))
        case .failure(let error): return .failed(error)
        }
    }

    private func load() -> [SessionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([SessionRecord].self, from: data)
        } catch {
            // Never wedge launch and never silently destroy history: move the bad
            // file aside so it can be inspected, and start clean.
            let stamp = Int(now().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("sessions-corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            Diagnostics.log("archive unreadable, moved to \(aside.lastPathComponent): \(error)")
            return []
        }
    }

    private func save() {
        switch write(cache) {
        case .success: break
        case .failure(let error): Diagnostics.log("failed to write archive: \(error)")
        }
    }

    private func write(_ candidate: [SessionRecord]) -> WriteResult {
        if let detail = writeOverride?(candidate) { return .failure(detail) }
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(candidate)
            try data.write(to: fileURL, options: .atomic)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Queries

    /// Every record with work on this day, not merely those that ended on it.
    /// A session that ran through midnight belongs to both days it touched.
    func records(on date: Date) -> [SessionRecord] {
        cache.filter { $0.workSeconds(on: date, calendar: calendar) > 0 }
    }

    /// Focused seconds attributable to a day, with cross-midnight sessions split
    /// between the days they cover rather than heaped on the later one. Breaks
    /// are excluded: they are recorded so a gap can be explained, not so it can
    /// be counted.
    func workSeconds(on date: Date) -> TimeInterval {
        cache.reduce(0) { total, record in
            guard record.workType.countsAsFocus else { return total }
            return total + record.workSeconds(on: date, calendar: calendar)
        }
    }

    func todayTotal() -> TimeInterval {
        workSeconds(on: now())
    }

    func sessionsToday() -> Int { threadCount(on: now()) }

    func longestToday() -> TimeInterval { longestThread(on: now())?.seconds ?? 0 }

    /// Focus *stretches* with work on a day: one per record. Since work carries
    /// on across a break, a session is a thread and several records can be one
    /// session — so the figures that say "sessions" count `threadCount(on:)`.
    /// This is the stretch count, kept for what is per stretch.
    func focusCount(on date: Date) -> Int {
        records(on: date).filter { $0.workType.countsAsFocus }.count
    }

    /// Sessions with work on a day, a session being a thread: work that was
    /// resumed after breaks counts once, however many stretches it took. The
    /// KPI, the hero, the calendar and the Sessions card all count this way,
    /// so "7 sessions" and "1 session · 7 stretches" can no longer share a
    /// screen.
    func threadCount(on date: Date) -> Int {
        Set(records(on: date).filter { $0.workType.countsAsFocus }.map(\.threadID)).count
    }

    /// The thread that contributed most work to a day, with the day's seconds
    /// and the intent its last stretch carried. A thread split by midnight is
    /// judged on its share of this day.
    func longestThread(on date: Date)
        -> (threadID: UUID, name: String, workType: WorkType, seconds: TimeInterval)? {
        var totals: [UUID: (name: String, workType: WorkType, seconds: TimeInterval, first: Date)] = [:]
        for record in records(on: date) where record.workType.countsAsFocus {
            var entry = totals[record.threadID] ?? (record.name, record.workType, 0, record.start)
            entry.seconds += record.workSeconds(on: date, calendar: calendar)
            if !record.name.isEmpty, record.start >= entry.first { entry.name = record.name }
            entry.first = min(entry.first, record.start)
            totals[record.threadID] = entry
        }
        // Ties go to the earlier thread, so the answer cannot change between
        // two refreshes of the same day.
        guard let best = totals.max(by: {
            ($0.value.seconds, $1.value.first) < ($1.value.seconds, $0.value.first)
        }), best.value.seconds > 0 else { return nil }
        return (best.key, best.value.name, best.value.workType, best.value.seconds)
    }

    /// One thread's archived work on a day — what its running stretch adds to.
    func threadWork(_ threadID: UUID, on date: Date) -> TimeInterval {
        records(on: date).reduce(0) { total, record in
            guard record.threadID == threadID, record.workType.countsAsFocus else { return total }
            return total + record.workSeconds(on: date, calendar: calendar)
        }
    }

    /// The focus session that contributed most work to a day, with that
    /// contribution — a record split by midnight is judged on its share of this
    /// day, not its whole. Returns the record as well as the figure because the
    /// stat row names what the longest session *was*; it used to print the
    /// busiest app's name beside it, which is a different measurement.
    func longestRecord(on date: Date) -> (record: SessionRecord, seconds: TimeInterval)? {
        var best: (record: SessionRecord, seconds: TimeInterval)?
        for record in cache where record.workType.countsAsFocus {
            let seconds = record.workSeconds(on: date, calendar: calendar)
            if seconds > 0, seconds > (best?.seconds ?? 0) { best = (record, seconds) }
        }
        return best
    }

    /// Focused seconds per day across the whole archive, cross-midnight work
    /// split. Built in one pass because the streak walks need every day at once.
    private func dailyTotals() -> [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for record in cache where record.workType.countsAsFocus {
            var cursor = calendar.startOfDay(for: record.start)
            let last = calendar.startOfDay(for: record.end)
            // Bounded so a single corrupt record with a wild end date cannot
            // spin here. Legacy data predates the span cap and can be long, but
            // nothing legitimate covers a year.
            var guardRail = 0
            while cursor <= last, guardRail < 400 {
                guardRail += 1
                let share = record.workSeconds(on: cursor, calendar: calendar)
                if share > 0 { totals[cursor, default: 0] += share }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        return totals
    }

    /// Seven bars ending today, oldest first.
    func weekBars() -> [DayBar] {
        let today = calendar.startOfDay(for: now())
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEEE"          // single-letter weekday

        let totals = dailyTotals()
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let seconds = totals[day] ?? 0
            return DayBar(id: day,
                          label: formatter.string(from: day),
                          minutes: Int(seconds / 60),
                          isToday: offset == 0)
        }
    }

    /// Consecutive days meeting `streakMinimum`. A streak ending yesterday still
    /// counts today, so today's zero does not erase it before the first session —
    /// which is exactly when the number needs to be motivating.
    /// - Parameter inFlight: seconds banked by a session that is still running.
    ///   Counted toward today, so the streak does not read 0 while you are working —
    ///   which is demoralising at exactly the moment the number exists to motivate.
    func currentStreak(includingToday inFlight: TimeInterval = 0) -> Int {
        var totals = dailyTotals()
        totals[calendar.startOfDay(for: now()), default: 0] += max(0, inFlight)

        var cursor = calendar.startOfDay(for: now())
        if (totals[cursor] ?? 0) < FocusConstants.streakMinimum {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while (totals[cursor] ?? 0) >= FocusConstants.streakMinimum {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Most-used (work type, intent) pairs from the recent window, most frequent
    /// first, ties broken by recency. Computed, never configured.
    /// The longest run of qualifying days ever recorded. A streak cannot be
    /// called a record without knowing what the record was.
    func bestStreak() -> Int {
        // The injected calendar, not `Calendar.current`: an archive built for a
        // test in another time zone was silently bucketing by the host's days.
        let totals = dailyTotals()
        let qualifying = totals
            .filter { $0.value >= FocusConstants.streakMinimum }
            .keys
            .sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in qualifying {
            if let previous,
               let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// Focused seconds on the same weekday a week ago — nil when that day has
    /// no records, so a comparison is never drawn against a blank.
    func focusedSameWeekdayLastWeek() -> TimeInterval? {
        guard let then = calendar.date(byAdding: .day, value: -7, to: now()) else { return nil }
        guard !records(on: then).isEmpty else { return nil }
        return workSeconds(on: then)
    }

    func quickStarts(limit: Int) -> [QuickStart] {
        let cutoff = now().addingTimeInterval(-Double(FocusConstants.quickStartWindowDays) * 86_400)
        var tally: [String: (item: QuickStart, count: Int, last: Date)] = [:]

        for record in cache where record.end >= cutoff && !record.name.isEmpty {
            let key = "\(record.workType.rawValue)|\(record.name)"
            let existing = tally[key]
            tally[key] = (item: QuickStart(id: key, name: record.name, workType: record.workType),
                          count: (existing?.count ?? 0) + 1,
                          last: max(existing?.last ?? .distantPast, record.end))
        }

        return tally.values
            .sorted { $0.count == $1.count ? $0.last > $1.last : $0.count > $1.count }
            .prefix(limit)
            .map(\.item)
    }
}
