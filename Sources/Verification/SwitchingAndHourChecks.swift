import Foundation

/// Three metric figures that disagreed with the evidence behind them: the
/// hourly usage bars on a day the clocks move by half an hour, the switch rate
/// of one resumed focus thread (a day against its range), and the switch rate
/// of a window made of same-app segments.
enum SwitchingAndHourChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The hourly bars add up on days the clocks move by 30 minutes, and never leave the grid",
         hourlyBarsSurviveHalfHourChange),
        ("A resumed thread's app change counts the same for its day as for its range",
         resumedThreadSwitchesAgree),
        ("App switches per minute count changes of app, not same-app segment boundaries",
         switchRateCountsAppChanges),
    ]

    // MARK: Hourly bars

    private static var lordHowe: Calendar? {
        guard let zone = TimeZone(identifier: "Australia/Lord_Howe") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// One app's single stretch on a Lord Howe day, between wall-clock hours
    /// (nil for the whole day): its hourly bars and the day's tracked time.
    private static func bars(year: Int, month: Int, day: Int, from: Int? = nil, to: Int? = nil,
                             calendar: Calendar) -> (bars: [HourBucket], tracked: TimeInterval)? {
        guard let noon = calendar.date(from: DateComponents(year: year, month: month,
                                                            day: day, hour: 12)) else { return nil }
        let dayStart = calendar.startOfDay(for: noon)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        func wall(_ hour: Int?, else fallback: Date) -> Date {
            hour.flatMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: dayStart) }
                ?? fallback
        }
        let clock = TestClock(noon)
        let usage = SelfTest.makeUsageArchive(
            clock,
            sessions: [AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                       start: wall(from, else: dayStart),
                                       end: wall(to, else: dayEnd))],
            accurateFrom: dayStart.addingTimeInterval(-86_400))
        let stats = DashboardStats(sessions: SelfTest.makeArchive(clock), usage: usage,
                                   calendar: calendar, now: { clock.value })
        return (stats.hourlyBuckets(for: noon, bundleID: "com.a"), stats.trackedTotal(for: noon))
    }

    private static func hourlyBarsSurviveHalfHourChange() -> [String] {
        var problems: [String] = []
        guard let calendar = lordHowe else { return ["no Lord Howe time zone"] }

        // Spring: 02:00 jumps to 02:30, a 23.5-hour day.
        if let spring = bars(year: 2026, month: 10, day: 4, calendar: calendar) {
            expect(spring.tracked == 84_600, "the spring day tracks 23.5 hours, got \(spring.tracked)",
                   &problems)
            expect(spring.bars.reduce(0) { $0 + $1.seconds } == 84_600,
                   "the spring day's bars add up to 84,600 s, got "
                   + "\(spring.bars.reduce(0) { $0 + $1.seconds })", &problems)
            expect(spring.bars.count == 24 && spring.bars.filter { $0.seconds == 1_800 }.count == 1,
                   "the spring day has 24 bars, one of them the half hour, got "
                   + "\(spring.bars.map(\.seconds))", &problems)
            expect(zip(spring.bars, spring.bars.dropFirst()).allSatisfy { $0.hour < $1.hour },
                   "the spring bars run forward in time", &problems)
        } else { problems.append("could not build the Lord Howe spring day") }

        // Autumn: 02:00 falls back to 01:30, a 24.5-hour day.
        if let autumn = bars(year: 2026, month: 4, day: 5, calendar: calendar) {
            expect(autumn.tracked == 88_200, "the autumn day tracks 24.5 hours, got \(autumn.tracked)",
                   &problems)
            expect(autumn.bars.reduce(0) { $0 + $1.seconds } == 88_200,
                   "the autumn day's bars add up to 88,200 s, got "
                   + "\(autumn.bars.reduce(0) { $0 + $1.seconds })", &problems)
            expect(autumn.bars.count == 25 && autumn.bars.filter { $0.seconds == 1_800 }.count == 1,
                   "the autumn day has 25 bars, one of them the half hour, got "
                   + "\(autumn.bars.map(\.seconds))", &problems)
            expect(zip(autumn.bars, autumn.bars.dropFirst()).allSatisfy { $0.hour < $1.hour },
                   "the autumn bars run forward in time", &problems)
        } else { problems.append("could not build the Lord Howe autumn day") }

        // A stretch across the change: 01:00 to 04:00 on the clock is 2.5 hours.
        if let across = bars(year: 2026, month: 10, day: 4, from: 1, to: 4, calendar: calendar) {
            expect(across.bars.map(\.seconds).filter { $0 > 0 } == [3_600, 1_800, 3_600],
                   "01:00 to 04:00 across the spring change fills hour, half hour, hour; got "
                   + "\(across.bars.map(\.seconds))", &problems)
        } else { problems.append("could not build the spring stretch") }

        // An ordinary day is unchanged: whole hours, one bar each.
        if let plain = bars(year: 2026, month: 7, day: 1, from: 9, to: 12, calendar: calendar) {
            expect(plain.bars.map(\.seconds).filter { $0 > 0 } == [3_600, 3_600, 3_600],
                   "an ordinary stretch fills whole hours, got \(plain.bars.map(\.seconds))",
                   &problems)
        } else { problems.append("could not build the ordinary day") }
        return problems
    }

    // MARK: Switches per focus session

    /// The day and range figures for one set of evidence, on the same calendar.
    private static func switchesPerSession(records: [SessionRecord], usage stretches: [(String, TimeInterval)])
        -> (day: FocusQuality, range: FocusQuality) {
        let calendar = Calendar.current
        let clock = TestClock(SelfTest.base.addingTimeInterval(8 * 3_600))
        let usage = SelfTest.makeUsageArchive(
            clock,
            sessions: stretches.map { app, offset in
                AppUsageSession(bundleID: app, appName: app,
                                start: SelfTest.base.addingTimeInterval(offset),
                                end: SelfTest.base.addingTimeInterval(offset + 1_800))
            },
            accurateFrom: SelfTest.base.addingTimeInterval(-86_400))
        let stats = DashboardStats(sessions: SelfTest.makeArchive(clock, records: records,
                                                                  calendar: calendar),
                                   usage: usage, calendar: calendar, now: { clock.value })
        return (stats.focusQuality(for: SelfTest.base), stats.focusQuality(for: [SelfTest.base]))
    }

    private static func record(_ name: String, at offset: TimeInterval, thread: UUID) -> SessionRecord {
        SessionRecord(name: name, workType: .deepWork,
                      start: SelfTest.base.addingTimeInterval(offset),
                      end: SelfTest.base.addingTimeInterval(offset + 1_800),
                      workSeconds: 1_800, threadID: thread)
    }

    private static func resumedThreadSwitchesAgree() -> [String] {
        var problems: [String] = []
        let thread = UUID()
        let resumed = [record("Report", at: 0, thread: thread),
                       record("Report", at: 7_200, thread: thread)]

        // One thread, Alpha before the gap and Beta after it: one switch.
        let moved = switchesPerSession(records: resumed, usage: [("alpha", 0), ("beta", 7_200)])
        expect(moved.range.sessionCount == 1 && moved.range.switchesPerSession == 1,
               "the range counts the resumed A-to-B change once, got "
               + "\(moved.range.switchesPerSession) over \(moved.range.sessionCount)", &problems)
        expect(moved.day.sessionCount == 1 && moved.day.switchesPerSession == 1,
               "the day counts the same change, got \(moved.day.switchesPerSession) over "
               + "\(moved.day.sessionCount)", &problems)

        // The same app on both sides of the gap is no switch.
        let same = switchesPerSession(records: resumed, usage: [("alpha", 0), ("alpha", 7_200)])
        expect(same.day.switchesPerSession == 0 && same.range.switchesPerSession == 0,
               "a resumed thread on one app has no switch, got day "
               + "\(same.day.switchesPerSession), range \(same.range.switchesPerSession)", &problems)

        // Two different threads never chain into a switch between them.
        let separate = [record("One", at: 0, thread: UUID()), record("Two", at: 7_200, thread: UUID())]
        let apart = switchesPerSession(records: separate, usage: [("alpha", 0), ("beta", 7_200)])
        expect(apart.day.sessionCount == 2 && apart.day.switchesPerSession == 0
                && apart.range.switchesPerSession == 0,
               "two threads on two apps are two sessions and no switch, got day "
               + "\(apart.day.switchesPerSession)/\(apart.day.sessionCount), range "
               + "\(apart.range.switchesPerSession)/\(apart.range.sessionCount)", &problems)
        return problems
    }

    // MARK: Switch rate

    /// Equal slices of a fifteen-minute window, one per entry, each an app.
    private static func slices(_ apps: [String]) -> [AppUsageSession] {
        let step = 900 / Double(apps.count)
        return apps.enumerated().map { index, app in
            AppUsageSession(bundleID: app, appName: app,
                            start: SelfTest.base.addingTimeInterval(Double(index) * step),
                            end: SelfTest.base.addingTimeInterval(Double(index + 1) * step))
        }
    }

    private static func switchRateCountsAppChanges() -> [String] {
        var problems: [String] = []
        let scorer = FocusScorer()
        let window = (start: SelfTest.base, end: SelfTest.base.addingTimeInterval(900))
        let warp = "dev.warp.Warp-Stable", xcode = "com.apple.dt.Xcode"

        let steady = scorer.score(segments: slices(Array(repeating: warp, count: 30)),
                                  activity: .active, window: window)
        SelfTest.expectClose(steady.signals.switchesPerMinute, 0,
                             "thirty Warp segments are no app switches", &problems)
        expect(steady.value == 1, "an unbroken Warp stretch scores full focus, got \(steady.value)",
               &problems)
        expect(steady.explanation.contains("0.0 switches/min"),
               "the explanation reports no churn, got '\(steady.explanation)'", &problems)

        let alternating = (0..<30).map { $0.isMultiple(of: 2) ? warp : xcode }
        SelfTest.expectClose(
            scorer.score(segments: slices(alternating), activity: .active, window: window)
                .signals.switchesPerMinute,
            29.0 / 15, "thirty alternating segments are 29 app changes in 15 minutes", &problems)

        let blocks = Array(repeating: warp, count: 10) + Array(repeating: xcode, count: 10)
            + Array(repeating: warp, count: 10)
        SelfTest.expectClose(
            scorer.score(segments: slices(blocks), activity: .active, window: window)
                .signals.switchesPerMinute,
            2.0 / 15, "Warp, Xcode, Warp in blocks of ten segments is two app changes", &problems)

        // The reason an automatic session gives is that same text.
        var detector = AutoSessionDetector(breakLength: 600)
        _ = detector.evaluate(score: steady, at: SelfTest.base, sessionRunning: false,
                              sessionWasAutoStarted: false, enginePaused: false)
        let decision = detector.evaluate(
            score: steady, at: SelfTest.base.addingTimeInterval(FocusConstants.autoStartDwell),
            sessionRunning: false, sessionWasAutoStarted: false, enginePaused: false)
        if case let .start(_, _, _, because) = decision {
            expect(because.contains("0.0 switches/min"),
                   "the start reason reports no churn, got '\(because)'", &problems)
        } else {
            problems.append("an unbroken run did not start a session, got \(decision)")
        }
        return problems
    }
}
