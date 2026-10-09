import Foundation

/// The hour grid and category bar behind History's "Best two hours" tile,
/// and the day's category figures beside the goals. Each clock hour gets the
/// work done in it: every hour of a night the clocks go back, nothing for a
/// pause, and nothing on a new day for work done before midnight.
enum InsightHourChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every hour of a night the clocks go back reaches the hour grid, the repeated hour included",
         repeatedHourCounted),
        ("A saved session's pause stays in the hour it happened instead of thinning its span",
         savedPauseStaysPut),
        ("A running session paused past midnight gives the new day none of the old day's work",
         livePauseStaysOnItsDay),
        ("The shared hour walk gives every hour of a night the clocks go back its own work",
         hourWalkCountsRepeatedHour),
    ]

    /// The one walk behind the hour grid and the Insights category hours. A
    /// 01:30–04:00 session across Sydney's 03:00 → 02:00 change is three and a
    /// half hours of work, and a pause at its start stays in its own slice.
    private static func hourWalkCountsRepeatedHour() -> [String] {
        var problems: [String] = []
        let calendar = calendar(in: "Australia/Sydney")
        let day = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5))!
        let start = calendar.date(byAdding: .minute, value: 90, to: day)!
        let end = start.addingTimeInterval(12_600)
        let paused = DateInterval(start: start, duration: 1_800)
        let record = SessionRecord(name: "Writing", workType: .deepWork, start: start, end: end,
                                   workSeconds: 10_800, pausedSpans: [paused])
        var total: TimeInterval = 0
        var first: TimeInterval = -1
        HourlyWork.forEachHour(from: start, to: end, calendar: calendar,
                               work: record.workSeconds(in:)) { slice, _, seconds in
            if slice == start { first = seconds }
            total += seconds
        }
        SelfTest.expectClose(total, 10_800, "work across the repeated hour", &problems)
        SelfTest.expectClose(first, 0, "work in the paused first half hour", &problems)
        return problems
    }

    private static func calendar(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// History's facts for `day` alone, over these saved records, read
    /// through `calendar` the day after.
    private static func dayFacts(_ records: [SessionRecord], day: Date,
                                 calendar: Calendar) -> InsightRangeFacts {
        MainActor.assumeIsolated {
            let clock = TestClock(calendar.date(byAdding: .day, value: 1, to: day)!)
            let suite = "fc-selftest-insight-hours-\(UUID().uuidString)"
            defer { MemoryDefaults.remove(named: suite) }
            let engine = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: suite)!),
                                       archive: SelfTest.makeArchive(clock, records: records,
                                                                     calendar: calendar),
                                       ownBundleID: "fc.insight.fixture", schedulesDwell: false,
                                       now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            return store.insightReading(scope: .day, anchoredAt: day, limit: 1, calendar: calendar).facts
        }
    }

    /// 5 April 2026 is the night daylight saving ends in Sydney (an hour back
    /// at 03:00) and on Lord Howe Island (half an hour back at 02:00). Setting
    /// the hour by number stopped the walk at the repeated hour.
    private static func repeatedHourCounted() -> [String] {
        var problems: [String] = []
        let cases: [(zone: String, dayLength: TimeInterval, hour: Int, hourLength: TimeInterval)] = [
            ("Australia/Sydney", 90_000, 2, 7_200),
            ("Australia/Lord_Howe", 88_200, 1, 5_400),
        ]
        for fixture in cases {
            let calendar = calendar(in: fixture.zone)
            let day = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5))!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let wholeDay = SessionRecord(name: "Writing", workType: .deepWork, start: day, end: next,
                                         workSeconds: next.timeIntervalSince(day))
            let facts = dayFacts([wholeDay], day: day, calendar: calendar)
            let hours = facts.grid.first ?? []
            SelfTest.expectClose(hours.reduce(0, +), fixture.dayLength,
                                 "\(fixture.zone): the hour grid for a day-long session", &problems)
            SelfTest.expectClose(hours.count == 24 ? hours[fixture.hour] : -1, fixture.hourLength,
                                 "\(fixture.zone): hour \(fixture.hour), lived twice", &problems)
            SelfTest.expectClose(facts.categories.first?.seconds ?? 0, fixture.dayLength,
                                 "\(fixture.zone): the category bar for the day", &problems)
        }

        // 01:30 summer time to 04:00 standard time is three and a half hours.
        let sydney = calendar(in: "Australia/Sydney")
        let day = sydney.date(from: DateComponents(year: 2026, month: 4, day: 5))!
        let start = sydney.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 1, minute: 30))!
        let end = sydney.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 4))!
        let night = SessionRecord(name: "Writing", workType: .deepWork, start: start, end: end,
                                  workSeconds: end.timeIntervalSince(start))
        let hours = dayFacts([night], day: day, calendar: sydney).grid.first ?? []
        SelfTest.expectClose(hours.reduce(0, +), 12_600, "Sydney: the hour grid for 01:30 to 04:00", &problems)
        for (hour, expected) in [(1, 1_800.0), (2, 7_200.0), (3, 3_600.0)] {
            SelfTest.expectClose(hours.count == 24 ? hours[hour] : -1, expected,
                                 "Sydney: hour \(hour) of 01:30 to 04:00", &problems)
        }
        return problems
    }

    /// 09:00 to 11:00 with the first hour paused is an hour's work, all of it
    /// from 10:00. Spreading the work over the span put half in each hour.
    private static func savedPauseStaysPut() -> [String] {
        var problems: [String] = []
        let sydney = calendar(in: "Australia/Sydney")
        let day = sydney.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let nine = sydney.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 9))!
        let ten = sydney.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 10))!
        let eleven = sydney.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 11))!
        let record = SessionRecord(name: "Writing", workType: .deepWork, start: nine, end: eleven,
                                   workSeconds: 3_600,
                                   pausedSpans: [DateInterval(start: nine, end: ten)])
        expect(record.exactPausedSpans != nil, "the fixture's pause should add up to its paused total", &problems)
        let facts = dayFacts([record], day: day, calendar: sydney)
        let hours = facts.grid.first ?? []
        SelfTest.expectClose(hours.count == 24 ? hours[9] : -1, 0, "the paused hour, 09:00", &problems)
        SelfTest.expectClose(hours.count == 24 ? hours[10] : -1, 3_600, "the worked hour, 10:00", &problems)
        SelfTest.expectClose(facts.categories.first?.seconds ?? 0, 3_600, "the category bar", &problems)
        return problems
    }

    /// An hour's work up to midnight, then an hour paused after it. The work
    /// is yesterday's; capping the session's work at today's overlap gave
    /// today the same hour again.
    private static func livePauseStaysOnItsDay() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // The story's day is Calendar.current's, so the fixture's is too.
            let calendar = SelfTest.gregorian
            let midnight = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
            let yesterday = calendar.date(byAdding: .day, value: -1, to: midnight)!
            let clock = TestClock(midnight.addingTimeInterval(-3_600))
            let suite = "fc-selftest-insight-live-\(UUID().uuidString)"
            defer { MemoryDefaults.remove(named: suite) }
            let engine = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: suite)!),
                                       archive: SelfTest.makeArchive(clock),
                                       ownBundleID: "fc.insight.fixture", schedulesDwell: false,
                                       now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Writing")
            clock.advance(3_600)
            engine.transition(on: .manualPause)
            clock.advance(3_600)
            expect(engine.state == .paused(reason: .manual),
                   "the session should sit paused, got \(engine.state)", &problems)

            SelfTest.expectClose(store.storyCategorySeconds(on: midnight)[.deepWork] ?? 0, 0,
                                 "today's category figure", &problems)
            SelfTest.expectClose(store.storyCategorySeconds(on: yesterday)[.deepWork] ?? 0, 3_600,
                                 "yesterday's category figure", &problems)
            let today = store.insightReading(scope: .day, anchoredAt: midnight, limit: 1,
                                             calendar: calendar).facts
            SelfTest.expectClose(today.hourTotals.reduce(0, +), 0, "today's hour grid", &problems)
            SelfTest.expectClose(today.categories.first?.seconds ?? 0, 0, "today's category bar", &problems)
            let before = store.insightReading(scope: .day, anchoredAt: yesterday, limit: 1,
                                              calendar: calendar).facts
            SelfTest.expectClose(before.hourTotals.reduce(0, +), 3_600, "yesterday's hour grid", &problems)
            return problems
        }
    }
}
