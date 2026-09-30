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
    /// Every record folded into this result. A break lists as its records'
    /// rows, so the journal finds it by these rather than by its thread.
    var recordIDs: [UUID] = []
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
}

extension SessionStore {
    /// Sessions and breaks holding every word of the query, newest first.
    /// A session is known by its name and any name it had before a rename,
    /// its category, its notes in full, the app it began in and the apps used
    /// that day, its date and time of day, whether the app started it, and
    /// what the Mac ran on. A break is known by the name it was given, where
    /// you were, and by its date and time. The app and category menus narrow
    /// the same list; a break joins it only through words or the Break
    /// category, since a day's apps say nothing about a break.
    func historySearchHits(limit: Int = 200) -> [HistorySearchHit] {
        let calendar = Calendar.current
        let filter = historyFilter
        let words = SearchWords.words(in: filter.query)
        guard !words.isEmpty || filter.appBundleID != nil || filter.workType != nil else { return [] }
        let formats = ["EEEE d MMMM yyyy", "d/M/yyyy", "h:mm a", "HH:mm"].map { DateFormats.australian($0) }
        let stable = DateFormatter()
        stable.locale = Locale(identifier: "en_US_POSIX")
        stable.dateFormat = "yyyy-MM-dd"
        let daysByDate = Dictionary(uniqueKeysWithValues: historyDays.map { (calendar.startOfDay(for: $0.date), $0) })
        let today = calendar.startOfDay(for: now())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let formerNames = formerSessionNames()

        // Stretches of one session on one day are one result, as they are
        // one card in the story, and are searched as one: a name in one
        // stretch and a word in another's note still find the session.
        struct ThreadDay: Hashable { let thread: UUID; let day: Date }
        var groups: [[SessionRecord]] = []
        var groupIndex: [ThreadDay: Int] = [:]
        for record in engine.archive.records.sorted(by: { $0.start > $1.start }) {
            if let type = filter.workType, record.workType != type { continue }
            let key = ThreadDay(thread: record.threadID, day: calendar.startOfDay(for: record.start))
            if let index = groupIndex[key] {
                groups[index].append(record)
            } else {
                groupIndex[key] = groups.count
                groups.append([record])
            }
        }

        var hits: [HistorySearchHit] = []
        for records in groups {
            let first = records[0]
            let day = calendar.startOfDay(for: first.start)
            let historyDay = daysByDate[day]
            let isBreak = !first.workType.countsAsFocus
            if isBreak, words.isEmpty, filter.workType != first.workType { continue }
            if let app = filter.appBundleID, !(historyDay?.appBundleIDs.contains(app) ?? false) { continue }
            var noteSnippet: String?
            var matchedApps: [String] = []
            if !words.isEmpty {
                let notes = records.compactMap { metadataArchive.metadata(for: $0.id)?.note }
                let apps = isBreak ? [] : (historyDay?.appBundleIDs ?? []).map(historyAppName(for:))
                var text = [first.workType.sessionTitle(named: first.name), first.workType.displayName]
                text += records.map(\.name) + (formerNames[first.threadID] ?? []) + notes + apps
                text += records.compactMap(\.detectedApp).map(historyAppName(for:))
                for record in records {
                    text += formats.map { $0.string(from: record.start) }
                    text += [stable.string(from: record.start), Self.timeOfDay(record.start, calendar: calendar)]
                    if let power = metadataArchive.metadata(for: record.id)?.power, !power.isEmpty,
                       let summary = PowerContextSummary.make(
                           observations: power,
                           interval: DateInterval(start: record.start, end: max(record.start, record.end))) {
                        text += [summary.headline, summary.detail ?? ""]
                    }
                }
                if day == today { text.append("today") }
                if day == yesterday { text.append("yesterday") }
                if records.contains(where: \.isAuto) { text.append("automatic auto-started") }
                guard SearchWords.all(words, in: SearchWords.fold(text.joined(separator: " "))) else { continue }
                func holdsAWord(_ text: String) -> Bool {
                    let folded = SearchWords.fold(text)
                    return words.contains { folded.contains($0) }
                }
                noteSnippet = notes.lazy.flatMap { $0.split(whereSeparator: \.isNewline) }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first(where: holdsAWord)
                matchedApps = apps.filter(holdsAWord)
            }
            hits.append(HistorySearchHit(id: first.id, threadID: first.threadID,
                                         name: first.workType.sessionTitle(named: first.name),
                                         workType: first.workType,
                                         start: records.map(\.start).min() ?? first.start,
                                         end: records.map(\.end).max() ?? first.end,
                                         worked: records.reduce(0) { $0 + $1.workSeconds }, day: day,
                                         noteSnippet: noteSnippet, matchedApps: matchedApps,
                                         recordIDs: records.map(\.id)))
            if hits.count >= limit { break }
        }
        return hits
    }

    /// The names each thread carried before a rename, so a session is still
    /// found by what it used to be called.
    private func formerSessionNames() -> [UUID: [String]] {
        var names: [UUID: [String]] = [:]
        for correction in corrections {
            guard case .rename = correction.correction else { continue }
            names[correction.threadID, default: []].append(correction.originalFields.name)
            names[correction.threadID, default: []] += correction.archiveSnapshot?.fields.map(\.name) ?? []
        }
        return names
    }

    /// Morning, afternoon, evening or night, as someone would say when a
    /// session began.
    static func timeOfDay(_ date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
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
        for day in focusByDay.keys.sorted() where (focusByDay[day] ?? 0) >= engine.store.streakMinimum {
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
        let categories = WorkTypeShare.shares(from: byCategory)

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
