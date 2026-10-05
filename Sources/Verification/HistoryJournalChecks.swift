import Foundation

/// History is one journal, newest first, back to the first recorded day.
/// These pin its shape: what gets a row, what collapses into a quiet line,
/// what the headers total, and how ↑/↓ walk it.
enum HistoryJournalChecks {
    static let tests: [(String, () -> [String])] = [
        ("Month headers total their own days once", monthTotals),
        ("Search narrows the journal to matching sessions and breaks, and totals only focus", searchNarrows),
        ("A ticking clock does not recompute a search", searchIsCached),
        ("The search summary says its figures once", journalWording),
        ("A session row speaks its time, name, category and length as one element", sessionSpeech),
        ("A day of one session shows its figure on the row, not the header too; a break never hides app use",
         dayTotalSaidOnce),
        ("The best two hours are said once, with where they fell", bestHoursSaidOnce),
        ("The period rail carries recorded app use in one line", monthRailAppUse),
        ("The tree and each rail scope render with their evidence", journalRenders)
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
        }
    }

    static func months(_ entries: [JournalEntry]) -> [JournalMonth] {
        entries.compactMap { if case .month(let month) = $0 { return month }; return nil }
    }

    static func days(_ entries: [JournalEntry]) -> [JournalDay] {
        entries.compactMap { if case .day(let day) = $0 { return day }; return nil }
    }

    // MARK: - Shape

    private static func monthTotals() -> [String] {
        var failures: [String] = []
        let september = HistoryJournalBuilder.month(starting: date(9, 1), days: archive, calendar: calendar)
        let august = HistoryJournalBuilder.month(starting: date(8, 1), days: archive, calendar: calendar)
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
        // A break that matched lists as its own row under its day, but it is
        // not focus: it adds no session, no focused day and no focus figure.
        let restIDs = (0..<3).map { _ in UUID() }
        func rest(_ index: Int, _ month: Int, _ day: Int, _ length: TimeInterval) -> HistorySearchHit {
            let start = date(month, day).addingTimeInterval(13 * 3_600)
            return HistorySearchHit(id: restIDs[index], threadID: UUID(), name: "Café", workType: .breakTime,
                                    start: start, end: start.addingTimeInterval(length), worked: length,
                                    day: date(month, day), noteSnippet: nil, matchedApps: [],
                                    recordIDs: [restIDs[index]])
        }
        let withBreaks = HistoryJournalBuilder.entries(
            matching: [rest(0, 9, 29, 1_500), hits[0], rest(1, 9, 28, 900), hits[1], hits[2], rest(2, 7, 14, 600)],
            calendar: calendar)
        let expectedWithBreaks = ["month 9", "day 9/29", "day 9/28", "month 8", "day 8/29", "month 7", "day 7/14"]
        if withBreaks.map(describe) != expectedWithBreaks {
            failures.append("break hits read \(withBreaks.map(describe)), expected \(expectedWithBreaks)")
        }
        if let september = months(withBreaks).first, september.focused != 1_800 || september.focusedDays != 1 {
            failures.append("a break hit changed September's figures: \(september.focused)s over \(september.focusedDays) days")
        }
        let breakDays = days(withBreaks)
        if let breakOnly = breakDays.first,
           breakOnly.sessions != 0 || breakOnly.focused != 0 || breakOnly.breaks != 1
            || breakOnly.threads != [restIDs[0]] {
            failures.append("29 Sep did not list its one matched break by record")
        }
        if breakDays.count > 1, breakDays[1].threads != [a, b, restIDs[1]] || breakDays[1].sessions != 2 {
            failures.append("28 Sep did not list its two sessions and its break")
        }
        let summary = HistoryTree.matchSummary(withBreaks)
        if summary != "3 sessions match · \(Tokens.duration(2_700)) of focus · 3 breaks" {
            failures.append("search summary with breaks read \"\(summary)\"")
        }
        let onlyBreaks = HistoryTree.matchSummary(
            HistoryJournalBuilder.entries(matching: [rest(0, 9, 29, 1_500)], calendar: calendar))
        if onlyBreaks != "1 break matches" {
            failures.append("a search matching one break summed \"\(onlyBreaks)\"")
        }
        // The field counts; the headline adds up the focus. Each says it once.
        let breakOnly = HistoryJournalBuilder.entries(matching: [rest(0, 9, 29, 1_500)], calendar: calendar)
        let counts = [HistoryTree.matchCount(withBreaks), HistoryTree.matchCount(breakOnly), HistoryTree.matchCount([])]
        if counts != ["3 sessions · 3 breaks", "1 break", "No matches"] {
            failures.append("the field's counts read \(counts)")
        }
        let focusedDays = days(withBreaks).filter { $0.focused > 0 }.count
        let headline = HistorySearchText.searchSentence(filter: HistoryFilter(query: "parser"), appName: nil,
                                                        entries: withBreaks)
        let breaksHeadline = HistorySearchText.searchSentence(filter: HistoryFilter(query: "café"), appName: nil,
                                                              entries: breakOnly)
        if headline.sentence != "You focused \(Tokens.duration(2_700)) on “parser” across "
            + (focusedDays == 1 ? "1 day." : "\(focusedDays) days.")
            || breaksHeadline.sentence != "1 break matches." || breaksHeadline.highlight != nil {
            failures.append("the search headline read \"\(headline.sentence)\" and \"\(breaksHeadline.sentence)\"")
        }
        return failures
    }

    // MARK: - Store

    private static func searchIsCached() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            var failures: [String] = []
            if !store.historyJournal().isEmpty { failures.append("an unsearched History listed search results") }
            guard let record = store.engine.archive.records.first else {
                return failures + ["the fixture has no session to search for"]
            }
            // A search walks every record; five reads under one filter walk them once.
            store.historyFilter.workType = record.workType
            let searched = store.searchJournalComputeCount
            for _ in 0..<5 { _ = store.historyJournal() }
            if store.searchJournalComputeCount != searched + 1 {
                failures.append("five reads under one search computed its matches "
                                + "\(store.searchJournalComputeCount - searched) times")
            }
            return failures
        }
    }

    // MARK: - Wording

    private static func journalWording() -> [String] {
        var failures: [String] = []
        let month = JournalMonth(start: date(9, 1), focused: 5_400, tracked: 6_000, focusedDays: 2,
                                 dailyFocus: Array(repeating: 0, count: 30))
        let entries: [JournalEntry] = [
            .month(month),
            .day(JournalDay(date: date(9, 28), focused: 1_800, tracked: 0, sessions: 2, threads: [])),
            .day(JournalDay(date: date(9, 22), focused: 600, tracked: 0, sessions: 1, threads: []))
        ]
        let summary = HistoryTree.matchSummary(entries)
        if summary != "3 sessions match · \(Tokens.duration(2_400)) of focus" {
            failures.append("the search summary read \"\(summary)\"")
        }
        return failures
    }

    private static func sessionSpeech() -> [String] {
        let start = date(9, 28).addingTimeInterval(8.5 * 3_600)
        let named = DaySession(id: UUID(), threadID: UUID(), name: "Refactor", workType: .deepWork,
                               start: start, end: start.addingTimeInterval(11_100), worked: 7_500,
                               stretches: 1, spans: [], isRunning: false)
        var failures: [String] = []
        let label = HistorySessionRow.spokenLabel(named)
        for part in [Tokens.timeRange(named.start, named.end), "Refactor",
                     WorkType.deepWork.displayName, Tokens.spent(7_500)] where !label.contains(part) {
            failures.append("the row did not say \"\(part)\": \(label)")
        }
        if label.contains(Tokens.duration(7_500)) { failures.append("the row spoke a compact duration: \(label)") }
        let unnamed = DaySession(id: UUID(), threadID: UUID(), name: "", workType: .deepWork,
                                 start: start, end: start.addingTimeInterval(600), worked: 600,
                                 stretches: 1, spans: [], isRunning: true)
        let quiet = HistorySessionRow.spokenLabel(unnamed)
        if quiet.components(separatedBy: WorkType.deepWork.displayName).count != 2 {
            failures.append("an unnamed session said its category twice: \(quiet)")
        }
        if !quiet.contains("in progress") { failures.append("a running session did not say so: \(quiet)") }
        if HistorySessionRow.detail(apps: ["Xcode", "Terminal", "Safari", "Notes"], note: "fixed it")
            != "Xcode, Terminal, Safari · “fixed it”" {
            failures.append("the second line lost its three apps or the note")
        }
        return failures
    }

    private static func dayTotalSaidOnce() -> [String] {
        let start = date(9, 28).addingTimeInterval(9 * 3_600)
        func session(_ worked: TimeInterval, running: Bool = false) -> DayEntry {
            .session(DaySession(id: UUID(), threadID: UUID(), name: "Parser", workType: .deepWork,
                                start: start, end: start.addingTimeInterval(worked), worked: worked,
                                stretches: 1, spans: [], isRunning: running))
        }
        let rest = DayEntry.rest(RestEntry(id: UUID(), name: "Lunch", start: start.addingTimeInterval(4_000),
                                           end: start.addingTimeInterval(4_600)))
        func day(_ focused: TimeInterval, tracked: TimeInterval = 0) -> JournalDay {
            JournalDay(date: date(9, 28), focused: focused, tracked: tracked, sessions: 1)
        }
        var failures: [String] = []
        if HistoryDayHeader.showsTotal(day: day(3_600), rows: [session(3_600)]) {
            failures.append("a one-session day repeated its session's figure in the header")
        }
        if !HistoryDayHeader.showsTotal(day: day(5_400), rows: [session(3_600), session(1_800)]) {
            failures.append("a two-session day lost its total")
        }
        if !HistoryDayHeader.showsTotal(day: day(3_600), rows: [session(3_600), rest]) {
            failures.append("a session with a break beside it lost the day's total")
        }
        if !HistoryDayHeader.showsTotal(day: day(3_600), rows: [session(3_600, running: true)]) {
            failures.append("a running session's row says \"in progress\", yet the header hid the day's figure")
        }
        if HistoryDayHeader.showsTotal(day: day(0, tracked: 600), rows: []) {
            failures.append("an app-use-only day showed a focus figure")
        }
        return failures
    }

    private static func bestHoursSaidOnce() -> [String] {
        let note = HistoryHours.note(seconds: 12_000, phrase: "on Tuesdays")
        var failures: [String] = []
        if note != "\(Tokens.duration(12_000)) of focus fell here, most of it on Tuesdays." {
            failures.append("the best-hours note read \"\(note)\"")
        }
        if HistoryHours.span(from: 9) != "9 am – 11 am" || HistoryHours.label(0) != "12 am"
            || HistoryHours.label(13) != "1 pm" {
            failures.append("clock hours were not said as 9 am, 12 am and 1 pm")
        }
        return failures
    }

    private static func monthRailAppUse() -> [String] {
        let line = HistoryPeriodRail.appUseLine(tracked: 59_100)
        return line == "\(Tokens.duration(59_100)) recorded app use"
            ? [] : ["the month rail's app use read \"\(line)\""]
    }

    // MARK: - Render

    private static func journalRenders() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            func require(_ label: String, _ frame: StoryRenderedFrame, _ evidence: StoryRenderEvidence) {
                if !frame.evidence.contains(evidence) {
                    failures.append("\(label) did not render \(evidence.rawValue): \(frame.evidence.map(\.rawValue).sorted())")
                }
            }
            let dense = FixtureFactory.insightsStore(withEvidence: true)
            dense.refreshReview()
            let denseSettings = SettingsModel(store: dense.engine.store, isTrackingEnabled: true,
                                              onChange: {}, onTrackingChanged: { _ in })
            let navigation = MainWindowModel(store: dense)
            navigation.open(tab: .review)
            let monthFrame = StoryWorkspaceChecks.renderFrame(
                HistoryWorkspace(store: dense, navigation: navigation, settings: denseSettings, scrolls: false), width: 1_160, height: 1_000)
            require("History on its month", monthFrame, .historyTree)
            require("History on its month", monthFrame, .historyPeriodRail)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1,
                                                  to: Calendar.current.startOfDay(for: dense.now()))!
            navigation.openHistory(day: yesterday)
            let dayFrame = StoryWorkspaceChecks.renderFrame(
                HistoryWorkspace(store: dense, navigation: navigation, settings: denseSettings, scrolls: false), width: 1_160, height: 1_600)
            require("History on a day", dayFrame, .historyDayRail)
            // The open day is the dashboard's own day story, not a list of rows.
            require("History on a day", dayFrame, .dayStory)
            if let thread = dense.journalThreads(on: yesterday, only: nil).first {
                navigation.selectHistory(session: thread, on: yesterday)
                require("History on a session", StoryWorkspaceChecks.renderFrame(
                    HistoryWorkspace(store: dense, navigation: navigation, settings: denseSettings, scrolls: false), width: 1_160, height: 1_000),
                    .historySessionRail)
            } else {
                failures.append("the dense fixture's yesterday has no session")
            }
            FixtureFactory.cleanUp()
            let sparse = FixtureFactory.store(for: .firstRun, accurateUsage: true)
            sparse.refreshReview()
            let fresh = MainWindowModel(store: sparse)
            fresh.open(tab: .review)
            require("An empty History", StoryWorkspaceChecks.renderFrame(
                HistoryWorkspace(store: sparse, navigation: fresh, settings: SettingsModel(store: sparse.engine.store, isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in }), scrolls: false), width: 1_160, height: 800),
                .historyEmpty)
            FixtureFactory.cleanUp()
            return failures
        }
    }
}
