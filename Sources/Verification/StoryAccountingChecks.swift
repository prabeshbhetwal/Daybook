import Foundation
import Combine

/// Regression coverage for the Story read model. Every fixture uses isolated
/// preferences and on-disk archives; no test reads or writes the user's data.
enum StoryAccountingChecks: CheckSuite {

    static let tests: [(String, () -> [String])] = [
        ("Repeated overnight ticks retain unique days and full-period stretches", overnightTicksKeepCanonicalEvidence),
        ("Full refresh requests dominate live requests in either transaction order", refreshPriorityIsMonotonic),
        ("Live publication does not consume a newer archive revision", livePublicationPreservesNewEvidence),
        ("Unchanged paused frames do not rebuild reports", unchangedPausedFrame),
        ("Archive query caches follow corrections and capacity eviction", archiveQueriesFollowChanges),
        ("Live day figures agree with a full rebuild at the injected clock", liveDashboardMatchesFullRefresh),
        ("Story accounting: running work stays consistent across scopes", runningWorkStaysConsistentAcrossScopes),
        ("Story accounting: focus-only days define focus averages", focusOnlyDaysDefineFocusAverages),
        ("Story accounting: usage intersections reconcile across scopes", usageIntersectionsReconcileAcrossScopes),
        ("Story accounting: paused spans cannot create credited coverage", pausedSpansCannotCreateCreditedCoverage),
        ("Story accounting: paused cross-midnight coverage reconciles across scopes", pausedCrossMidnightCoverageReconcilesAcrossScopes),
        ("Story accounting: cross-midnight running work is clipped and deduplicated", crossMidnightRunningWorkIsClippedAndDeduplicated),
        ("Story accounting: History detail preserves out-of-period evidence", historyDetailPreservesOutOfPeriodEvidence),
        ("Visible period evidence follows ticker tails and same-count archive mutations", visiblePeriodFollowsLiveEvidence),
        ("History detail namespaces legacy and live stretch identities", historyDetailKeepsLegacyAndLiveIdentity),
        ("Session app ranks include uncheckpointed and live-tail usage", appRanksUseEffectiveLiveUsage),
        ("Idle visible ticks preserve capacity read models without rebuilding", idleTicksDoNotRebuildCapacityReadModels)
    ]

