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
    /// Names of apps used in the session that held a query word.
    let matchedApps: [String]
    /// Every record folded into this result. A break lists as its records'
    /// rows, so the journal finds it by these rather than by its thread.
    var recordIDs: [UUID] = []
}

extension SessionStore {
    /// Sessions and breaks holding every word of the query, newest first.
    /// A session is known by its name and any name it had before a rename,
    /// its category, its notes in full, the app it began in and the apps in
    /// front during it, its date and time of day, whether the app started it,
    /// and what the Mac ran on. A break is known by the name it was given,
    /// where you were, and by its date and time. The app and category menus
    /// narrow the same list; a break joins it only through words or the Break
    /// category. An app counts for a session only when it was in front for
    /// `HistoryAppLens.minimumUse` inside the session itself: matched by the
    /// day, picking an app listed every session of every day it was opened.
    func historySearchHits(limit: Int = 200) -> [HistorySearchHit] {
        historySearchHits(matching: historyFilter, limit: limit)
    }

    /// The same list for any filter, so a lookup can search without touching
    /// the one History is showing. An empty filter finds nothing, as an empty
    /// search field does, unless `listingAll` asks for every session.
    func historySearchHits(matching filter: HistoryFilter, limit: Int = 200,
                           listingAll: Bool = false) -> [HistorySearchHit] {
        let calendar = periodCalendar
        let words = SearchWords.words(in: filter.query)
        guard !filter.noOverlap else { return [] }
        guard listingAll || !words.isEmpty || filter.appBundleID != nil || filter.workType != nil
                || filter.hasPhrases else { return [] }
        let formats = ["EEEE d MMMM yyyy", "d/M/yyyy", "h:mm a", "HH:mm"].map { DateFormats.australian($0) }
        let stable = DateFormatter()
        stable.locale = Locale(identifier: "en_US_POSIX")
        stable.dateFormat = "yyyy-MM-dd"
        let usage = historySortedUsage()
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
            let isBreak = !first.workType.countsAsFocus
            guard filter.holds(day: day, in: calendar) else { continue }
            if filter.minLength != nil || filter.maxLength != nil {
                let worked = records.reduce(0) { $0 + $1.workSeconds }
                if isBreak || worked < filter.minLength ?? 0 || worked > filter.maxLength ?? .infinity { continue }
            }
            if isBreak, words.isEmpty, filter.workType != first.workType { continue }
            let used = filter.appBundleID != nil || (!words.isEmpty && !isBreak)
                ? usage.uniqueUse(within: records.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) })
                    .mapValues { $0.total }.filter { $0.value >= HistoryAppLens.minimumUse }
                : [:]
            if let app = filter.appBundleID, used[app] == nil { continue }
            var noteSnippet: String?
            var matchedApps: [String] = []
            if !words.isEmpty {
                let notes = records.compactMap { metadataArchive.metadata(for: $0.id)?.note }
                let apps = isBreak ? [] : used.keys.sorted().map(historyAppName(for:))
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
}
