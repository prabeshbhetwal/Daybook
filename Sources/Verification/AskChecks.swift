import Foundation

/// Ask Daybook's ranges and wording: a range names the same period History
/// does, and every answer reads the same way whatever lookup produced it.
enum AskChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Each Ask range spans the period History draws, in the period calendar", rangesFollowPeriodCalendar),
        ("Ask range names round-trip and are distinct", rangeNamesRoundTrip),
        ("Every Ask answer says plainly when nothing was found", nothingFoundIsSaid),
        ("Ask answers print durations as the rest of the app does", figuresAreDurationText),
        ("An Ask answer is cut to the byte cap at a line or clause boundary", outputStaysUnderCap),
        ("The best-hours window reads as a 12-hour range", windowLabels),
        ("Ask's focus totals are History's own figures for the same period", focusTotalsMatchHistory),
        ("Ask counts the session still running today", liveSessionCountsToday),
        ("Words narrow Ask's totals to the sessions that match", wordsNarrowTotals),
        ("Ask lists matching sessions inside the range only", findSessionsStaysInRange),
        ("Ask names the two-hour window and the weekday it sits on", bestHoursNamesWindow),
        ("Ask finds an app by a loose name and says so when none matches", appTimeResolvesLooseNames),
        ("Ask's all-time figures start at the first record", allTimeStartsAtRecord),
        ("Ask lookups write nothing and leave History's filter alone", lookupsOnlyRead),
    ]

    private static func rangesFollowPeriodCalendar() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current.forPeriods
        func midnight(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2023, month: month, day: day))!
        }
        let firstDay = calendar.date(from: DateComponents(year: 2023, month: 9, day: 2, hour: 14))!
        let expected: [(AskRange, Date, Date)] = [
            (.today, midnight(11, 15), midnight(11, 16)),
            (.yesterday, midnight(11, 14), midnight(11, 15)),
            (.thisWeek, midnight(11, 13), midnight(11, 20)),
            (.lastWeek, midnight(11, 6), midnight(11, 13)),
            (.thisMonth, midnight(11, 1), midnight(12, 1)),
            (.lastMonth, midnight(10, 1), midnight(11, 1)),
            (.last30Days, midnight(10, 17), midnight(11, 16)),
            (.allTime, midnight(9, 2), midnight(11, 16)),
        ]
        for (range, start, end) in expected {
            let interval = range.interval(now: SelfTest.base, firstDay: firstDay, calendar: calendar)
            expect(interval.start == start && interval.end == end,
                   "\(range.rawValue) spans \(interval.start) to \(interval.end), not \(start) to \(end)", &problems)
        }
        return problems
    }

    private static func rangeNamesRoundTrip() -> [String] {
        var problems: [String] = []
        for range in AskRange.allCases {
            expect(AskRange(rawValue: range.rawValue) == range,
                   "\(range.rawValue) does not come back from its own name", &problems)
        }
        expect(Set(AskRange.allCases.map(\.rawValue)).count == AskRange.allCases.count,
               "two ranges share a name", &problems)
        return problems
    }

    private static func nothingFoundIsSaid() -> [String] {
        var problems: [String] = []
        let range = AskRange.thisWeek
        let cases: [(String, String, String)] = [
            ("focus totals", AskFacts.focusTotals(range, words: nil, focused: 0, sessions: 0, focusedDays: 0,
                                                  best: nil, parts: nil),
             "No focus recorded this week."),
            ("focus totals for words", AskFacts.focusTotals(range, words: "thesis", focused: 0, sessions: 0,
                                                            focusedDays: 0, best: nil, parts: nil),
             "No sessions match “thesis” this week."),
            ("best hours", AskFacts.bestHours(range, span: "This week", window: nil, strongest: nil),
             "Not enough focus this week to tell; it needs at least 30m."),
            ("sessions", AskFacts.sessions(range, words: "thesis", hits: []),
             "No sessions match “thesis” this week."),
            ("app time", AskFacts.appTime(range, app: (query: "Figma", name: nil, total: 0, sessions: 0), top: []),
             "No app called “Figma” was used this week."),
            ("app time, no app", AskFacts.appTime(range, app: nil, top: []),
             "No app use recorded this week."),
        ]
        for (name, got, want) in cases {
            expect(got == want, "\(name) says “\(got)”, not “\(want)”", &problems)
        }
        let allTime = AskFacts.bestHours(.allTime, span: "All time", window: nil, strongest: nil)
        expect(allTime == "Not enough focus in all your history to tell; it needs at least 30m.",
               "best hours over all time says “\(allTime)”", &problems)
        return problems
    }

    private static func figuresAreDurationText() -> [String] {
        var problems: [String] = []
        let got = AskFacts.focusTotals(.thisWeek, words: nil, focused: 24_000, sessions: 5, focusedDays: 4,
                                       best: (unit: "day", label: "Tue 14 Nov", focused: 7_500), parts: nil)
        let want = "This week: 6h 40m focused over 5 sessions on 4 days; best day Tue 14 Nov, 2h 5m."
        expect(got == want, "focus totals say “\(got)”, not “\(want)”", &problems)

        let one = AskFacts.focusTotals(.thisWeek, words: "thesis", focused: 3_600, sessions: 1, focusedDays: 1,
                                       best: nil,
                                       parts: nil)
        expect(one == "Sessions matching “thesis” this week: 1h over 1 session on 1 day.",
               "one session on one day says “\(one)”", &problems)

        let parts = AskFacts.focusTotals(.thisWeek, words: nil, focused: 5_400, sessions: 2, focusedDays: 2,
                                         best: nil,
                                         parts: (name: "day", items: [(label: "Mon 13 Nov", focused: 3_600),
                                                                      (label: "Tue 14 Nov", focused: 1_800)]))
        expect(parts == "This week: 1h 30m focused over 2 sessions on 2 days. By day: Mon 13 Nov 1h, Tue 14 Nov 30m.",
               "the per-day breakdown says “\(parts)”", &problems)

        let hours = AskFacts.bestHours(.thisWeek, span: "This week", window: (startHour: 9, seconds: 7_200),
                                       strongest: "on Tuesdays")
        expect(hours == "This week: most focus 9–11am (2h); strongest on Tuesdays.",
               "best hours say “\(hours)”", &problems)

        let lines = AskFacts.sessions(.thisWeek, words: "thesis",
                                      hits: [(day: "Tue 14 Nov", name: "Thesis", worked: 3_600, note: nil),
                                             (day: "Mon 13 Nov", name: "Thesis", worked: 1_800, note: "outline")])
        expect(lines == "Tue 14 Nov · Thesis · 1h\nMon 13 Nov · Thesis · 30m · note: outline",
               "session lines say “\(lines)”", &problems)

        let long = AskFacts.sessions(.thisWeek, words: "x",
                                     hits: [(day: "Tue 14 Nov", name: "X", worked: 60,
                                             note: String(repeating: "n", count: 120))])
        expect(long.hasSuffix("note: " + String(repeating: "n", count: 80)),
               "a long note is cut to 80 characters", &problems)

        let found = AskFacts.appTime(.thisWeek, app: (query: "saf", name: "Safari", total: 5_400, sessions: 1),
                                     top: [])
        expect(found == "Safari this week: 1h 30m in front; used in 1 session.",
               "app time says “\(found)”", &problems)

        let top = AskFacts.appTime(.thisWeek, app: nil,
                                   top: (1...6).map { (name: "App\($0)", total: 60.0 * Double($0)) })
        expect(top == "Most-used apps this week: App1 1m, App2 2m, App3 3m, App4 4m, App5 5m.",
               "the top apps say “\(top)”", &problems)
        return problems
    }

    private static func outputStaysUnderCap() -> [String] {
        var problems: [String] = []
        let cap = AskFacts.maximumBytes
        let ellipsis = "…".utf8.count

        // Line break: the answer is exactly the first k whole lines, k the
        // most that leave room for the ellipsis, never a partial line.
        let note = String(repeating: "n", count: 80)
        let hits = (0..<200).map { (day: "Tue 14 Nov", name: "Session \($0)", worked: 3_600.0, note: Optional(note)) }
        let lines = (0..<200).map { "Tue 14 Nov · Session \($0) · 1h · note: \(note)" }
        var kept = 0
        while kept < lines.count, lines[...kept].joined(separator: "\n").utf8.count + ellipsis <= cap { kept += 1 }
        let text = AskFacts.sessions(.thisWeek, words: "session", hits: hits)
        expect(text.utf8.count <= cap, "the answer is \(text.utf8.count) bytes", &problems)
        expect(kept > 0 && kept < lines.count, "the fixture no longer needs a cut at a line break", &problems)
        expect(text == lines[..<kept].joined(separator: "\n") + "…",
               "an over-long list is not cut after its \(kept) whole lines: ends “\(text.suffix(40))”", &problems)

        // Clause break: with no line break, the cut lands on the last "; ".
        let days = (0..<100).map { (label: "Day \($0)", focused: 3_600.0) }
        let clause = AskFacts.focusTotals(.thisWeek, words: nil, focused: 24_000, sessions: 5, focusedDays: 4,
                                          best: (unit: "day", label: "Tue 14 Nov", focused: 7_500),
                                          parts: (name: "day", items: days))
        expect(clause == "This week: 6h 40m focused over 5 sessions on 4 days…",
               "an over-long total is not cut at its “; ”: “\(clause)”", &problems)

        // A separator that starts just past the kept text still counts: the
        // first two lines are exactly as long as the cap allows with the ellipsis.
        let fits = String(repeating: "a", count: 10) + "\n" + String(repeating: "b", count: cap - ellipsis - 11)
        let edge = AskFacts.capped(fits + "\n" + String(repeating: "c", count: 100))
        expect(edge == fits + "…" && edge.utf8.count == cap,
               "a cut that lands on a line break loses the line before it: ends “\(edge.suffix(20))”", &problems)

        // No separator at all: cut mid-text, still within the cap.
        let name = String(repeating: "x", count: 1_500)
        let bare = AskFacts.sessions(.thisWeek, words: "x",
                                     hits: [(day: "Tue 14 Nov", name: name, worked: 60, note: nil)])
        let bareLine = "Tue 14 Nov · \(name) · 1m"
        expect(bare == String(decoding: bareLine.utf8.prefix(cap - ellipsis), as: UTF8.self) + "…",
               "a single over-long line is not cut at the cap: \(bare.utf8.count) bytes", &problems)

        expect(AskFacts.capped("short") == "short", "a short answer was changed", &problems)
        let multibyte = AskFacts.capped(String(repeating: "é", count: 2_000))
        expect(multibyte.utf8.count <= AskFacts.maximumBytes, "a multibyte answer is over the cap", &problems)
        return problems
    }

    private static func windowLabels() -> [String] {
        var problems: [String] = []
        for (start, label) in [(9, "9–11am"), (11, "11am–1pm"), (0, "12–2am")] {
            let text = AskFacts.bestHours(.thisWeek, span: "This week",
                                          window: (startHour: start, seconds: 3_600), strongest: nil)
            expect(text.contains(label), "a window starting at \(start) reads “\(text)”, not \(label)", &problems)
        }
        return problems
    }

    // MARK: - Lookups through the store

    /// Wed 15 Nov 2023, 09:13, on a store whose History holds three sessions:
    /// Thesis on Mon 13 Nov 9–10 with the note "chapter two outline", Parser
    /// on Tue 14 Nov 14:00–15:30 with Safari in front 14:00–15:00, and Thesis
    /// on Tue 17 Oct 9–11. No break is recorded.
    private struct Fixture {
        let clock: TestClock
        let calendar: Calendar
        let engine: SessionEngine
        let store: SessionStore
        let defaults: UserDefaults
        let suite: String
        /// Where the session, usage and metadata archives write.
        let directories: [URL]

        func cleanUp() {
            for directory in directories { try? FileManager.default.removeItem(at: directory) }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private static func makeFixture() -> Fixture? {
        let clock = TestClock(SelfTest.base)
        let calendar = Calendar.current.forPeriods
        let directories = (0..<3).map { _ in SelfTest.scratchDirectory() }
        for directory in directories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let suite = "fc-selftest-ask-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        // A moment on the day `back` days before today, in the store's calendar.
        func moment(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: clock.value))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let archive = SessionArchive(directory: directories[0], calendar: calendar, now: { clock.value })
        let thesis = SessionRecord(name: "Thesis", workType: .deepWork, start: moment(2, 9), end: moment(2, 10),
                                   workSeconds: 3_600)
        let records = [
            thesis,
            SessionRecord(name: "Parser", workType: .deepWork, start: moment(1, 14), end: moment(1, 15, 30),
                          workSeconds: 5_400),
            SessionRecord(name: "Thesis", workType: .deepWork, start: moment(29, 9), end: moment(29, 11),
                          workSeconds: 7_200),
        ]
        for record in records where archive.append(record) != nil { return nil }

        let envelope = SelfTest.UsageEnvelopeFixture(
            metadata: AppUsageMetadata(accurateFrom: moment(40, 0)),
            sessions: [AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                       start: moment(1, 14), end: moment(1, 15))])
        guard let data = try? JSONEncoder().encode(envelope),
              (try? data.write(to: directories[1].appendingPathComponent("app-usage.json"), options: .atomic)) != nil
        else { return nil }
        let usage = AppUsageArchive(directory: directories[1], calendar: calendar, now: { clock.value })

        let metadata = SessionMetadataArchive(directory: directories[2])
        guard case .saved = metadata.saveNote("chapter two outline", for: thesis.id) else { return nil }

        let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "com.example.ask", schedulesDwell: false, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.ask", idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, metadataArchive: metadata,
                                 now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.setReviewVisible(true)
        store.refreshReview()
        return Fixture(clock: clock, calendar: calendar, engine: engine, store: store, defaults: defaults,
                       suite: suite, directories: directories)
    }

    private static func withFixture(_ body: (Fixture, inout [String]) -> Void) -> [String] {
        MainActor.assumeIsolated {
            guard let fixture = makeFixture() else { return ["could not build the Ask fixture"] }
            defer { fixture.cleanUp() }
            var problems: [String] = []
            body(fixture, &problems)
            return problems
        }
    }

    private static func focusTotalsMatchHistory() -> [String] {
        withFixture { f, problems in
            let text = f.store.askLookup(.focusTotals(.thisWeek, words: nil))
            let lead = "This week: 2h 30m focused over 2 sessions on 2 days; best day Tue 14 Nov, 1h 30m."
            expect(text.hasPrefix(lead), "this week's totals say “\(text)”, not “\(lead)…”", &problems)

            let week = AskRange.thisWeek.interval(now: f.clock.value, firstDay: f.store.historyTop().firstDay,
                                                  calendar: f.calendar)
            let summary = f.store.historySummary(for: HistoryPlace(level: .week, span: week))
            expect(summary.focused == 9_000, "History reads \(summary.focused)s for the week, not 9000s", &problems)
            expect(text.hasPrefix("This week: \(DurationText.compact(summary.focused)) focused over "
                                  + "\(summary.sessions) sessions on \(summary.focusedDays) days"),
                   "Ask's week differs from History's: “\(text)”", &problems)

            let days = text.components(separatedBy: " By day: ").dropFirst().first ?? ""
            for day in ["Mon 13 Nov", "Tue 14 Nov", "Wed 15 Nov"] {
                expect(days.contains(day), "the by-day list omits \(day): “\(days)”", &problems)
            }
            for day in ["Thu 16 Nov", "Fri 17 Nov", "Sat 18 Nov", "Sun 19 Nov"] {
                expect(!text.contains(day), "the answer names \(day), a day that has not come: “\(text)”", &problems)
            }
        }
    }

    private static func liveSessionCountsToday() -> [String] {
        withFixture { f, problems in
            f.engine.start(workType: .deepWork, intent: "Thesis")
            f.clock.advance(20 * 60)
            f.store.updateTimeDrivenFigures()
            let text = f.store.askLookup(.focusTotals(.today, words: nil))
            expect(text.contains("20m"), "the running session's 20m is missing from “\(text)”", &problems)
        }
    }

    private static func wordsNarrowTotals() -> [String] {
        withFixture { f, problems in
            let week = f.store.askLookup(.focusTotals(.thisWeek, words: "thesis"))
            expect(week == "Sessions matching “thesis” this week: 1h over 1 session on 1 day.",
                   "thesis this week says “\(week)”", &problems)
            let month = f.store.askLookup(.focusTotals(.lastMonth, words: "thesis"))
            expect(month.contains("2h"), "thesis last month says “\(month)”, not 2h", &problems)
        }
    }

    private static func findSessionsStaysInRange() -> [String] {
        withFixture { f, problems in
            let cases: [(AskRequest, String)] = [
                // "thesis" matches the name, so no note is shown with it.
                (.findSessions(words: "thesis", .thisWeek), "Mon 13 Nov · Thesis · 1h"),
                (.findSessions(words: "outline", .thisWeek), "Mon 13 Nov · Thesis · 1h · note: chapter two outline"),
                (.findSessions(words: "thesis", .lastMonth), "Tue 17 Oct · Thesis · 2h"),
                (.findSessions(words: "zebra", .thisWeek), "No sessions match “zebra” this week."),
                // Monday's session sits on the day the last week ends at midnight.
                (.findSessions(words: "thesis", .lastWeek), "No sessions match “thesis” last week."),
            ]
            for (request, want) in cases {
                let got = f.store.askLookup(request)
                expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
            }
        }
    }

    private static func bestHoursNamesWindow() -> [String] {
        withFixture { f, problems in
            let text = f.store.askLookup(.bestHours(.last30Days))
            expect(text.hasPrefix("Over the 5 weeks to 15 Nov: most focus 9–11am"),
                   "the best hours say “\(text)”", &problems)
            expect(text.contains("on Tuesdays"), "the strongest weekday is missing from “\(text)”", &problems)
            let today = f.store.askLookup(.bestHours(.today))
            expect(today == "Not enough focus today to tell; it needs at least 30m.",
                   "a day without focus says “\(today)”", &problems)
        }
    }

    private static func appTimeResolvesLooseNames() -> [String] {
        withFixture { f, problems in
            let cases: [(AskRequest, String)] = [
                (.appTime(.thisWeek, app: "safari."), "Safari this week: 1h in front; used in 1 session."),
                (.appTime(.thisWeek, app: "Figma"), "No app called “Figma” was used this week."),
                (.appTime(.lastWeek, app: "Safari"), "No app called “Safari” was used last week."),
            ]
            for (request, want) in cases {
                let got = f.store.askLookup(request)
                expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
            }
            let top = f.store.askLookup(.appTime(.thisWeek, app: nil))
            expect(top.hasPrefix("Most-used apps this week: Safari 1h"), "the top apps say “\(top)”", &problems)
        }
    }

    private static func allTimeStartsAtRecord() -> [String] {
        withFixture { f, problems in
            let text = f.store.askLookup(.focusTotals(.allTime, words: nil))
            expect(text.contains("4h 30m"), "all time is not 4h 30m: “\(text)”", &problems)
            expect(text.contains("October 2023"), "all time leaves out October: “\(text)”", &problems)
            for month in f.calendar.monthSymbols.prefix(9) {
                expect(!text.contains("\(month) 2023"), "all time names \(month) 2023, before the record: “\(text)”",
                       &problems)
            }
        }
    }

    private static func lookupsOnlyRead() -> [String] {
        withFixture { f, problems in
            func bytes() -> [String: Data] {
                var files: [String: Data] = [:]
                for directory in f.directories {
                    let paths = FileManager.default.enumerator(atPath: directory.path)?.allObjects as? [String] ?? []
                    for path in paths {
                        let url = directory.appendingPathComponent(path)
                        if let data = try? Data(contentsOf: url) { files[url.path] = data }
                    }
                }
                return files
            }
            let before = bytes()
            let settings = NSDictionary(dictionary: f.defaults.dictionaryRepresentation())
            for name in ["sessions.json", "app-usage.json", "session-metadata.json"] {
                expect(before.keys.contains { $0.hasSuffix("/" + name) },
                       "the fixture wrote no \(name), so nothing was compared", &problems)
            }

            var requests: [AskRequest] = [
                .focusTotals(.thisWeek, words: "thesis"), .focusTotals(.lastMonth, words: "thesis"),
                .findSessions(words: "thesis", .thisWeek), .findSessions(words: "outline", .thisWeek),
                .findSessions(words: "zebra", .thisWeek), .appTime(.thisWeek, app: "safari."),
                .appTime(.thisWeek, app: "Figma"),
            ]
            for range in AskRange.allCases {
                requests += [.focusTotals(range, words: nil), .bestHours(range), .appTime(range, app: nil)]
            }
            for request in requests where f.store.askLookup(request).isEmpty {
                problems.append("\(request.provenance) answered with nothing")
            }

            expect(bytes() == before, "a lookup changed a file in the session, usage or metadata folders",
                   &problems)
            expect(settings.isEqual(to: f.defaults.dictionaryRepresentation()),
                   "a lookup changed the preferences", &problems)
            expect(f.store.historyFilter == HistoryFilter(),
                   "a lookup left History filtered: \(f.store.historyFilter)", &problems)
        }
    }
}
