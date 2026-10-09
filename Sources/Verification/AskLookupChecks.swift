import Foundation

/// Ask Daybook's lookups, end to end through a real store: each answer is
/// History's or Insights' own figure for the same period, read the way the
/// app reads it with the Ask sheet open over the story (the dashboard shown,
/// History not), and a lookup writes nothing.
enum AskLookupChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's focus totals are History's own figures for the same period", focusTotalsMatchHistory),
        ("Ask counts the session still running today", liveSessionCountsToday),
        ("Words narrow Ask's totals to the sessions that match", wordsNarrowTotals),
        ("Ask lists matching sessions inside the range only", findSessionsStaysInRange),
        ("Ask names the two-hour window and the weekday it sits on", bestHoursNamesWindow),
        ("Ask finds an app by a loose name and says so when none matches", appTimeResolvesLooseNames),
        ("Ask's all-time figures start at the first record", allTimeStartsAtRecord),
        ("Ask lookups write nothing and leave History's filter alone", lookupsOnlyRead),
        ("Ask reads History's figures when History has never been open, and rebuilds nothing twice",
         lookupsWorkWithHistoryHidden),
    ]

    /// Wed 15 Nov 2023, 09:13, on a store whose History holds three sessions:
    /// Thesis on Mon 13 Nov 9–10 with the note "chapter two outline", Parser
    /// on Tue 14 Nov 14:00–15:30 with Safari in front 14:00–15:00, and Thesis
    /// on Tue 17 Oct 9–11. No break is recorded. The dashboard is shown and
    /// History never has been, so its day index is not built.
    struct Fixture {
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

    /// `extraThesisDays` adds that many past days, each with one minute of
    /// Thesis and of Safari, for checks that need a long history.
    private static func makeFixture(extraThesisDays: Int = 0) -> Fixture? {
        let clock = TestClock(SelfTest.base)
        let calendar = Calendar.current.forPeriods
        let directories = (0..<3).map { _ in SelfTest.scratchDirectory() }
        directories.forEach { try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        let suite = "fc-selftest-ask-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        // A moment on the day `back` days before today, in the store's calendar.
        func moment(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: clock.value))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        // Written in one go: a thousand appends would rewrite the file a thousand times.
        let extraDays = (0..<extraThesisDays).map { 40 + $0 }
        let extra = extraDays.map {
            SessionRecord(name: "Thesis", workType: .deepWork, start: moment($0, 9), end: moment($0, 9, 1),
                          workSeconds: 60)
        }
        let file = directories[0].appendingPathComponent("sessions.json")
        if !extra.isEmpty, (try? JSONEncoder().encode(extra).write(to: file, options: .atomic)) == nil { return nil }
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
            metadata: AppUsageMetadata(accurateFrom: moment(40 + extraThesisDays, 0)),
            sessions: [AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                       start: moment(1, 14), end: moment(1, 15))]
                + extraDays.map {
                    AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                    start: moment($0, 9), end: moment($0, 9, 1))
                })
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
        return Fixture(clock: clock, calendar: calendar, engine: engine, store: store, defaults: defaults,
                       suite: suite, directories: directories)
    }

    static func withFixture(extraThesisDays: Int = 0, _ body: (Fixture, inout [String]) -> Void) -> [String] {
        MainActor.assumeIsolated {
            guard let fixture = makeFixture(extraThesisDays: extraThesisDays) else {
                return ["could not build the Ask fixture"]
            }
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

            // One day is its own best and has no breakdown: neither is said.
            let yesterday = f.store.askLookup(.focusTotals(.yesterday, words: nil))
            expect(yesterday == "Yesterday: 1h 30m focused over 1 session on 1 day.",
                   "yesterday says “\(yesterday)”", &problems)
        }
    }

    private static func liveSessionCountsToday() -> [String] {
        withFixture { f, problems in
            f.engine.start(workType: .deepWork, intent: "Thesis")
            f.clock.advance(20 * 60)
            let text = f.store.askLookup(.focusTotals(.today, words: nil))
            expect(text == "Today: 20m focused over 1 session on 1 day.",
                   "the running session's 20m, alone, reads “\(text)”", &problems)
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

    /// The sheet opens over the story, where History's day index is never
    /// built or kept current. A lookup brings it up to date itself, once,
    /// and leaves History hidden.
    private static func lookupsWorkWithHistoryHidden() -> [String] {
        withFixture { f, problems in
            expect(!f.store.reviewVisible, "the fixture shows History", &problems)
            expect(f.store.historyDays.isEmpty, "History's index was built before any lookup", &problems)

            let first = f.store.askLookup(.focusTotals(.thisWeek, words: nil))
            expect(first.hasPrefix("This week: 2h 30m focused over 2 sessions"),
                   "with History hidden, this week says “\(first)”", &problems)
            expect(!f.store.reviewVisible, "a lookup left History showing", &problems)

            // Already current: the same question again rebuilds nothing.
            func builds() -> [Int] {
                [f.store.historyIndexGeneration, f.store.reviewReadModelGeneration, f.store.historyTreeComputeCount]
            }
            let built = builds()
            let second = f.store.askLookup(.focusTotals(.thisWeek, words: nil))
            expect(second == first, "the same question answered “\(second)” the second time", &problems)
            expect(builds() == built, "a second lookup rebuilt History: \(built) became \(builds())", &problems)

            // Behind again once a session is saved: the next lookup sees it.
            f.engine.start(workType: .deepWork, intent: "Thesis")
            f.clock.advance(20 * 60)
            expect(f.engine.stop(), "the session did not stop", &problems)
            let later = f.store.askLookup(.focusTotals(.today, words: nil))
            expect(later == "Today: 20m focused over 1 session on 1 day.",
                   "after a saved session, today says “\(later)”", &problems)
            expect(!f.store.reviewVisible, "a lookup left History showing", &problems)
        }
    }
}