    private static func overnightTicksKeepCanonicalEvidence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for includesStoredSpan in [false, true] {
                let clock = TestClock(date(2026, 8, 19, 23, 50))
                guard let fixture = makeStore(clock) else { return ["Could not create isolated preferences"] }
                defer { fixture.cleanUp() }
                fixture.engine.start(workType: .deepWork, intent: "Overnight")
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                clock.advance(1_200)
                if includesStoredSpan {
                    fixture.engine.archive.append(SessionRecord(name: "Stored overnight", workType: .deepWork,
                        start: date(2026, 8, 19, 23, 10), end: date(2026, 8, 20, 0, 5),
                        workSeconds: 3_300))
                }
                fixture.store.setDashboardVisible(true)
                fixture.store.setReviewVisible(true)
                fixture.store.refreshReview(period: .month)
                let generation = fixture.store.historyIndexGeneration
                for tick in 1...3 {
                    clock.advance(1)
                    fixture.store.updateTimeDrivenFigures()
                    let days = fixture.store.historyDays
                    expect(days.count == 2 && Set(days.map(\.date)).count == 2,
                           "tick \(tick): overnight data duplicated or lost a History date", &problems)
                    let expected = Double(1_200 + tick + (includesStoredSpan ? 3_300 : 0))
                    expectClose(days.reduce(0) { $0 + $1.focused }, expected,
                                "History does not contain each running contribution exactly once", &problems)
                    expectClose(fixture.store.reviewFocusSessions.reduce(0) { $0 + $1.seconds }, expected,
                                "period focus rows lost the prior-day portion", &problems)
                    expectClose(fixture.store.reviewLongestFocusSeconds,
                                includesStoredSpan ? 3_300 : Double(1_200 + tick),
                                "period longest is a day-only slice", &problems)
                    expect(fixture.store.historyIndexGeneration == generation,
                           "live update rebuilt stable all-history indexing", &problems)
                }
                let partial = fixture.store.historyDays
                let focus = fixture.store.reviewFocusSessions
                fixture.store.refreshReview()
                expect(partial == fixture.store.historyDays && focus == fixture.store.reviewFocusSessions,
                       "partial overnight evidence differs from a full rebuild", &problems)
            }
            return problems
        }
    }

    private static func refreshPriorityIsMonotonic() -> [String] {
        MainActor.assumeIsolated {
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            guard let fixture = makeStore(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            fixture.engine.start(workType: .deepWork, intent: "Live")
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            let past = date(2026, 8, 17, 9, 0)
            let id = UUID()
            fixture.usage.checkpoint(AppUsageSession(id: id, bundleID: "past", appName: "Past",
                                                      start: past, end: past.addingTimeInterval(600)))
            fixture.store.setReviewVisible(true)
            fixture.store.refreshReview(period: .month)
            var problems: [String] = []
            for (tickFirst, duration) in [(false, 900.0), (true, 1_200.0)] {
                clock.advance(1)
                fixture.store.withRefreshTransaction {
                    if tickFirst { fixture.store.updateTimeDrivenFigures() }
                    fixture.store.withRefreshTransaction {
                        fixture.usage.checkpoint(AppUsageSession(id: id, bundleID: "past", appName: "Past",
                            start: past, end: past.addingTimeInterval(duration)))
                    }
                    if !tickFirst { fixture.store.updateTimeDrivenFigures() }
                }
                let row = fixture.store.historyDays.first {
                    Calendar.current.isDate($0.date, inSameDayAs: past)
                }
                expectClose(row?.tracked ?? -1, duration,
                            "live request erased a full nested historical invalidation", &problems)
            }
            var armed = false
            let observer = fixture.store.$reviewDays.sink { _ in
                guard armed else { return }
                armed = false
                fixture.usage.checkpoint(AppUsageSession(id: id, bundleID: "past", appName: "Past",
                    start: past, end: past.addingTimeInterval(1_500)))
            }
            defer { observer.cancel() }
            armed = true
            fixture.store.withRefreshTransaction { fixture.store.refreshReview() }
            expectClose(fixture.store.historyDays.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: past)
            })?.tracked ?? -1, 1_500, "publication erased a newly queued full refresh", &problems)
            return problems
        }
    }

    private static func livePublicationPreservesNewEvidence() -> [String] {
        MainActor.assumeIsolated {
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            guard let fixture = makeStore(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            fixture.store.setDashboardVisible(true)
            fixture.store.setReviewVisible(true)
            let id = UUID()
            let start = clock.value.addingTimeInterval(-900)
            fixture.usage.checkpoint(AppUsageSession(id: id, bundleID: "editor", appName: "Editor",
                start: start, end: start.addingTimeInterval(600)))
            var armed = false
            let observer = fixture.store.$trackedToday.sink { _ in
                guard armed else { return }
                armed = false
                fixture.usage.checkpoint(AppUsageSession(id: id, bundleID: "editor", appName: "Editor",
                    start: start, end: start.addingTimeInterval(900)))
            }
            defer { observer.cancel() }
            armed = true
            fixture.store.updateTimeDrivenFigures()
            // The clock is deliberately unchanged. The pending source revision,
            // not a minute boundary or an open tracker tail, must trigger this pass.
            fixture.store.updateTimeDrivenFigures()
            var problems: [String] = []
            expect(!armed && fixture.usage.sessions.count == 1,
                   "the observer must correct the same record during publication", &problems)
            expectClose(fixture.usage.totalToday(), 900,
                        "durable correction was not recorded", &problems)
            expectClose(fixture.store.trackedForSelectedDay, 900,
                        "selected-day total missed the published correction", &problems)
            expectClose(fixture.store.trackedToday, 900,
                        "the frame cache consumed evidence its live values never read", &problems)
            return problems
        }
    }

    private static func unchangedPausedFrame() -> [String] {
        MainActor.assumeIsolated {
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            guard let fixture = makeStore(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            fixture.engine.start(workType: .deepWork, intent: "Pause")
            clock.advance(60)
            fixture.engine.transition(on: .manualPause)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            fixture.store.setDashboardVisible(true)
            fixture.store.setReviewVisible(true)
            fixture.store.refreshReview(period: .month)
            let dashboard = fixture.store.dashboardReadModelGeneration
            let review = fixture.store.reviewReadModelGeneration
            for _ in 0..<3 { fixture.store.updateTimeDrivenFigures() }
            return dashboard == fixture.store.dashboardReadModelGeneration
                && review == fixture.store.reviewReadModelGeneration ? []
                : ["A fixed-clock paused frame rebuilt Dashboard or Review without new evidence"]
        }
    }

    private static func archiveQueriesFollowChanges() -> [String] {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let today = date(2026, 8, 19, 12, 0)
        let archive = SessionArchive(directory: directory, now: { today }, capacity: 2)
        let yesterday = date(2026, 8, 18, 9, 0)
        let thread = UUID()
        archive.append(SessionRecord(name: "Yesterday", workType: .deepWork,
            start: yesterday, end: yesterday.addingTimeInterval(1_800), workSeconds: 1_800))
        archive.append(SessionRecord(name: "Today", workType: .deepWork,
            start: today.addingTimeInterval(-1_800), end: today, workSeconds: 1_800, threadID: thread))
        var problems: [String] = []
        for _ in 0..<3 {
            expect(archive.currentStreak() == 2 && archive.bestStreak() == 2,
                   "initial streak queries disagree", &problems)
            expectClose(archive.workSeconds(on: today), 1_800, "initial day work", &problems)
            expect(archive.threadCount(on: today) == 1, "initial day count", &problems)
            _ = archive.longestThread(on: today)
        }
        archive.rename(thread: thread, to: "Renamed")
        expect(archive.longestThread(on: today)?.name == "Renamed",
               "a warmed query retained the old name", &problems)
        archive.setWorkType(.breakTime, forThread: thread)
        expectClose(archive.workSeconds(on: today), 0, "Break correction kept cached focus", &problems)
        expect(archive.currentStreak() == 1 && archive.bestStreak() == 1,
               "Break correction kept a cached streak", &problems)
        archive.append(SessionRecord(name: "New today", workType: .deepWork,
            start: today, end: today.addingTimeInterval(1_800), workSeconds: 1_800))
        expect(archive.records.count == 2 && archive.currentStreak() == 1 && archive.bestStreak() == 1,
               "capacity eviction retained yesterday's cached contribution", &problems)
        expectClose(archive.workSeconds(on: yesterday), 0, "evicted day retained cached work", &problems)
        return problems
    }

    private static func liveDashboardMatchesFullRefresh() -> [String] {
        MainActor.assumeIsolated {
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            guard let fixture = makeStore(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            fixture.engine.start(workType: .deepWork, intent: "Live day")
            fixture.store.tracker?.appActivated(bundleID: "editor", name: "Editor")
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            fixture.store.setDashboardVisible(true)
            let fullGeneration = fixture.store.dashboardArchiveReadModelGeneration
            clock.advance(80)
            fixture.store.updateTimeDrivenFigures()
            var problems: [String] = []
            expect(fixture.store.dashboardArchiveReadModelGeneration == fullGeneration,
                   "a live day rebuilt stable dashboard history", &problems)
            let tracked = fixture.store.trackedForSelectedDay
            let appTotal = fixture.store.rankedApps.reduce(0) { $0 + $1.total }
            let worked = fixture.store.daySessions.reduce(0.0) { total, entry in
                if case .session(let session) = entry { return total + session.worked }
                return total
            }
            expectClose(tracked, 80, "live day tracked value", &problems)
            expectClose(appTotal, tracked, "live day app rows", &problems)
            expectClose(worked, 80, "day digest used the wall clock instead of the injected clock", &problems)
            fixture.store.refreshDashboard()
            expectClose(fixture.store.trackedForSelectedDay, tracked, "full/live tracked parity", &problems)
            expectClose(fixture.store.rankedApps.reduce(0) { $0 + $1.total }, appTotal,
                        "full/live app parity", &problems)
            return problems
        }
    }

    private static func visiblePeriodFollowsLiveEvidence() -> [String] {
        MainActor.assumeIsolated {
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            guard let fixture = makeStore(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            let start = clock.value
            fixture.store.setDashboardVisible(true)
            fixture.store.setReviewVisible(true)
            fixture.engine.start(workType: .deepWork, intent: "Live period evidence")
            fixture.store.tracker?.appActivated(bundleID: "com.example.editor", name: "Editor")
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            fixture.store.refreshReview(period: .week)
            let stableHistoryGeneration = fixture.store.historyIndexGeneration
            clock.advance(125)
            fixture.store.updateTimeDrivenFigures()
            var problems: [String] = []
            expectClose(fixture.store.reviewSummary.tracked, 125,
                        "Week bars/average consume the uncheckpointed live tail", &problems)
            expectClose(fixture.store.historyDays.first?.focused ?? -1, 125,
                        "An open History sheet advances running work with Day", &problems)
            expect(fixture.store.historyIndexGeneration == stableHistoryGeneration,
                   "Live ticker rebuilt stable all-history indexing instead of patching today", &problems)
            let id = UUID()
            fixture.usage.checkpoint(AppUsageSession(id: id, bundleID: "com.example.previous",
                                                      appName: "Previous", start: start.addingTimeInterval(-1_200),
                                                      end: start.addingTimeInterval(-600)))
            let count = fixture.usage.sessions.count
            fixture.usage.checkpoint(AppUsageSession(id: id, bundleID: "com.example.previous",
                                                      appName: "Previous", start: start.addingTimeInterval(-1_200),
                                                      end: start.addingTimeInterval(-300)))
            expect(fixture.usage.sessions.count == count,
                   "The mutation fixture must replace, not append, a record", &problems)
            expectClose(fixture.store.reviewSummary.tracked, 1_025,
                        "Visible Review reacts to a direct same-count archive mutation", &problems)
            return problems
        }
    }

    /// Catches `record.id == threadID` colliding with the same thread's live
    /// projection in History detail.
    private static func historyDetailKeepsLegacyAndLiveIdentity() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            guard let fixture = makeStore(clock) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            let identity = UUID()
            fixture.engine.archive.append(SessionRecord(
                id: identity, name: "Legacy", workType: .deepWork,
                start: clock.value.addingTimeInterval(-1_200),
                end: clock.value.addingTimeInterval(-600), workSeconds: 600,
                threadID: identity))
            fixture.engine.start(workType: .deepWork, intent: "Legacy", threadID: identity)
            clock.advance(45)
            fixture.store.refreshReview(period: .week)
            let entries = fixture.store.reviewDayDetail(for: clock.value)?.focusEntries ?? []
            expect(entries.count == 2 && Set(entries.map(\.id)).count == 2,
                   "History detail gave legacy and live stretches the same row identity", &problems)
            expect(entries.contains(where: { $0.sourceRecordID == identity })
                    && entries.contains(where: { $0.sourceRecordID == nil }),
                   "History detail did not retain archive provenance beside the live namespace", &problems)
            return problems
        }
    }

    /// Catches a session/disclosure helper reading only durable usage while the
    /// Story rail reads the tracker overlay for that same visit.
    private static func appRanksUseEffectiveLiveUsage() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            guard let fixture = makeStore(clock) else {
                return ["could not create isolated preferences suite"]
            }
            defer { fixture.cleanUp() }
            fixture.store.tracker?.appActivated(bundleID: "com.example.editor", name: "Editor")
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            clock.advance(45)
            let bounds = DateInterval(start: clock.value.addingTimeInterval(-45), end: clock.value)
            expectClose(fixture.store.appRanks(within: [bounds]).first?.total ?? -1, 45,
                        "first uncheckpointed visit is absent from session app ranks", &problems)
            fixture.store.tracker?.flush()
            clock.advance(30)
            let extended = DateInterval(start: clock.value.addingTimeInterval(-75), end: clock.value)
            expectClose(fixture.store.appRanks(within: [extended]).first?.total ?? -1, 75,
                        "post-checkpoint live tail is absent from session app ranks", &problems)
            return problems
        }
    }

    /// A capacity-sized test that asserts actual visible read-model behaviour:
    /// unchanged idle ticks must not publish new dashboard/Review generations.
    private static func idleTicksDoNotRebuildCapacityReadModels() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(date(2026, 8, 19, 12, 0))
            let sessionDirectory = scratchDirectory()
            let usageDirectory = scratchDirectory()
            let suiteName = "com.prabesh.daybook.story-capacity.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                return ["could not create isolated capacity preferences"]
            }
            defer {
                defaults.removePersistentDomain(forName: suiteName)
                try? FileManager.default.removeItem(at: sessionDirectory)
                try? FileManager.default.removeItem(at: usageDirectory)
            }
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: clock.value)
            var records: [SessionRecord] = []
            var usage: [AppUsageSession] = []
            for offset in 0..<200 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: day) else { continue }
                for index in 0..<25 {
                    let start = date.addingTimeInterval(Double(8 * 3_600 + index * 900))
                    records.append(SessionRecord(name: "Work", workType: .deepWork,
                                                 start: start, end: start.addingTimeInterval(600),
                                                 workSeconds: 600))
                }
                for index in 0..<100 {
                    let start = date.addingTimeInterval(Double(8 * 3_600 + index * 240))
                    usage.append(AppUsageSession(bundleID: "com.example.editor\(index % 5)",
                                                 appName: "Editor", start: start,
                                                 end: start.addingTimeInterval(180)))
                }
            }
            struct Envelope: Codable { let metadata: AppUsageMetadata; let sessions: [AppUsageSession] }
            do {
                try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: usageDirectory, withIntermediateDirectories: true)
                try JSONEncoder().encode(records).write(to: sessionDirectory.appendingPathComponent("sessions.json"))
                try JSONEncoder().encode(Envelope(metadata: .init(accurateFrom: day.addingTimeInterval(-201 * 86_400)),
                                                   sessions: usage))
                    .write(to: usageDirectory.appendingPathComponent("app-usage.json"))
            } catch { return ["Could not seed capacity fixture: \(error)"] }
            let archive = SessionArchive(directory: sessionDirectory, now: { clock.value })
            let usageArchive = AppUsageArchive(directory: usageDirectory, now: { clock.value })
            guard archive.records.count == 5_000, usageArchive.sessions.count == 20_000 else {
                return ["Capacity fixture did not load the required record counts"]
            }
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "com.example.capacity", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usageArchive, ownBundleID: "com.example.capacity",
                                          idle: .disabled, now: { clock.value })
            // The check ticks the store itself. A live ticker would fall due
            // during a slow (-Onone) rebuild, sample the build Mac's real HID
            // idle, and close the tracker's open stretch before the live tick.
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usageArchive)
            store.setDashboardVisible(true)
            store.setReviewVisible(true)
            store.refreshReview(period: .month)
            let dashboardGeneration = store.dashboardReadModelGeneration
            let reviewGeneration = store.reviewReadModelGeneration
            let began = Date()
            store.updateTimeDrivenFigures()
            store.updateTimeDrivenFigures()
            store.updateTimeDrivenFigures()
            let elapsed = Date().timeIntervalSince(began)
            expect(store.dashboardReadModelGeneration == dashboardGeneration
                    && store.reviewReadModelGeneration == reviewGeneration,
                   "unchanged idle ticks rebuilt capacity-sized dashboard or History read models", &problems)
            store.tracker?.appActivated(bundleID: "com.example.live", name: "Live editor")
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            let historyGeneration = store.historyIndexGeneration
            let fullDashboardGeneration = store.dashboardArchiveReadModelGeneration
            let trackedBeforeLiveTick = store.reviewSummary.tracked
            clock.advance(1)
            let liveBegan = Date()
            store.updateTimeDrivenFigures()
            let liveElapsed = Date().timeIntervalSince(liveBegan)
            expect(store.historyIndexGeneration == historyGeneration,
                   "capacity live tick rebuilt stable all-history indexing", &problems)
            expect(store.dashboardArchiveReadModelGeneration == fullDashboardGeneration,
                   "capacity live tick rebuilt stable dashboard history", &problems)
            expect(store.reviewSummary.tracked > trackedBeforeLiveTick,
                   "capacity live tick did not advance current Review evidence", &problems)
            Diagnostics.log("Story capacity idle ticks \(elapsed)s; live tick \(liveElapsed)s")
            return problems
        }
    }

    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-story-accounting-\(UUID().uuidString)", isDirectory: true)
    }

    private static func makeStore(_ clock: TestClock,
                                  calendar: Calendar = .current)
        -> (store: SessionStore, engine: SessionEngine, usage: AppUsageArchive, cleanUp: () -> Void)? {
        let sessionDirectory = scratchDirectory()
        let usageDirectory = scratchDirectory()
        let suiteName = "com.prabesh.daybook.story-accounting.\(UUID().uuidString)"
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

    private static func runningWorkStaysConsistentAcrossScopes() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let start = date(2026, 8, 19, 12, 0, calendar: calendar)
            let clock = TestClock(start)
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
            let clock = TestClock(anchor)
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
            let clock = TestClock(anchor)
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
            let clock = TestClock(anchor)
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
            let clock = TestClock(date(2026, 8, 19, 12, 0, calendar: calendar))
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
            let clock = TestClock(start)
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
            let clock = TestClock(anchor)
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
