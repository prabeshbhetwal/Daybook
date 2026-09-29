import Foundation

/// History is one journal, newest first, back to the first recorded day.
/// These pin its shape: what gets a row, what collapses into a quiet line,
/// what the headers total, and how ↑/↓ walk it.
enum HistoryJournalChecks {
    static let tests: [(String, () -> [String])] = [
        ("The journal runs newest first to the first recorded day and no further", newestFirst),
        ("Month headers total their own days once", monthTotals),
        ("A day at the Mac with no session reads as app use only", appUseOnly),
        ("A day with only a recorded break keeps its own row", breakOnlyDay),
        ("With nothing recorded the journal is this month and today", emptyArchive),
        ("A new month opens with its own header at midnight on the 1st", monthBoundary),
        ("A daylight-saving month keeps every day once", daylightSaving),
        ("Search narrows the journal to matching sessions and totals them", searchNarrows),
        ("Today's live figures reach the cached journal and its month", liveToday),
        ("Arrow keys step through months, days and sessions in reading order", keyboardSteps),
        ("Jump to date selects a listed day, or the month of a quiet one", jumpSelects),
        ("The twelve-month chart stops at the first recorded month", recentMonthsFloor),
        ("A ticking clock does not rebuild the journal", journalIsCached)
    ]

    // MARK: - Fixtures

