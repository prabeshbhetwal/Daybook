import Foundation

/// Regression coverage for the Story read model. Every fixture uses isolated
/// preferences and on-disk archives; no test reads or writes the user's data.
enum StoryAccountingChecks {

    static let tests: [(String, () -> [String])] = [
        ("Story accounting: running work stays consistent across scopes", runningWorkStaysConsistentAcrossScopes),
        ("Story accounting: focus-only days define focus averages", focusOnlyDaysDefineFocusAverages),
        ("Story accounting: usage intersections reconcile across scopes", usageIntersectionsReconcileAcrossScopes),
        ("Story accounting: paused spans cannot create credited coverage", pausedSpansCannotCreateCreditedCoverage),
        ("Story accounting: paused cross-midnight coverage reconciles across scopes", pausedCrossMidnightCoverageReconcilesAcrossScopes),
        ("Story accounting: cross-midnight running work is clipped and deduplicated", crossMidnightRunningWorkIsClippedAndDeduplicated),
        ("Story accounting: History detail preserves out-of-period evidence", historyDetailPreservesOutOfPeriodEvidence)
    ]

    private final class Clock {
        var value: Date
        init(_ value: Date) { self.value = value }
        func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
    }

    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-story-accounting-\(UUID().uuidString)", isDirectory: true)
    }

    private static func makeStore(_ clock: Clock,
                                  calendar: Calendar = .current)
        -> (store: SessionStore, engine: SessionEngine, usage: AppUsageArchive, cleanUp: () -> Void)? {
        let sessionDirectory = scratchDirectory()
        let usageDirectory = scratchDirectory()
        let suiteName = "com.prabesh.focuscontinuity.story-accounting.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        defaults.removePersistentDomain(forName: suiteName)
        let archive = SessionArchive(directory: sessionDirectory, calendar: calendar,
                                     now: { clock.value })
        let usage = AppUsageArchive(directory: usageDirectory, calendar: calendar,
                                    now: { clock.value })
        let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "com.example.story", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.story",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        return (store, engine, usage, {
            try? FileManager.default.removeItem(at: sessionDirectory)
            try? FileManager.default.removeItem(at: usageDirectory)
            defaults.removePersistentDomain(forName: suiteName)
        })
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int, _ minute: Int,
                             calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private static func expectClose(_ actual: TimeInterval, _ expected: TimeInterval,
                                    _ label: String, _ problems: inout [String]) {
        if abs(actual - expected) > 0.01 {
            problems.append("\(label): expected \(expected)s, got \(actual)s")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool,
                               _ label: String, _ problems: inout [String]) {
        if !condition() { problems.append(label) }
    }

    private static func runningWorkStaysConsistentAcrossScopes() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let start = date(2026, 8, 19, 12, 0, calendar: calendar)
            let clock = Clock(start)
            guard let fixture = makeStore(clock, calendar: calendar) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }

            fixture.engine.start(workType: .deepWork, intent: "Live work")
            clock.advance(10 * 60)
            fixture.store.refreshReview(period: .week)

            let today = calendar.startOfDay(for: clock.value)
            expectClose(fixture.store.storyFocusedSeconds(on: today), 10 * 60,
                        "Day includes ten-minute running work", &problems)
            expectClose(fixture.store.storyFocusSummary.focused, 10 * 60,
                        "Week includes ten-minute running work", &problems)
            let monthFacts = fixture.store.dayFacts(inMonthOf: today)
            expectClose(monthFacts[today]?.focused ?? -1, 10 * 60,
                        "Month cell includes ten-minute running work", &problems)
            expectClose(fixture.store.reviewFocusSessions.first?.seconds ?? -1, 10 * 60,
                        "Review focus entry includes ten-minute running work", &problems)
            expectClose(fixture.store.reviewLongestFocusSeconds, 10 * 60,
                        "Review longest stretch includes running work", &problems)
            expectClose(fixture.store.reviewBestDay?.focused ?? -1, 10 * 60,
                        "Review best day includes running work", &problems)
            expectClose(fixture.store.historyDays.first(where: {
                calendar.isDate($0.date, inSameDayAs: today)
            })?.focused ?? -1, 10 * 60,
                        "History current-day row includes running work", &problems)
            expect(fixture.engine.archive.records.isEmpty,
                   "live Story accounting must not append a synthetic archive record", &problems)
            return problems
        }
    }

    private static func focusOnlyDaysDefineFocusAverages() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let anchor = date(2026, 8, 19, 12, 0, calendar: calendar)
            let clock = Clock(anchor)
            guard let fixture = makeStore(clock, calendar: calendar) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            let day = calendar.startOfDay(for: anchor)
            fixture.engine.archive.append(SessionRecord(name: "Reading", workType: .deepWork,
                                                         start: day.addingTimeInterval(9 * 3_600),
                                                         end: day.addingTimeInterval(9 * 3_600 + 30 * 60),
                                                         workSeconds: 30 * 60))
            fixture.store.refreshReview(period: .week)

            expectClose(fixture.store.reviewSummary.tracked, 0,
                        "tracked period summary remains independently zero", &problems)
            expect(fixture.store.storyFocusSummary.activeDays == 1,
                   "focus-only evidence counts as one focused day", &problems)
            expectClose(fixture.store.storyFocusSummary.averagePerActiveDay, 30 * 60,
                        "focus average is based on focus-only day", &problems)
            return problems
        }
    }

    private static func usageIntersectionsReconcileAcrossScopes() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let anchor = date(2026, 8, 19, 12, 0, calendar: calendar)
            let clock = Clock(anchor)
            guard let fixture = makeStore(clock, calendar: calendar) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            let day = calendar.startOfDay(for: anchor)
            fixture.engine.archive.append(SessionRecord(name: "Write", workType: .deepWork,
                                                         start: day.addingTimeInterval(9 * 3_600),
                                                         end: day.addingTimeInterval(10 * 3_600),
                                                         workSeconds: 60 * 60))
            fixture.usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                                  start: day.addingTimeInterval(9 * 3_600 + 15 * 60),
                                                  end: day.addingTimeInterval(9 * 3_600 + 45 * 60)))
            fixture.usage.record(AppUsageSession(bundleID: "com.example.mail", appName: "Mail",
                                                  start: day.addingTimeInterval(10 * 3_600),
                                                  end: day.addingTimeInterval(10 * 3_600 + 20 * 60)))
            fixture.store.refreshReview(period: .week)

            let dayBreakdown = fixture.store.storyUsageBreakdown(on: day)
            let periodBreakdown = fixture.store.storyUsageBreakdown
            expectClose(dayBreakdown.tracked, 50 * 60, "day tracked evidence", &problems)
            expectClose(dayBreakdown.insideSessions, 30 * 60,
                        "usage inside focus is its literal intersection", &problems)
            expectClose(dayBreakdown.outsideSessions, 20 * 60,
                        "usage outside focus is the observed remainder", &problems)
            expectClose(dayBreakdown.uncoveredFocus, 30 * 60,
                        "uncovered focus is declared work without credited coverage", &problems)
            expectClose(periodBreakdown.tracked, dayBreakdown.tracked,
                        "period tracked reconciles with its only active day", &problems)
            expectClose(periodBreakdown.insideSessions, dayBreakdown.insideSessions,
                        "period inside usage reconciles with its only active day", &problems)
            expectClose(periodBreakdown.outsideSessions, dayBreakdown.outsideSessions,
                        "period outside usage reconciles with its only active day", &problems)
            return problems
        }
    }

    private static func pausedSpansCannotCreateCreditedCoverage() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let anchor = date(2026, 8, 19, 12, 0, calendar: calendar)
            let clock = Clock(anchor)
            guard let fixture = makeStore(clock, calendar: calendar) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            let day = calendar.startOfDay(for: anchor)
            fixture.engine.archive.append(SessionRecord(name: "Paused", workType: .deepWork,
                                                         start: day.addingTimeInterval(9 * 3_600),
                                                         end: day.addingTimeInterval(10 * 3_600),
                                                         workSeconds: 10 * 60))
            fixture.usage.record(AppUsageSession(bundleID: "com.example.video", appName: "Video",
                                                  start: day.addingTimeInterval(9 * 3_600),
                                                  end: day.addingTimeInterval(10 * 3_600)))

            let breakdown = fixture.store.storyUsageBreakdown(on: day)
            expectClose(breakdown.tracked, 60 * 60,
                        "observed use remains the recorder's literal hour", &problems)
            expectClose(breakdown.insideSessions, 60 * 60,
                        "inside usage is literal temporal session membership", &problems)
            expectClose(breakdown.outsideSessions, 0,
                        "no observed use falls outside the session span", &problems)
            expectClose(breakdown.uncoveredFocus, 0,
                        "recorded work with matching usage has no missing coverage", &problems)
            let credited = FocusedActiveTime.seconds(on: day,
                                                      records: fixture.engine.archive.records,
                                                      usage: fixture.usage.sessions,
                                                      running: nil,
                                                      calendar: calendar)
            expectClose(credited, 10 * 60,
                        "credited focus remains bounded by recorded work", &problems)
            return problems
        }
    }

    private static func pausedCrossMidnightCoverageReconcilesAcrossScopes() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let start = date(2026, 8, 18, 23, 30, calendar: calendar)
            let clock = Clock(date(2026, 8, 19, 12, 0, calendar: calendar))
            guard let fixture = makeStore(clock, calendar: calendar) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            let firstDay = calendar.startOfDay(for: start)
            let secondDay = calendar.startOfDay(for: clock.value)
            fixture.engine.archive.append(SessionRecord(name: "Paused overnight", workType: .deepWork,
                                                         start: start,
                                                         end: start.addingTimeInterval(60 * 60),
                                                         workSeconds: 10 * 60))
            fixture.usage.record(AppUsageSession(bundleID: "com.example.video", appName: "Video",
                                                  start: start,
                                                  end: start.addingTimeInterval(30 * 60)))
            fixture.store.refreshReview(period: .week)

            let first = fixture.store.storyUsageBreakdown(on: firstDay)
            let second = fixture.store.storyUsageBreakdown(on: secondDay)
            let week = fixture.store.storyUsageBreakdown
            expectClose(first.tracked, 30 * 60, "first day tracked", &problems)
            expectClose(first.insideSessions, 30 * 60, "first day inside span", &problems)
            expectClose(first.outsideSessions, 0, "first day outside span", &problems)
            expectClose(first.uncoveredFocus, 0, "first day credited coverage", &problems)
            expectClose(second.tracked, 0, "second day tracked", &problems)
            expectClose(second.insideSessions, 0, "second day inside span", &problems)
            expectClose(second.outsideSessions, 0, "second day outside span", &problems)
            expectClose(second.uncoveredFocus, 5 * 60, "second day missing coverage", &problems)
            expectClose(week.tracked, first.tracked + second.tracked,
                        "Week tracked equals local-day sum", &problems)
            expectClose(week.insideSessions, first.insideSessions + second.insideSessions,
                        "Week inside span equals local-day sum", &problems)
            expectClose(week.outsideSessions, first.outsideSessions + second.outsideSessions,
                        "Week outside span equals local-day sum", &problems)
            expectClose(week.uncoveredFocus, first.uncoveredFocus + second.uncoveredFocus,
                        "Week uncovered focus equals local-day sum", &problems)

            fixture.store.refreshReview(period: .month)
            let month = fixture.store.storyUsageBreakdown
            expectClose(month.tracked, week.tracked, "Month tracked equals Week", &problems)
            expectClose(month.insideSessions, week.insideSessions, "Month inside span equals Week", &problems)
            expectClose(month.outsideSessions, week.outsideSessions, "Month outside span equals Week", &problems)
            expectClose(month.uncoveredFocus, week.uncoveredFocus,
                        "Month uncovered focus equals Week", &problems)
            return problems
        }
    }

    private static func crossMidnightRunningWorkIsClippedAndDeduplicated() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let start = date(2026, 8, 18, 23, 50, calendar: calendar)
            let clock = Clock(start)
            guard let fixture = makeStore(clock, calendar: calendar) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            let thread = UUID()
            fixture.engine.start(workType: .deepWork, intent: "Night hand-off", threadID: thread)
            clock.advance(20 * 60)
            let firstDay = calendar.startOfDay(for: start)
            let secondDay = calendar.startOfDay(for: clock.value)

            expectClose(fixture.store.storyFocusedSeconds(on: firstDay), 10 * 60,
                        "running work clips before midnight", &problems)
            expectClose(fixture.store.storyFocusedSeconds(on: secondDay), 10 * 60,
                        "running work clips after midnight", &problems)
            expect(fixture.store.storySessionCount(on: firstDay) == 1,
                   "first local day counts one live thread", &problems)
            expect(fixture.store.storySessionCount(on: secondDay) == 1,
                   "second local day counts one live thread", &problems)

            fixture.store.refreshReview(period: .week)
            for day in [firstDay, secondDay] {
                expectClose(fixture.store.historyDays.first(where: {
                    calendar.isDate($0.date, inSameDayAs: day)
                })?.focused ?? -1, 10 * 60,
                            "History projects running focus on \(day)", &problems)
                expect(fixture.store.historyDays.first(where: {
                    calendar.isDate($0.date, inSameDayAs: day)
                })?.sessions == 1,
                       "History deduplicates running thread on \(day)", &problems)
                let detailSeconds = fixture.store.reviewDayDetail(for: day, calendar: calendar)?
                    .focusEntries.first(where: { $0.threadID == thread })?.seconds ?? -1
                expectClose(detailSeconds, 10 * 60,
                            "History detail projects running focus on \(day)", &problems)
            }
            fixture.engine.archive.append(SessionRecord(name: "Earlier", workType: .deepWork,
                                                         start: secondDay.addingTimeInterval(60),
                                                         end: secondDay.addingTimeInterval(2 * 60),
                                                         workSeconds: 60, threadID: thread))
            expect(fixture.store.storySessionCount(on: secondDay) == 1,
                   "archived and live pieces of one thread remain one session", &problems)
            expectClose(fixture.store.storyLongestStretch(on: secondDay), 10 * 60,
                        "longest stretch is not the resumed thread total", &problems)
            return problems
        }
    }

    private static func historyDetailPreservesOutOfPeriodEvidence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let anchor = date(2026, 8, 19, 12, 0, calendar: calendar)
            let clock = Clock(anchor)
            guard let fixture = makeStore(clock, calendar: calendar) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            let olderDay = date(2026, 8, 3, 0, 0, calendar: calendar)
            fixture.engine.archive.append(SessionRecord(name: "Older focus", workType: .deepWork,
                                                         start: olderDay.addingTimeInterval(9 * 3_600),
                                                         end: olderDay.addingTimeInterval(9 * 3_600 + 15 * 60),
                                                         workSeconds: 15 * 60))
            fixture.usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                                  start: olderDay.addingTimeInterval(9 * 3_600),
                                                  end: olderDay.addingTimeInterval(9 * 3_600 + 20 * 60)))
            fixture.store.refreshReview(period: .week)

            guard let detail = fixture.store.reviewDayDetail(for: olderDay, calendar: calendar) else {
                return ["History day outside Review period should still provide detail"]
            }
            expect(detail.periodDay == nil,
                   "out-of-period History day has no misleading current-period bar", &problems)
            expect(detail.appEntries.count == 1,
                   "out-of-period History day keeps its app entry", &problems)
            expect(detail.focusEntries.count == 1,
                   "out-of-period History day keeps its focus entry", &problems)
            expectClose(detail.day.tracked, 20 * 60,
                        "out-of-period History tracked evidence", &problems)
            expectClose(detail.day.focused, 15 * 60,
                        "out-of-period History focus evidence", &problems)
            return problems
        }
    }
}
