import Foundation

/// One session that matched a History search: the record, its day, and the
/// words that matched, so the result can say why it is here.
struct HistorySearchHit: Identifiable, Equatable {
    let id: UUID
    let threadID: UUID
    let name: String
    let workType: WorkType
    let start: Date
    let end: Date
    let worked: TimeInterval
    let day: Date
    /// The note's text when the note matched, trimmed to a line.
    let noteSnippet: String?
    /// App names on the day when an app matched.
    let matchedApps: [String]
}

/// Everything on record, summed once: what the History page opens with.
struct HistoryArchiveFacts: Equatable {
    let firstDay: Date?
    let dayCount: Int
    let sessionCount: Int
    let focused: TimeInterval
    let bestMonth: (start: Date, focused: TimeInterval)?
    let longestStreak: Int
    let categories: [WorkTypeShare]
    let apps: [AppRank]
    /// Focused seconds per local day, for the map.
    let focusByDay: [Date: TimeInterval]
    /// Recorded app use per local day, so a day at the Mac with no session
    /// still shows as a day.
    let trackedByDay: [Date: TimeInterval]

    static let empty = HistoryArchiveFacts(firstDay: nil, dayCount: 0, sessionCount: 0, focused: 0,
                                           bestMonth: nil, longestStreak: 0, categories: [], apps: [],
                                           focusByDay: [:], trackedByDay: [:])

    static func == (lhs: HistoryArchiveFacts, rhs: HistoryArchiveFacts) -> Bool {
        lhs.firstDay == rhs.firstDay && lhs.dayCount == rhs.dayCount && lhs.sessionCount == rhs.sessionCount
            && lhs.focused == rhs.focused && lhs.longestStreak == rhs.longestStreak
            && lhs.bestMonth?.start == rhs.bestMonth?.start && lhs.categories == rhs.categories
            && lhs.apps == rhs.apps
    }

    /// The calendar years with anything on record, newest first.
    func years(calendar: Calendar = .current, now: Date) -> [Int] {
        var set = Set<Int>()
        for day in focusByDay.keys { set.insert(calendar.component(.year, from: day)) }
        for day in trackedByDay.keys { set.insert(calendar.component(.year, from: day)) }
        set.insert(calendar.component(.year, from: now))
        return set.sorted(by: >)
    }

    func focused(inYear year: Int, calendar: Calendar = .current) -> TimeInterval {
        focusByDay.reduce(0) { calendar.component(.year, from: $1.key) == year ? $0 + $1.value : $0 }
    }
}

extension SessionStore {
    /// Sessions whose name, note, category, apps or date contain the query,
    /// newest first. The app and category menus narrow the same list.
    func historySearchHits(limit: Int = 200) -> [HistorySearchHit] {
        let calendar = Calendar.current
        let filter = historyFilter
        let needle = filter.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty || filter.appBundleID != nil || filter.workType != nil else { return [] }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_AU")
        dayFormatter.dateFormat = "EEEE d MMMM yyyy"
        let stable = DateFormatter()
        stable.locale = Locale(identifier: "en_US_POSIX")
        stable.dateFormat = "yyyy-MM-dd"
        let daysByDate = Dictionary(uniqueKeysWithValues: historyDays.map { (calendar.startOfDay(for: $0.date), $0) })

        var hits: [HistorySearchHit] = []
        for record in engine.archive.records.sorted(by: { $0.start > $1.start }) {
            let day = calendar.startOfDay(for: record.start)
            let historyDay = daysByDate[day]
            if let type = filter.workType, record.workType != type { continue }
            if let app = filter.appBundleID, !(historyDay?.appBundleIDs.contains(app) ?? false) { continue }
            let note = metadataArchive.metadata(for: record.id)?.note ?? ""
            var noteSnippet: String?
            var matchedApps: [String] = []
            if !needle.isEmpty {
                let name = record.name.lowercased()
                let type = record.workType.displayName.lowercased()
                let dateText = (dayFormatter.string(from: record.start) + " " + stable.string(from: record.start)).lowercased()
                let apps = (historyDay?.appBundleIDs ?? []).map(historyAppName(for:))
                matchedApps = apps.filter { $0.lowercased().contains(needle) }
                let noteMatches = note.lowercased().contains(needle)
                guard name.contains(needle) || type.contains(needle) || dateText.contains(needle)
                        || noteMatches || !matchedApps.isEmpty else { continue }
                if noteMatches {
                    noteSnippet = note.split(whereSeparator: \.isNewline)
                        .first { $0.lowercased().contains(needle) }
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                }
            }
            // Stretches of one session on one day are one result, as they are
            // one card in the story.
            if let index = hits.firstIndex(where: { $0.threadID == record.threadID && $0.day == day }) {
                let joined = hits[index]
                hits[index] = HistorySearchHit(id: joined.id, threadID: joined.threadID,
                                               name: joined.name, workType: joined.workType,
                                               start: min(joined.start, record.start),
                                               end: max(joined.end, record.end),
                                               worked: joined.worked + record.workSeconds, day: day,
                                               noteSnippet: joined.noteSnippet ?? noteSnippet,
                                               matchedApps: joined.matchedApps)
                continue
            }
            hits.append(HistorySearchHit(id: record.id, threadID: record.threadID,
                                         name: record.name.isEmpty ? record.workType.displayName : record.name,
                                         workType: record.workType, start: record.start, end: record.end,
                                         worked: record.workSeconds, day: day,
                                         noteSnippet: noteSnippet, matchedApps: matchedApps))
            if hits.count >= limit { break }
        }
        return hits
    }