    /// Sydney, so the daylight-saving check meets a real transition.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        calendar.locale = Locale(identifier: "en_AU")
        return calendar
    }()

    static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func row(_ month: Int, _ day: Int, focused: TimeInterval = 0, tracked: TimeInterval = 0,
                    sessions: Int = 0, types: Set<WorkType> = []) -> HistoryDay {
        HistoryDay(date: date(month, day), tracked: tracked, focused: focused, sessions: sessions,
                   appBundleIDs: [], workTypes: types)
    }

    /// Two September days and two August ones, with gaps between.
    static let archive: [HistoryDay] = [
        row(9, 28, focused: 3_600, tracked: 4_000, sessions: 2, types: [.deepWork]),
        row(9, 22, focused: 1_800, tracked: 2_000, sessions: 1, types: [.admin]),
        row(8, 30, tracked: 600),
        row(8, 29, focused: 900, tracked: 900, sessions: 1, types: [.learning])
    ]

    static func describe(_ entry: JournalEntry) -> String {
        switch entry {
        case .month(let month): return "month \(calendar.component(.month, from: month.start))"
        case .day(let day):
            return "day \(calendar.component(.month, from: day.date))/\(calendar.component(.day, from: day.date))"
        case .quiet(let quiet):
            return "quiet \(calendar.component(.day, from: quiet.first))-\(calendar.component(.day, from: quiet.last))"
        }
    }

    static func months(_ entries: [JournalEntry]) -> [JournalMonth] {
        entries.compactMap { if case .month(let month) = $0 { return month }; return nil }
    }

    static func days(_ entries: [JournalEntry]) -> [JournalDay] {
        entries.compactMap { if case .day(let day) = $0 { return day }; return nil }
    }

    // MARK: - Shape

    private static func newestFirst() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let expected = ["month 9", "day 9/29", "day 9/28", "quiet 23-27", "day 9/22", "quiet 1-21",
                        "month 8", "quiet 31-31", "day 8/30", "day 8/29"]
        let got = entries.map(describe)
        return got == expected ? [] : ["journal read \(got), expected \(expected)"]
    }

    private static func monthTotals() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        var failures: [String] = []
        let found = months(entries)
        guard found.count == 2 else { return ["expected two months, found \(found.count)"] }
        let september = found[0], august = found[1]
        if september.focused != 5_400 || september.focusedDays != 2 || september.averagePerFocusedDay != 2_700 {
            failures.append("September totalled \(september.focused)s on \(september.focusedDays) days")
        }
        if september.tracked != 6_000 { failures.append("September app use was \(september.tracked)s") }
        if september.dailyFocus.count != 30 || september.dailyFocus[27] != 3_600 {
            failures.append("September's bars lost the 28th or a day: \(september.dailyFocus.count) slots")
        }
        if august.focused != 900 || august.tracked != 1_500 || august.focusedDays != 1 {
            failures.append("August totalled \(august.focused)s focus and \(august.tracked)s app use")
        }
        return failures
    }

    private static func appUseOnly() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let byDay = Dictionary(uniqueKeysWithValues: days(entries).map { ($0.date, $0) })
        var failures: [String] = []
        if byDay[date(8, 30)]?.isAppUseOnly != true { failures.append("30 Aug did not read as app use only") }
        if byDay[date(9, 28)]?.isAppUseOnly != false { failures.append("28 Sep read as app use only") }
        return failures
    }

    private static func breakOnlyDay() -> [String] {
        let rest = row(9, 25, types: [.breakTime])
        let entries = HistoryJournalBuilder.entries(days: archive + [rest], today: date(9, 29), calendar: calendar)
        let got = entries.map(describe)
        return got.contains("day 9/25") && got.contains("quiet 26-27") && got.contains("quiet 23-24")
            ? [] : ["a break-only day vanished into a quiet run: \(got)"]
    }

    private static func emptyArchive() -> [String] {
        let got = HistoryJournalBuilder.entries(days: [], today: date(9, 29), calendar: calendar).map(describe)
        return got == ["month 9", "day 9/29"] ? [] : ["an empty archive read \(got)"]
    }

    private static func monthBoundary() -> [String] {
        let got = HistoryJournalBuilder.entries(days: [row(9, 30, focused: 600, sessions: 1)],
                                                today: date(10, 1), calendar: calendar).map(describe)
        let expected = ["month 10", "day 10/1", "month 9", "day 9/30"]
        return got == expected ? [] : ["the 1st read \(got), expected \(expected)"]
    }

    private static func daylightSaving() -> [String] {
        // Sydney moves its clocks forward at 2 am on Sunday 4 October 2026.
        let rows = [row(10, 5, focused: 600, sessions: 1), row(10, 3, focused: 600, sessions: 1)]
        let entries = HistoryJournalBuilder.entries(days: rows, today: date(10, 6), calendar: calendar)
        var failures: [String] = []
        let expected = ["month 10", "day 10/6", "day 10/5", "quiet 4-4", "day 10/3"]
        if entries.map(describe) != expected {
            failures.append("October read \(entries.map(describe)), expected \(expected)")
        }
        if let october = months(entries).first {
            if october.dailyFocus.count != 31 { failures.append("October has \(october.dailyFocus.count) bars") }
            if october.dailyFocus[2] != 600 || october.dailyFocus[4] != 600 {
                failures.append("October's bars lost the 3rd or the 5th across the clock change")
            }
        }
        return failures
    }

    private static func searchNarrows() -> [String] {
        let a = UUID(), b = UUID(), c = UUID()
        func hit(_ thread: UUID, _ month: Int, _ day: Int, _ worked: TimeInterval) -> HistorySearchHit {
            let start = date(month, day).addingTimeInterval(9 * 3_600)
            return HistorySearchHit(id: UUID(), threadID: thread, name: "Parser", workType: .deepWork,
                                    start: start, end: start.addingTimeInterval(worked), worked: worked,
                                    day: date(month, day), noteSnippet: nil, matchedApps: [])
        }
        let hits = [hit(a, 9, 28, 1_200), hit(b, 9, 28, 600), hit(c, 8, 29, 900)]
        let entries = HistoryJournalBuilder.entries(matching: hits, calendar: calendar)
        var failures: [String] = []
        let expected = ["month 9", "day 9/28", "month 8", "day 8/29"]
        if entries.map(describe) != expected {
            failures.append("search read \(entries.map(describe)), expected \(expected)")
        }
        if let september = months(entries).first, september.focused != 1_800 || september.focusedDays != 1 {
            failures.append("September's header totalled \(september.focused)s, not the 1800s matched")
        }
        if let day = days(entries).first, day.threads != [a, b] || day.sessions != 2 || day.focused != 1_800 {
            failures.append("28 Sep was not narrowed to its two matches")
        }
        return failures
    }

    private static func liveToday() -> [String] {
        let cached = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let live = row(9, 29, focused: 1_200, tracked: 300, sessions: 1)
        let patched = HistoryJournalBuilder.patching(cached, today: live, calendar: calendar)
        var failures: [String] = []
        if let today = days(patched).first, today.focused != 1_200 || today.sessions != 1 {
            failures.append("today's row kept its cached figures")
        }
        if let september = months(patched).first,
           september.focused != 6_600 || september.tracked != 6_300 || september.focusedDays != 3 {
            failures.append("September did not take today's live figures: \(september.focused)s")
        }
        if patched.map(describe) != cached.map(describe) { failures.append("patching changed the rows") }
        return failures
    }

    private static func keyboardSteps() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let a = UUID(), b = UUID()
        let threads: (Date) -> [UUID] = { $0 == date(9, 28) ? [a, b] : [] }
        let down: [HistorySelection] = [
            .day(date(9, 29)), .day(date(9, 28)), .session(thread: a, day: date(9, 28)),
            .session(thread: b, day: date(9, 28)), .day(date(9, 22)), .month(date(8, 1)),
            .day(date(8, 30)), .day(date(8, 29)), .day(date(8, 29))
        ]
        var failures: [String] = []
        var current = HistorySelection.month(date(9, 1))
        for expected in down {
            current = HistoryJournalBuilder.step(from: current, by: 1, entries: entries, threads: threads)
            if current != expected { failures.append("↓ reached \(current), expected \(expected)"); break }
        }
        let up: [HistorySelection] = [
            .session(thread: b, day: date(9, 28)), .session(thread: a, day: date(9, 28)),
            .day(date(9, 28)), .day(date(9, 29)), .month(date(9, 1)), .month(date(9, 1))
        ]
        current = .day(date(9, 22))
        for expected in up {
            current = HistoryJournalBuilder.step(from: current, by: -1, entries: entries, threads: threads)
            if current != expected { failures.append("↑ reached \(current), expected \(expected)"); break }
        }
        return failures
    }

    private static func jumpSelects() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        var failures: [String] = []
        if HistoryJournalBuilder.selection(forJump: date(9, 28), in: entries, calendar: calendar) != .day(date(9, 28)) {
            failures.append("jumping to a listed day did not select it")
        }
        if HistoryJournalBuilder.selection(forJump: date(9, 25), in: entries, calendar: calendar) != .month(date(9, 1)) {
            failures.append("jumping to a quiet day did not select its month")
        }
        let session = HistorySelection.session(thread: UUID(), day: date(9, 28))
        if HistoryJournalBuilder.anchorID(for: session, in: entries, calendar: calendar)
            != JournalEntry.dayID(date(9, 28)) {
            failures.append("a session did not scroll to its day's header")
        }
        if HistoryJournalBuilder.anchorID(for: .month(date(8, 1)), in: entries, calendar: calendar)
            != JournalEntry.monthID(date(8, 1)) {
            failures.append("a month did not scroll to its header")
        }
        if HistoryJournalBuilder.anchorID(for: .day(date(9, 25)), in: entries, calendar: calendar) != nil {
            failures.append("a quiet day claimed a row of its own")
        }
        return failures
    }

    private static func recentMonthsFloor() -> [String] {
        let focus = [date(8, 29): 900.0, date(9, 28): 3_600.0]
        var failures: [String] = []
        let short = HistoryJournalBuilder.recentMonths(endingAt: date(9, 15), focusByDay: focus,
                                                       firstDay: date(8, 29), calendar: calendar)
        if short.map(\.start) != [date(8, 1), date(9, 1)] || short.map(\.focused) != [900, 3_600] {
            failures.append("a two-month record drew \(short.map(\.start))")
        }
        let long = HistoryJournalBuilder.recentMonths(endingAt: date(9, 15), focusByDay: focus,
                                                      firstDay: date(1, 1, year: 2025), calendar: calendar)
        if long.count != 12 || long.first?.start != date(10, 1, year: 2025) || long.last?.start != date(9, 1) {
            failures.append("a long record drew \(long.count) months from \(String(describing: long.first?.start))")
        }
        return failures
    }

    // MARK: - Store

    private static func journalIsCached() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            var failures: [String] = []
            let first = store.historyJournal()
            guard case .month = first.first else { return ["the journal did not open on a month"] }
            let before = store.journalComputeCount
            for _ in 0..<5 { _ = store.historyJournal() }
            if store.journalComputeCount != before {
                failures.append("five reads of an unchanged archive rebuilt the journal "
                                + "\(store.journalComputeCount - before) times")
            }
            guard let record = store.engine.archive.records.first else {
                return failures + ["the fixture has no session to annotate"]
            }
            store.setNoteDraft("journal cache check", for: record.id)
            _ = store.saveNote(for: record.id)
            _ = store.historyJournal()
            if store.journalComputeCount != before + 1 {
                failures.append("a saved note did not rebuild the journal once")
            }
            return failures
        }
    }
}