    /// The whole archive summed once per evidence revision.
    func historyArchiveFacts() -> HistoryArchiveFacts {
        let revision = evidenceRevision
        if let cached = historyArchiveFactsCache, cached.revision == revision { return cached.facts }
        let facts = buildHistoryArchiveFacts()
        historyArchiveFactsCache = (revision, facts)
        return facts
    }

    private func buildHistoryArchiveFacts() -> HistoryArchiveFacts {
        let calendar = Calendar.current
        var focusByDay: [Date: TimeInterval] = [:]
        var trackedByDay: [Date: TimeInterval] = [:]
        for day in historyDays {
            let key = calendar.startOfDay(for: day.date)
            focusByDay[key] = day.focused
            trackedByDay[key] = day.tracked
        }
        if historyDays.isEmpty {
            // Before the review index exists, the archive's own records still
            // say which days held focus.
            for record in engine.archive.records where record.workType.countsAsFocus && record.workSeconds > 0 {
                focusByDay[calendar.startOfDay(for: record.start), default: 0] += record.workSeconds
            }
        }
        let sessionCount = Set(engine.archive.records.filter { $0.workType.countsAsFocus }.map(\.threadID)).count
        let focused = focusByDay.values.reduce(0, +)

        var byMonth: [Date: TimeInterval] = [:]
        for (day, seconds) in focusByDay where seconds > 0 {
            if let start = calendar.dateInterval(of: .month, for: day)?.start {
                byMonth[start, default: 0] += seconds
            }
        }
        let bestMonth = byMonth.max { $0.value < $1.value }.map { (start: $0.key, focused: $0.value) }

        var longest = 0, run = 0
        var previous: Date?
        for day in focusByDay.keys.sorted() where (focusByDay[day] ?? 0) >= FocusConstants.streakMinimum {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        var byCategory: [WorkType: TimeInterval] = [:]
        for record in engine.archive.records where record.workType.countsAsFocus {
            byCategory[record.workType, default: 0] += record.workSeconds
        }
        let categoryTotal = byCategory.values.reduce(0, +)
        var categories: [WorkTypeShare] = []
        for (type, seconds) in byCategory where seconds > 0 && categoryTotal > 0 {
            categories.append(WorkTypeShare(workType: type, seconds: seconds, share: seconds / categoryTotal))
        }
        categories.sort { $0.seconds > $1.seconds }

        var appTotals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        if let usage {
            let stats = DashboardStats(sessions: engine.archive, usage: usage,
                                       usageSnapshot: effectiveUsageSnapshot,
                                       calendar: calendar, now: now)
            for day in historyDays {
                for app in stats.rankedApps(for: day.date) {
                    let existing = appTotals[app.bundleID]
                    appTotals[app.bundleID] = (app.appName, (existing?.total ?? 0) + app.total,
                                               max(existing?.longest ?? 0, app.longest))
                }
            }
        }
        var appSum: TimeInterval = 0
        for value in appTotals.values { appSum += value.total }
        var apps: [AppRank] = []
        for (key, value) in appTotals {
            let share: Double = appSum > 0 ? value.total / appSum : 0
            apps.append(AppRank(bundleID: key, appName: value.name, total: value.total,
                                share: share, longest: value.longest))
        }
        apps.sort { (a: AppRank, b: AppRank) -> Bool in a.total > b.total }

        return HistoryArchiveFacts(firstDay: focusByDay.keys.min().map { min($0, trackedByDay.keys.min() ?? $0) },
                                   dayCount: historyDays.count, sessionCount: sessionCount, focused: focused,
                                   bestMonth: bestMonth, longestStreak: longest, categories: categories,
                                   apps: apps, focusByDay: focusByDay, trackedByDay: trackedByDay)
    }
}
