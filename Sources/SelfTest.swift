import Foundation
import SwiftUI

/// Headless logic tests (§7). Pure state-machine and time arithmetic with an
/// injected clock — no UI, no notifications, no run loop.
enum SelfTest {

    private final class Clock {
        var value: Date
        init(_ start: Date) { value = start }
        func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
    }

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let suiteName = "com.prabesh.focuscontinuity.selftest"

    /// A scratch directory per archive so tests never touch real history.
    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-selftest-\(UUID().uuidString)", isDirectory: true)
    }

    private static func makeArchive(_ clock: Clock) -> SessionArchive {
        SessionArchive(directory: scratchDirectory(), now: { clock.value })
    }

    private static func makeEngine(_ clock: Clock) -> SessionEngine {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        return SessionEngine(store: store,
                             archive: makeArchive(clock),
                             ownBundleID: FocusConstants.bundleIdentifier,
                             schedulesDwell: false,
                             now: { clock.value })
    }

    /// "Now", moved to noon when the real clock is within three hours of
    /// midnight, so fixtures built as "two hours ago, today" stay inside today.
    /// Tests 87 and 94 failed at 00:45 because their earlier stretches fell on
    /// yesterday and only the after-midnight share counted.
    private static func anchoredNow() -> Date {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        return now.timeIntervalSince(dayStart) < 3 * 3_600 ? dayStart.addingTimeInterval(12 * 3_600) : now
    }

    private static func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Runner

    static func run() -> Bool {
        var failures: [String] = []
        var passed = 0
        let tests: [(String, () -> [String])] = [
            ("Elapsed maths across two pause cycles", testElapsedWithPauseCycles),
            ("Debounce: 3s away is discarded", testDebounce),
            ("Micro-break: 8m away accumulates silently", testMicroBreak),
            ("Extended break: 22m away awaits a decision", testExtendedBreak),
            ("Merge Time credits exactly the away duration", testMergeVersusContinue),
            ("Category precedence: override beats built-in map", testCategoryPrecedence),
            ("Coalescing: lock+sleep+unlock+wake resolves once", testCoalescing),
            ("Negative clock skew clamps to zero", testClockSkew),
            ("Codable round-trip of persisted state", testCodableRoundTrip),
            ("Exhaustive transition table is total", testExhaustiveTransitions),
            ("Restore across a 22m gap escalates to a decision", testRestoreWithGap),
            ("Dwell guard: leaving the break app cancels the pause", testDwellCancellation),
            ("Pure helpers: title format, archive ring, defaults", testPureHelpers),
            ("Decision accounting: deliberation and Reset are honest", testDecisionAccounting),
            ("Archive queries: today, sessions, longest, week bars", testArchiveQueries),
            ("Streak rule: 25m minimum, yesterday still counts", testStreakRule),
            ("Archive survives reload; corrupt file moved aside", testArchivePersistence),
            ("Quick starts ranked by frequency then recency", testQuickStarts),
            ("Discrete sessions: start/stop writes honest records", testDiscreteSessions),
            ("Away inside a session is excluded from its record", testAwayInsideSession),
            ("Engine publishes state changes to observers", testEngineNotifiesObservers),
            ("App usage tracker segments and merges correctly", testUsageTracker),
            ("Periodic usage checkpoints roll back an idle tail", testPeriodicCheckpointRollsBackIdleTail),
            ("Legacy app usage migration preserves history", testLegacyUsageMigrationPreservesHistory),
            ("Usage checkpoints replace records by identity", testUsageCheckpointReplacesByIdentity),
            ("Most-used apps ranked with recent sessions", testMostUsedApps),
            ("History formatters: ago, range, spent", testHistoryFormatters),
            ("Dashboard: timeline order, colour index, rankings", testDashboardTimeline),
            ("Dashboard: usage clipped across midnight", testTimelineClipsAcrossMidnight),
            ("Dashboard: focus quality and running apps", testFocusQualityAndRunning),
            ("Dashboard: insights are gated, never fabricated", testInsightGating),
            ("Defects B-2/B-3: running session counts everywhere", testRunningSessionCountsEverywhere),
            ("Idle time is trimmed from app usage", testIdleTrimsUsage),
            ("Precise durations and session-count consistency", testPreciseDurationAndConsistency),
            ("Window snaps to hours with a four-hour floor", testWindowSnappingAndStretches),
            ("End reasons recorded; legacy records still decode", testEndReasonsAndMigration),
            ("Session grouping: detours join, breaks split", testSessionGrouping),
            ("Hourly buckets split across the hour boundary", testHourlyBuckets),
            ("G-1: an all-zero week chart reports no data", testWeekChartEmptyRule),
            ("Break reminder: continuous work, resets, and quiet periods", testBreakReminder),
            ("Timeline layout: clusters, elision, and mapping", testTimelineLayout),
            ("Insight copy names the measure; Finder is not listed", testInsightCopyAndRunningFilter),
            ("Sleep and wake: labels are honest, no work is lost", testSleepWakeTracking),
            ("Period rollups: bounds, active-day average, empty period", testPeriodStats),
            ("Period log: grouped, reverse chronological, day-scoped", testPeriodLog),
            ("App purpose: static map, ambiguity, overrides", testAppPurpose),
            ("App purpose: focused set and session kind", testSessionKind),
            ("Input density: active, passive and absent", testInputDensity),
            ("Input density: ring is bounded, absence clears it", testInputDensityRing),
            ("Threads: records carry a thread, legacy JSON decodes", testThreadIdentity),
            ("Threads: continuing reuses the thread, starting fresh does not",
             testThreadContinuity),
            ("Threads: grouped, summed, ordered, running included", testThreadSummaries),
            ("Threads: primary app by purpose, side apps above the floor", testThreadApps),
            ("Continue: a thread resumes with its name, type and link",
             testContinueThread),
            ("Focus score: media veto, activity weight, churn penalty", testFocusScore),
            ("Daily goal: share, personal median, honest nil", testDailyGoal),
            ("Auto sessions: sustained start, backdating, pause then end",
             testAutoSessionDetector),
            ("Auto sessions: a score drifting mid-band never flaps",
             testAutoSessionHysteresis),
            ("Rewards: gated on real data, capped, cooled down", testRewardEngine),
            ("C1: a manual session cannot leave a stale qualifying run behind",
             testNoStaleQualifyingRun),
            ("Start continues matching work; the lock screen is never an app",
             testAdoptAndSystemProcesses),
            ("Learning: corrections move the threshold, one answer does not",
             testPurposeLearner),
            ("Log grouping: one row per app, totals and shares add up",
             testLogAppGroups),
            ("An unanswered away card excludes the gap and keeps running",
             testUnansweredAwayIsHonest),
            ("Marking yourself away pauses without restarting the pause clock",
             testManualAway),
            ("A night-long absence ends the session where the user left",
             testLongAwayEndsSession),
            ("Cross-midnight work is split between its days, not heaped on one",
             testDayAttribution),
            ("A refused flush keeps its seconds; the day total filters and clips",
             testFlushAndTotalToday),
            ("Break tiers: 20/50/90 thresholds, escalation, app-aware wording",
             testBreakTiers),
            ("A recorded break explains the gap without counting as focus",
             testRecordedBreak),
            ("Idle past ten minutes pauses backdated; typing resumes only that",
             testIdleAutoPause),
            ("The goal counts only declared work you were actually doing",
             testFocusedActiveTime),
            ("Away closes the session where you left and reopens on return",
             testAwayEndsSession),
            ("'Now' reports the current stretch, not process uptime",
             testRunningStretch),
            ("The popover fits the screen it opens on", testPopoverMetrics),
            ("The menu bar stays on today when the dashboard browses back",
             testGlanceStaysToday),
            ("A second absence during the away card is never work",
             testShadowAwayIsNotWork),
            ("An unlocked absence past the cap still ends the session",
             testUnlockedAbsenceEndsSession),
            ("Hands-on time inside a paused session cannot fill the goal",
             testGoalDistractionCap),
            ("A night that began idle and then locked still ends the session",
             testIdleThenLockedNightEndsSession),
            ("A second absence the card sat through survives a relaunch",
             testShadowAwaySurvivesRelaunch),
            ("Sessions, Focused and Longest follow the selected day",
             testDayScopedSessionFigures),
            ("Palette: seven distinct app colours, both appearances, total work types",
             testPalette),
            ("Menu-bar glyph renders a template ring for every state", testMenuBarGlyph),
            ("Settings model writes through and notifies once per change", testSettingsModel),
            ("Previous-period total is the same rollup one period back",
             testPreviousPeriodTracked),
            ("The popover still fits a 13\" screen with the away card up",
             testPopoverStillFits13Inch),
            ("Away prompt tier is a pure rule; Never means quick", testAwayPromptTier),
            ("Pending away range spans the absence and ends at return", testPendingAwayRange),
            ("The hero clock is the thread's, picking up after a break", testThreadClock),
            ("Coming back in a different app starts new work; same app continues",
             testAppAwareContinuity),
            ("Rhythm: segments split across hours, dominant app per hour, peak run",
             testRhythm),
            ("A named break is recorded under that name; other answers ignore it",
             testNamedBreak),
            ("Day digest: stretches fold by thread, breaks sit between, running joins",
             testSessionDigest),
            ("Apps within a session's spans: intersected, ranked, shares of the inside",
             testAppsWithinSpans),
            ("Summary text: every clause gated on its figure; empty days say so",
             testSummaryText),
            ("Sessions are threads: stretches of one thread count once, running included",
             testSessionsAreThreads),
            ("An absence is measured from where it began, not from a late idle pause",
             testAbsenceFromWhereItBegan),
            ("Relaunched behind a lock, the absence stays open until the unlock",
             testRestoreBehindLock),
            ("The menu bar's band stays on today while the dashboard browses",
             testGlanceStaysOnToday),
            ("Watching is presence: quiet pause, written down, never asked about; meetings count",
             testWatchingIsNotAbsence),
            ("Quiet while a question is pending is an absence the card sat through",
             testQuietWhileAwaiting),
            ("Declared categories are a last resort; automatic sessions are named",
             testCategoryFallbackAndNames),
            ("A wake is the machine's: only input or an unlock ends an absence",
             testWakeIsNotAReturn)
        ]

        print("FocusContinuity self-test")
        for (index, test) in tests.enumerated() {
            let problems = test.1()
            let number = index < 9 ? " \(index + 1)" : "\(index + 1)"
            if problems.isEmpty {
                passed += 1
                print("  [PASS] \(number). \(test.0)")
            } else {
                print("  [FAIL] \(number). \(test.0)")
                for problem in problems {
                    print("         - \(problem)")
                    failures.append("\(index + 1): \(problem)")
                }
            }
        }
        cleanUp()
        print("\(passed)/\(tests.count) passed")
        return failures.isEmpty
    }

    private static func expect(_ condition: Bool,
                               _ message: @autoclosure () -> String,
                               _ problems: inout [String]) {
        if !condition { problems.append(message()) }
    }

    private static func expectClose(_ actual: TimeInterval,
                                    _ expected: TimeInterval,
                                    _ label: String,
                                    _ problems: inout [String]) {
        if abs(actual - expected) > 0.001 {
            problems.append("\(label): expected \(expected), got \(actual)")
        }
    }

    // MARK: - 1

    private static func testElapsedWithPauseCycles() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        clock.advance(600)
        engine.transition(on: .manualPause)
        clock.advance(120)
        engine.transition(on: .manualResume)
        clock.advance(300)
        engine.transition(on: .manualPause)
        clock.advance(60)
        engine.transition(on: .manualResume)
        clock.advance(100)

        expectClose(engine.elapsed, 1000, "elapsed", &problems)
        expectClose(engine.totalPausedDuration, 180, "totalPaused", &problems)
        expect(engine.state == .running, "state should be running", &problems)
        return problems
    }

    // MARK: - 2

    private static func testDebounce() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        clock.advance(100)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(3)
        engine.transition(on: .awayEnded)

        expectClose(engine.totalPausedDuration, 0, "totalPaused", &problems)
        expectClose(engine.elapsed, 103, "elapsed", &problems)
        expect(engine.state == .running, "state should stay running", &problems)
        return problems
    }

    // MARK: - 3

    private static func testMicroBreak() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        var decisions = 0
        engine.onNeedsDecision = { _, _ in decisions += 1 }

        engine.transition(on: .launch)
        clock.advance(60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(480)
        engine.transition(on: .awayEnded)

        expectClose(engine.totalPausedDuration, 480, "totalPaused", &problems)
        expectClose(engine.elapsed, 60, "elapsed", &problems)
        expect(engine.state == .running, "state should stay running", &problems)
        expect(decisions == 0, "no alert should be raised for a micro-break", &problems)
        return problems
    }

    // MARK: - 4

    private static func testExtendedBreak() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        var raised: TimeInterval?
        engine.onNeedsDecision = { away, _ in raised = away }

        engine.transition(on: .launch)
        clock.advance(60)
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        clock.advance(1320)
        engine.transition(on: .awayEnded)

        if case .awaitingUserDecision(let away, _) = engine.state {
            expectClose(away, 1320, "away", &problems)
        } else {
            problems.append("state should be awaitingUserDecision, got \(engine.state)")
        }
        expectClose(raised ?? -1, 1320, "raised alert away", &problems)

        // Events arriving while the alert is up are recorded but never transition
        // (D10), and must not leave a stale away interval behind after the answer.
        engine.transition(on: .awayBegan(trigger: .screenLock))
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        expect(engine.state != .running, "events during the alert must not resume", &problems)
        engine.transition(on: .decision(.mergeTime))
        clock.advance(10)
        engine.transition(on: .awayEnded)
        expect(engine.state == .running, "state should be running after the decision", &problems)
        expectClose(engine.totalPausedDuration, 0, "totalPaused after a stale interval", &problems)
        return problems
    }

    // MARK: - 5

    private static func testMergeVersusContinue() -> [String] {
        var problems: [String] = []
        let away: TimeInterval = 1320

        func elapsedAfter(_ decision: UserDecision) -> TimeInterval {
            let clock = Clock(base)
            let engine = makeEngine(clock)
            engine.transition(on: .launch)
            clock.advance(60)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)
            engine.transition(on: .decision(decision))
            return engine.elapsed
        }

        let merged = elapsedAfter(.mergeTime)
        let continued = elapsedAfter(.continueSession)

        expectClose(merged, 60 + away, "merged elapsed", &problems)
        // Continue now closes the old session where the user left and opens a
        // new one at the moment of return, so its clock starts from zero rather
        // than carrying the pre-away work forward. The two are no longer
        // comparable as one minus the other.
        expectClose(continued, 0, "continue starts a fresh clock", &problems)
        return problems
    }

    // MARK: - 6

    private static func testCategoryPrecedence() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        let terminal = "com.apple.Terminal"

        expect(engine.categories.category(for: terminal) == .work,
               "built-in map should classify Terminal as work", &problems)
        engine.categories.setOverride(.breakTime, for: terminal)
        expect(engine.categories.category(for: terminal) == .breakTime,
               "override should beat the built-in map", &problems)
        engine.categories.clearOverride(for: terminal)
        expect(engine.categories.category(for: terminal) == .work,
               "clearing the override should fall back to the built-in map", &problems)
        expect(engine.categories.category(for: "com.example.unknown") == .neutral,
               "unknown bundle identifiers should be neutral", &problems)
        expect(engine.categories.category(for: nil) == .neutral,
               "a nil bundle identifier should be neutral", &problems)
        return problems
    }

    // MARK: - 7

    private static func testCoalescing() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        clock.advance(100)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(5)
        engine.transition(on: .awayBegan(trigger: .systemSleep))   // ignored
        clock.advance(595)
        engine.transition(on: .awayEnded)                          // resolves once
        engine.transition(on: .awayEnded)                          // idempotent

        expectClose(engine.totalPausedDuration, 600, "totalPaused", &problems)
        expect(engine.state == .running, "state should stay running", &problems)
        return problems
    }

    // MARK: - 8

    private static func testClockSkew() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        // A pause that ends "before" it began must contribute 0, not a negative
        // duration. Without the clamp in `interval(from:)` this accumulates -50
        // and inflates elapsed, so the assertion below fails.
        engine.transition(on: .launch)
        clock.advance(100)
        engine.transition(on: .manualPause)
        clock.value = base.addingTimeInterval(50)      // clock jumps backwards
        engine.transition(on: .manualResume)
        expectClose(engine.totalPausedDuration, 0, "totalPaused after a backwards pause",
                    &problems)

        // Same for an away interval resolved against a backwards clock.
        clock.value = base.addingTimeInterval(200)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.value = base.addingTimeInterval(150)
        engine.transition(on: .awayEnded)
        expectClose(engine.totalPausedDuration, 0, "totalPaused after a backwards away",
                    &problems)
        expect(engine.state == .running, "state should stay running", &problems)

        clock.value = base.addingTimeInterval(-500)    // before the session start
        expectClose(engine.elapsed, 0, "elapsed", &problems)
        return problems
    }

    // MARK: - 9

    private static func testCodableRoundTrip() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.sessionName = "Refactor"
        engine.transition(on: .launch)
        clock.advance(300)
        engine.transition(on: .appActivated(bundleID: "com.spotify.client", name: "Spotify"))
        engine.transition(on: .dwellExpired(bundleID: "com.spotify.client"))

        let snapshot = engine.snapshot()
        do {
            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            expect(decoded == snapshot, "decoded snapshot should equal the original", &problems)
            expect(decoded.kind == .paused, "snapshot kind should be paused", &problems)
            expect(decoded.pauseBundleID == "com.spotify.client",
                   "snapshot should carry the distraction bundle id", &problems)

            let restoreClock = Clock(clock.value)
            let restored = makeEngine(restoreClock)
            restored.restore(from: decoded)
            expect(restored.state == .paused(reason: .distractionApp(bundleID: "com.spotify.client")),
                   "restored state should match, got \(restored.state)", &problems)
            expectClose(restored.elapsed, 300, "restored elapsed", &problems)
        } catch {
            problems.append("round-trip threw: \(error)")
        }
        return problems
    }

    // MARK: - 11

    /// D14 — the launch path. A snapshot written while running, reloaded after a
    /// gap longer than the threshold, must escalate exactly as a live wake would.
    private static func testRestoreWithGap() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.sessionName = "Refactor"
        engine.transition(on: .launch)
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        clock.advance(600)
        let snapshot = engine.snapshot()

        // Short gap: absorbed as a micro-break, session continues.
        let shortClock = Clock(clock.value.addingTimeInterval(120))
        let shortEngine = makeEngine(shortClock)
        var shortDecisions = 0
        shortEngine.onNeedsDecision = { _, _ in shortDecisions += 1 }
        shortEngine.restore(from: snapshot)
        expect(shortEngine.state == .running, "a 2m gap should stay running", &problems)
        expectClose(shortEngine.totalPausedDuration, 120, "gap absorbed", &problems)
        expect(shortDecisions == 0, "a 2m gap should raise no alert", &problems)

        // Long gap: escalates through the same extended-break path.
        let longClock = Clock(clock.value.addingTimeInterval(1_320))
        let longEngine = makeEngine(longClock)
        var raised: TimeInterval?
        longEngine.onNeedsDecision = { away, _ in raised = away }
        longEngine.restore(from: snapshot)
        if case .awaitingUserDecision(let away, let app) = longEngine.state {
            expectClose(away, 1_320, "restored away", &problems)
            expect(app == "Terminal", "restored lastApp should survive, got \(app)", &problems)
        } else {
            problems.append("a 22m gap should await a decision, got \(longEngine.state)")
        }
        expectClose(raised ?? -1, 1_320, "restored alert away", &problems)
        expect(longEngine.currentAppBundleID == "com.apple.Terminal",
               "restore should repopulate the bundle id", &problems)
        return problems
    }

    // MARK: - 12

    /// D6 — a dwell that fires after focus has moved on must not pause.
    private static func testDwellCancellation() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        engine.transition(on: .appActivated(bundleID: "com.spotify.client", name: "Spotify"))
        clock.advance(10)
        // Back to work before the 20s dwell elapses.
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        engine.transition(on: .dwellExpired(bundleID: "com.spotify.client"))
        expect(engine.state == .running, "a stale dwell must not pause, got \(engine.state)",
               &problems)

        // Staying put does pause, and a work app resumes immediately.
        engine.transition(on: .appActivated(bundleID: "com.spotify.client", name: "Spotify"))
        engine.transition(on: .dwellExpired(bundleID: "com.spotify.client"))
        expect(engine.state == .paused(reason: .distractionApp(bundleID: "com.spotify.client")),
               "dwelling on a break app should pause, got \(engine.state)", &problems)
        clock.advance(60)
        engine.transition(on: .appActivated(bundleID: "com.apple.finder", name: "Finder"))
        expect(engine.state.isPaused, "a neutral app must not resume (D5)", &problems)
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        expect(engine.state == .running, "a work app should resume", &problems)
        expectClose(engine.totalPausedDuration, 60, "pause accumulated on exit", &problems)
        return problems
    }

    // MARK: - 13

    private static func testPureHelpers() -> [String] {
        var problems: [String] = []

        // D15 title formatting.
        expect(Tokens.duration(0) == "0m", "0s should format as 0m", &problems)
        expect(Tokens.duration(900) == "15m", "900s should format as 15m", &problems)
        expect(Tokens.duration(8_100) == "2h 15m", "8100s should format as 2h 15m",
               &problems)
        expect(Tokens.duration(-5) == "0m", "negative input should format as 0m",
               &problems)

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()

        // D9 — a missing key must read as 15m, not as a zero-second threshold.
        expectClose(store.breakThreshold, FocusConstants.defaultThreshold,
                    "default threshold", &problems)

        // The archive ring caps at capacity, dropping the oldest entries.
        let clock = Clock(base.addingTimeInterval(60))
        let dir = scratchDirectory()
        let ring = SessionArchive(directory: dir, now: { clock.value })
        let overflow = FocusConstants.archiveCapacity + 10
        for index in 0..<overflow {
            ring.append(SessionRecord(name: "s\(index)", workType: .deepWork,
                                      start: base, end: base.addingTimeInterval(60),
                                      workSeconds: Double(index)))
        }
        expect(ring.records.count == FocusConstants.archiveCapacity,
               "ring should cap at \(FocusConstants.archiveCapacity), got \(ring.records.count)",
               &problems)
        expect(ring.records.first?.name == "s10",
               "ring should drop the oldest, got \(ring.records.first?.name ?? "nil")", &problems)
        expect(ring.sessionsToday() == FocusConstants.archiveCapacity,
               "all surviving records end on the same day", &problems)
        clock.value = base.addingTimeInterval(86_400 * 5)
        expect(ring.sessionsToday() == 0, "no records end five days later", &problems)
        try? FileManager.default.removeItem(at: dir)

        // A corrupt blob is discarded rather than crashing or wedging the app.
        defaults.set(Data("not json".utf8), forKey: "fc.state")
        expect(store.loadState() == nil, "corrupt state should decode as nil", &problems)
        expect(defaults.data(forKey: "fc.state") == nil,
               "corrupt state should be cleared from defaults", &problems)

        store.removeAll()
        return problems
    }

    // MARK: - 14

    /// The card blocks nothing, so the minutes that pass while it is up are
    /// ordinary working minutes and are credited — except under "Start fresh",
    /// where they belong to the session that starts on return rather than to the
    /// one that ended when the user walked away.
    private static func testDecisionAccounting() -> [String] {
        var problems: [String] = []
        let deliberation: TimeInterval = 300
        let away: TimeInterval = 1_320
        let work: TimeInterval = 60

        /// Drives a session to the decision point, waits `deliberation`, answers.
        func engineAfter(_ decision: UserDecision) -> SessionEngine {
            let clock = Clock(base)
            let engine = makeEngine(clock)
            engine.sessionName = "Refactor"
            engine.transition(on: .launch)
            clock.advance(work)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)
            clock.advance(deliberation)
            engine.transition(on: .decision(decision))
            return engine
        }

        let merged = engineAfter(.mergeTime)
        expectClose(merged.elapsed, work + away + deliberation,
                    "merge counts the away and the time since", &problems)

        let continued = engineAfter(.continueSession)
        expectClose(continued.elapsed, deliberation,
                    "continue starts fresh at the moment of return", &problems)

        let reset = engineAfter(.resetTimer)
        expect(reset.state == .running, "reset should leave a running session", &problems)
        // Not zero: the new session began when they came back, not when they
        // reached for the button.
        expectClose(reset.elapsed, deliberation, "fresh session dates from the return",
                    &problems)
        if let archived = reset.archive.records.last {
            expectClose(archived.workSeconds, work,
                        "archived work excludes both the break and the time since", &problems)
            expect(archived.name == "Refactor", "archived name, got \(archived.name)", &problems)
            // The old session stopped when the user walked away. Stamping it
            // `now()` drew it straight through the gap on the day timeline.
            expectClose(archived.end.timeIntervalSince(archived.start), work + 0,
                        "archived span ends where the away began", &problems)
        } else {
            problems.append("reset should archive the previous session")
        }

        // The manual escape hatch behaves like Continue Session.
        let clock = Clock(base)
        let escaped = makeEngine(clock)
        escaped.transition(on: .launch)
        clock.advance(work)
        escaped.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(away)
        escaped.transition(on: .awayEnded)
        clock.advance(deliberation)
        escaped.transition(on: .manualResume)
        expect(escaped.state == .running, "manual resume must escape the decision state",
               &problems)
        expectClose(escaped.elapsed, deliberation,
                    "the manual escape behaves like 'I was away': a fresh clock "
                    + "from the moment of return", &problems)
        return problems
    }

    // MARK: - 15

    private static func testArchiveQueries() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })

        for minutes in [20.0, 50.0, 20.0] {
            archive.append(SessionRecord(name: "s", workType: .deepWork,
                                         start: clock.value,
                                         end: clock.value.addingTimeInterval(minutes * 60),
                                         workSeconds: minutes * 60))
        }
        expectClose(archive.todayTotal(), 90 * 60, "todayTotal", &problems)
        expect(archive.sessionsToday() == 3,
               "sessionsToday should be 3, got \(archive.sessionsToday())", &problems)
        expectClose(archive.longestToday(), 50 * 60, "longestToday", &problems)

        let bars = archive.weekBars()
        expect(bars.count == 7, "weekBars should have 7 entries, got \(bars.count)", &problems)
        expect(bars.last?.isToday == true, "last bar should be today", &problems)
        expect(bars.last?.minutes == 90,
               "today should be 90 minutes, got \(bars.last?.minutes ?? -1)", &problems)
        expect(bars.dropLast().allSatisfy { $0.minutes == 0 },
               "earlier days should be empty", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 16

    private static func testStreakRule() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })
        let day: TimeInterval = 86_400

        func add(daysAgo: Int, minutes: Double) {
            let start = clock.value.addingTimeInterval(-Double(daysAgo) * day)
            archive.append(SessionRecord(name: "s", workType: .deepWork,
                                         start: start,
                                         end: start.addingTimeInterval(minutes * 60),
                                         workSeconds: minutes * 60))
        }

        add(daysAgo: 0, minutes: 30)
        add(daysAgo: 1, minutes: 30)
        add(daysAgo: 2, minutes: 10)   // below the 25m bar — breaks the chain
        add(daysAgo: 3, minutes: 60)
        expect(archive.currentStreak() == 2,
               "streak should be 2, got \(archive.currentStreak())", &problems)

        // A streak ending yesterday still shows today, before today's first session.
        let dir2 = scratchDirectory()
        let archive2 = SessionArchive(directory: dir2, now: { clock.value })
        let yesterday = clock.value.addingTimeInterval(-day)
        archive2.append(SessionRecord(name: "s", workType: .deepWork,
                                      start: yesterday,
                                      end: yesterday.addingTimeInterval(1_800),
                                      workSeconds: 1_800))
        expect(archive2.currentStreak() == 1,
               "yesterday-only streak should be 1, got \(archive2.currentStreak())", &problems)

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir2)
        return problems
    }

    // MARK: - 17

    private static func testArchivePersistence() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()

        let first = SessionArchive(directory: dir, now: { clock.value })
        first.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                   start: base, end: base.addingTimeInterval(600),
                                   workSeconds: 600, detectedApp: "com.apple.Terminal"))

        let second = SessionArchive(directory: dir, now: { clock.value })
        expect(second.records.count == 1, "record should survive a reload", &problems)
        expect(second.records.first?.name == "Refactor", "name should survive", &problems)
        expect(second.records.first?.detectedApp == "com.apple.Terminal",
               "detected app should survive", &problems)

        try? Data("not json".utf8).write(to: dir.appendingPathComponent("sessions.json"))
        let third = SessionArchive(directory: dir, now: { clock.value })
        expect(third.records.isEmpty, "corrupt store should start empty", &problems)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        expect(files.contains { $0.hasPrefix("sessions-corrupt-") },
               "corrupt file should be renamed aside, saw \(files)", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 18

    private static func testQuickStarts() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })

        func add(_ name: String, _ type: WorkType, count: Int) {
            for _ in 0..<count {
                archive.append(SessionRecord(name: name, workType: type,
                                             start: clock.value, end: clock.value,
                                             workSeconds: 600))
            }
        }
        add("Refactor", .deepWork, count: 3)
        add("Standup", .meetings, count: 2)
        add("Email", .admin, count: 1)
        // Empty intents never become quick starts.
        add("", .deepWork, count: 5)
        // Anything outside the window is ignored.
        let old = clock.value.addingTimeInterval(-30 * 86_400)
        archive.append(SessionRecord(name: "Ancient", workType: .learning,
                                     start: old, end: old, workSeconds: 600))

        let quick = archive.quickStarts(limit: 7)
        expect(quick.count == 3, "3 distinct pairs, got \(quick.count)", &problems)
        expect(quick.first?.name == "Refactor",
               "most frequent first, got \(quick.first?.name ?? "nil")", &problems)
        expect(quick.first?.workType == .deepWork, "work type should ride along", &problems)
        expect(!quick.contains { $0.name == "Ancient" }, "stale entries excluded", &problems)
        expect(archive.quickStarts(limit: 2).count == 2, "limit respected", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 19

    private static func testDiscreteSessions() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Refactor")
        expect(engine.state == .running, "start should run, got \(engine.state)", &problems)
        clock.advance(1_500)
        engine.transition(on: .manualPause)
        clock.advance(300)
        engine.transition(on: .manualResume)
        clock.advance(600)
        engine.stop()

        expect(engine.state == .idle, "stop should idle, got \(engine.state)", &problems)
        guard let record = engine.archive.records.last else {
            problems.append("stop should write a record")
            return problems
        }
        expectClose(record.workSeconds, 2_100, "paused time excluded from the record", &problems)
        expect(record.name == "Refactor", "record keeps the intent, got \(record.name)", &problems)
        expect(record.workType == .deepWork, "record keeps the work type", &problems)
        expectClose(engine.archive.todayTotal(), 2_100, "today total", &problems)

        engine.start(workType: .admin, intent: "Email")
        clock.advance(600)
        engine.stop()
        expectClose(engine.archive.todayTotal(), 2_700, "two sessions sum", &problems)
        expect(engine.archive.sessionsToday() == 2, "two sessions counted", &problems)
        expect(engine.archive.records.last?.workType == .admin, "second work type", &problems)

        // Starting while running archives the first rather than losing it.
        engine.start(workType: .learning, intent: "Read")
        clock.advance(300)
        engine.start(workType: .deepWork, intent: "Switch")
        expect(engine.archive.sessionsToday() == 3,
               "starting while running should archive the previous session", &problems)
        return problems
    }

    // MARK: - 20

    private static func testAwayInsideSession() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Write")
        clock.advance(600)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(480)                      // micro-break, absorbed silently
        engine.transition(on: .awayEnded)
        clock.advance(600)
        engine.stop()

        expectClose(engine.archive.records.last?.workSeconds ?? -1, 1_200,
                    "micro-break excluded from the record", &problems)
        return problems
    }

    // MARK: - 21

    /// The menu bar label showed a static glyph because nothing observed the
    /// store. This covers the engine half of that chain: every real transition
    /// must reach an observer, so a view bound to it can redraw.
    private static func testEngineNotifiesObservers() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        var seen: [SessionState] = []
        engine.onStateChanged = { seen.append($0) }

        engine.start(workType: .deepWork, intent: "Refactor")
        clock.advance(600)
        engine.transition(on: .manualPause)
        clock.advance(60)
        engine.transition(on: .manualResume)
        engine.stop()

        expect(seen.contains(.running), "observer should see running", &problems)
        expect(seen.contains { $0.isPaused }, "observer should see paused", &problems)
        expect(seen.last == .idle, "observer should see idle last, got \(String(describing: seen.last))",
               &problems)
        expect(seen.count >= 4,
               "start, pause, resume and stop should each notify, got \(seen.count)", &problems)

        // A no-op must not notify: redundant redraws are how menu bar items flicker.
        let before = seen.count
        engine.transition(on: .manualResume)   // already idle — documented no-op
        expect(seen.count == before, "a no-op must not notify", &problems)
        return problems
    }

    // MARK: - 22

    private static func testUsageTracker() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        // Idle disabled: this test is about segmenting, and the real monitor
        // would read the actual machine's idle time and trim everything.
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })

        // Two hours in one app, then a switch.
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(7_200)
        tracker.appActivated(bundleID: "com.apple.Safari", name: "Safari")
        clock.advance(600)
        tracker.suspend()

        expect(usage.sessions.count == 2, "two stretches, got \(usage.sessions.count)", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 7_200, "Xcode stretch", &problems)
        expectClose(usage.sessions.last?.seconds ?? -1, 600, "Safari stretch", &problems)

        // A brief glance away and back continues the same session rather than
        // shattering a long stretch into fragments.
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(1_800)
        tracker.appActivated(bundleID: "com.apple.Safari", name: "Safari")
        clock.advance(30)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(1_800)
        tracker.suspend()

        // Raw stretches are now kept apart on purpose: grouping joins them at
        // display time, non-destructively, so the threshold stays retunable.
        let xcode = usage.sessions.filter { $0.bundleID == "com.apple.dt.Xcode" }
        expect(xcode.count == 3, "raw stretches are kept, got \(xcode.count)", &problems)
        let segments = xcode.map {
            TimelineSegment(id: $0.id, bundleID: $0.bundleID, appName: $0.appName,
                            start: $0.start, end: $0.end, colorIndex: 0,
                            endReason: $0.endReason)
        }
        let grouped = AppSessionGrouper.group(segments, others: [])
        expect(grouped.count == 2,
               "grouping rejoins the glance into two sittings, got \(grouped.count)",
               &problems)

        // Sub-5s flickers are Cmd-Tab noise and are dropped entirely.
        let before = usage.sessions.count
        tracker.appActivated(bundleID: "com.flicker.app", name: "Flicker")
        clock.advance(2)
        tracker.suspend()
        expect(usage.sessions.count == before, "a 2s flicker must not be recorded", &problems)

        // Our own popover taking focus must not chop the user's stretch in two.
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(300)
        tracker.appActivated(bundleID: FocusConstants.bundleIdentifier, name: "FocusContinuity")
        clock.advance(10)
        expect(tracker.currentBundleID == "com.apple.dt.Xcode",
               "our own activation must not end the stretch", &problems)

        // Disabling stops recording entirely.
        tracker.setEnabled(false)
        let afterDisable = usage.sessions.count
        tracker.appActivated(bundleID: "com.apple.Notes", name: "Notes")
        clock.advance(600)
        tracker.suspend()
        expect(usage.sessions.count == afterDisable, "disabled tracking records nothing",
               &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    /// A periodic checkpoint is a provisional view of one stretch, not an
    /// immutable fragment. An idle observation must be able to shorten that
    /// saved view before a later active stretch begins.
    private static func testPeriodicCheckpointRollsBackIdleTail() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        var idle: TimeInterval = 0
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: IdleMonitor(idleSeconds: { idle }),
                                      now: { clock.value })

        tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
        clock.advance(60)
        tracker.flush()
        let firstCheckpointID = usage.sessions.first?.id
        clock.advance(60)
        tracker.flush()

        expect(usage.sessions.count == 1,
               "repeated checkpoints must retain one UUID, got \(usage.sessions.count)",
               &problems)
        expect(usage.sessions.first?.id == firstCheckpointID,
               "a periodic checkpoint must correct the original UUID", &problems)
        expect(usage.sessions.first?.endReason == .stillOpen,
               "an active checkpoint must remain provisional", &problems)
        expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 120,
                    "saved checkpoints plus the live tail must not double-count", &problems)

        clock.advance(20 * 60)
        idle = 20 * 60
        tracker.flush()
        expect(usage.sessions.count == 1 && usage.sessions.first?.endReason == .idle,
               "idle must finalise the provisional checkpoint", &problems)
        expectClose(usage.totalToday(), 120,
                    "an idle tail must be removed from today total", &problems)
        expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 120,
                    "a finalised checkpoint has no duplicated live tail", &problems)

        idle = 0
        tracker.confirmPresence(at: clock.value)
        clock.advance(60)
        tracker.flush()

        let ids = Set(usage.sessions.map(\.id))
        expect(ids.count == 2,
               "returning after idle must create exactly one new UUID, got \(ids.count)",
               &problems)
        expectClose(usage.totalToday(), 180,
                    "two active minutes, twenty idle minutes, then one active minute is 180s",
                    &problems)
        expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 180,
                    "the returned stretch remains singly counted after checkpointing", &problems)
        return problems
    }

    // MARK: - Usage storage persistence

    /// A migration must change only the outer JSON container. The original
    /// bytes remain available for recovery, and every historical session field
    /// survives exactly as recorded.
    private static func testLegacyUsageMigrationPreservesHistory() -> [String] {
        var problems: [String] = []
        let clock = Clock(base.addingTimeInterval(12_345))
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstID = UUID()
        let secondID = UUID()
        let legacy = "[\n"
            + "  {\"id\":\"\(firstID.uuidString)\",\"bundleID\":\"com.example.editor\","
            + "\"appName\":\"Editor\",\"start\":\(base.timeIntervalSinceReferenceDate),"
            + "\"end\":\(base.addingTimeInterval(600).timeIntervalSinceReferenceDate),"
            + "\"endReason\":\"idle\"},\n"
            + "  {\"id\":\"\(secondID.uuidString)\",\"bundleID\":\"com.example.browser\","
            + "\"appName\":\"Browser\",\"start\":\(base.addingTimeInterval(900).timeIntervalSinceReferenceDate),"
            + "\"end\":\(base.addingTimeInterval(1_500).timeIntervalSinceReferenceDate),"
            + "\"endReason\":\"appSwitch\"}\n"
            + "]\n"
        let originalBytes = Data(legacy.utf8)
        let usageURL = directory.appendingPathComponent("app-usage.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? originalBytes.write(to: usageURL)

        let migrated = AppUsageArchive(directory: directory, now: { clock.value })
        let expected = [
            AppUsageSession(id: firstID, bundleID: "com.example.editor", appName: "Editor",
                            start: base, end: base.addingTimeInterval(600), endReason: .idle),
            AppUsageSession(id: secondID, bundleID: "com.example.browser", appName: "Browser",
                            start: base.addingTimeInterval(900), end: base.addingTimeInterval(1_500),
                            endReason: .appSwitch)
        ]

        expect(migrated.sessions == expected,
               "migration must preserve every historical session field", &problems)
        expect(migrated.metadata.schemaVersion == 2,
               "migrated storage must identify itself as schema v2", &problems)
        expect(migrated.metadata.accurateFrom == clock.value,
               "migration must record when corrected usage becomes authoritative", &problems)
        guard let backupURL = migrated.legacyBackupURL else {
            problems.append("migration must retain a discoverable v1 backup URL")
            return problems
        }
        expect((try? Data(contentsOf: backupURL)) == originalBytes,
               "v1 backup must preserve the original bytes exactly", &problems)
        let migratedObject = try? JSONSerialization.jsonObject(with: Data(contentsOf: usageURL)) as? [String: Any]
        expect(migratedObject?["metadata"] != nil && migratedObject?["sessions"] != nil,
               "app-usage.json must be rewritten as a v2 envelope", &problems)

        let reloaded = AppUsageArchive(directory: directory, now: { clock.value.addingTimeInterval(60) })
        expect(reloaded.sessions == expected,
               "the v2 envelope must reload without changing history", &problems)
        expect(reloaded.metadata == migrated.metadata,
               "the authoritative date must persist in the v2 envelope", &problems)
        return problems
    }

    /// A checkpoint corrects its stable stretch rather than appending a fragment;
    /// meaningful mutations notify exactly once, while no-op corrections do not.
    private static func testUsageCheckpointReplacesByIdentity() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = AppUsageArchive(directory: directory, now: { clock.value })
        var notifications = 0
        archive.onDidChange = { notifications += 1 }
        let identity = UUID()
        let original = AppUsageSession(id: identity, bundleID: "com.example.editor", appName: "Editor",
                                       start: base, end: base.addingTimeInterval(60), endReason: .stillOpen)

        archive.checkpoint(original)
        expect(archive.sessions == [original], "the first checkpoint must create one record", &problems)
        expect(archive.revision == 1 && notifications == 1,
               "creating a checkpoint must revise and notify once", &problems)

        let corrected = AppUsageSession(id: identity, bundleID: "com.example.editor", appName: "Editor",
                                        start: base, end: base.addingTimeInterval(120), endReason: .stillOpen)
        archive.checkpoint(corrected)
        expect(archive.sessions == [corrected],
               "a checkpoint with the same UUID must replace, not append", &problems)
        expect(archive.revision == 2 && notifications == 2,
               "a corrected checkpoint must revise and notify once", &problems)

        archive.checkpoint(corrected)
        expect(archive.revision == 2 && notifications == 2,
               "an unchanged checkpoint must not revise or notify", &problems)

        let trimmedBelowMinimum = AppUsageSession(id: identity, bundleID: "com.example.editor",
                                                  appName: "Editor", start: base,
                                                  end: base.addingTimeInterval(4), endReason: .idle)
        archive.checkpoint(trimmedBelowMinimum)
        expect(archive.sessions.isEmpty,
               "a corrected checkpoint below five seconds must remove its record", &problems)
        expect(archive.revision == 3 && notifications == 3,
               "removing a corrected record must revise and notify once", &problems)

        archive.checkpoint(trimmedBelowMinimum)
        expect(archive.revision == 3 && notifications == 3,
               "discarding an absent short checkpoint must be a no-op", &problems)

        // A correction at capacity is a replacement, never an insertion: it
        // must leave every other stored record intact. A genuinely new UUID,
        // on the other hand, uses the archive's ordinary oldest-first bound.
        let capacityDirectory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: capacityDirectory) }
        try? FileManager.default.createDirectory(at: capacityDirectory,
                                                 withIntermediateDirectories: true)
        let capacity = AppUsageConstants.capacity
        let stored = (0..<capacity).map { offset in
            AppUsageSession(id: UUID(), bundleID: "com.example.\(offset)",
                            appName: "App \(offset)",
                            start: base.addingTimeInterval(Double(offset) * 10),
                            end: base.addingTimeInterval(Double(offset) * 10 + 5))
        }
        let legacyURL = capacityDirectory.appendingPathComponent("app-usage.json")
        try? JSONEncoder().encode(stored).write(to: legacyURL)
        let bounded = AppUsageArchive(directory: capacityDirectory, now: { clock.value })
        let correctedOldest = AppUsageSession(id: stored[0].id,
                                              bundleID: stored[0].bundleID,
                                              appName: stored[0].appName,
                                              start: stored[0].start,
                                              end: stored[0].end.addingTimeInterval(60),
                                              endReason: .stillOpen)
        bounded.checkpoint(correctedOldest)
        expect(bounded.sessions.count == capacity && bounded.sessions.contains(correctedOldest)
               && bounded.sessions.contains(where: { $0.id == stored[1].id }),
               "correcting an existing UUID at capacity must not evict another record", &problems)

        let newIdentity = AppUsageSession(bundleID: "com.example.new", appName: "New",
                                          start: base.addingTimeInterval(999_999),
                                          end: base.addingTimeInterval(1_000_004))
        bounded.checkpoint(newIdentity)
        expect(bounded.sessions.count == capacity && bounded.sessions.contains(newIdentity)
               && !bounded.sessions.contains(where: { $0.id == correctedOldest.id })
               && bounded.sessions.contains(where: { $0.id == stored[1].id }),
               "a new UUID at capacity must evict only the oldest record", &problems)
        return problems
    }

    // MARK: - 23

    private static func testMostUsedApps() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })

        func add(_ bundleID: String, _ name: String, minutes: Double, endingHoursAgo: Double) {
            let end = clock.value.addingTimeInterval(-endingHoursAgo * 3_600)
            usage.record(AppUsageSession(bundleID: bundleID, appName: name,
                                         start: end.addingTimeInterval(-minutes * 60),
                                         end: end))
        }
        add("com.apple.dt.Xcode", "Xcode", minutes: 120, endingHoursAgo: 4)
        add("com.apple.dt.Xcode", "Xcode", minutes: 60, endingHoursAgo: 8)
        add("com.apple.dt.Xcode", "Xcode", minutes: 30, endingHoursAgo: 12)
        add("com.apple.Safari", "Safari", minutes: 45, endingHoursAgo: 2)

        let summaries = usage.mostUsedApps(limit: 4, sessionsEach: 5)
        expect(summaries.count == 2, "two apps, got \(summaries.count)", &problems)
        expect(summaries.first?.bundleID == "com.apple.dt.Xcode",
               "busiest app first, got \(summaries.first?.appName ?? "nil")", &problems)
        expectClose(summaries.first?.totalSeconds ?? -1, 210 * 60, "Xcode total", &problems)
        expectClose(summaries.first?.longestSeconds ?? -1, 120 * 60, "Xcode longest", &problems)
        expect(summaries.first?.recent.count == 3, "three recent Xcode sessions", &problems)
        expectClose(summaries.first?.lastSession?.seconds ?? -1, 120 * 60,
                    "most recent first", &problems)

        // The per-app session limit is what Settings changes.
        let limited = usage.mostUsedApps(limit: 4, sessionsEach: 2)
        expect(limited.first?.recent.count == 2, "session limit respected", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 24

    private static func testHistoryFormatters() -> [String] {
        var problems: [String] = []
        let reference = base

        expect(Tokens.relative(reference.addingTimeInterval(-30), from: reference) == "just now",
               "30s should read 'just now'", &problems)
        expect(Tokens.relative(reference.addingTimeInterval(-3_600), from: reference) == "1 hour ago",
               "singular hour", &problems)
        expect(Tokens.relative(reference.addingTimeInterval(-4 * 3_600), from: reference)
               == "4 hours ago", "the example from the request", &problems)
        expect(Tokens.relative(reference.addingTimeInterval(-26 * 3_600), from: reference)
               == "yesterday", "26h should read 'yesterday'", &problems)

        expect(Tokens.spent(7_200) == "2 hours", "2h exactly, got \(Tokens.spent(7_200))",
               &problems)
        expect(Tokens.spent(7_980) == "2 hours 13 min",
               "2h13m, got \(Tokens.spent(7_980))", &problems)
        expect(Tokens.spent(60) == "1 minute", "singular minute", &problems)
        expect(Tokens.spent(0) == "0 seconds", "zero", &problems)

        // Range formatting is locale-dependent, so assert the structure only.
        let range = Tokens.timeRange(reference, reference.addingTimeInterval(7_200))
        expect(range.contains("–"), "range should use an en dash, got \(range)", &problems)
        return problems
    }

    // MARK: - 25

    private static func testDashboardTimeline() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        func use(_ id: String, _ name: String, fromHour: Double, hours: Double) {
            let start = dayStart.addingTimeInterval(fromHour * 3_600)
            usage.record(AppUsageSession(bundleID: id, appName: name, start: start,
                                         end: start.addingTimeInterval(hours * 3_600)))
        }
        use("com.a", "Alpha", fromHour: 9, hours: 2)
        use("com.b", "Beta", fromHour: 11, hours: 1)
        use("com.a", "Alpha", fromHour: 14, hours: 1)

        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
        let segments = stats.timeline(for: base)
        expect(segments.count == 3, "three segments, got \(segments.count)", &problems)
        expect(segments.map(\.start) == segments.map(\.start).sorted(),
               "segments must be ordered by start", &problems)
        expect(segments.filter { $0.bundleID == "com.a" }.allSatisfy { $0.colorIndex == 0 },
               "the busiest app takes index 0 for all its segments", &problems)

        let ranked = stats.rankedApps(for: base)
        expect(ranked.count == 2, "two apps, got \(ranked.count)", &problems)
        expect(ranked.first?.bundleID == "com.a", "busiest first", &problems)
        expectClose(ranked.first?.total ?? -1, 3 * 3_600, "Alpha total", &problems)
        expectClose(ranked.first?.longest ?? -1, 2 * 3_600, "Alpha longest", &problems)
        expectClose(ranked.reduce(0) { $0 + $1.share }, 1.0, "shares sum to 1", &problems)
        expectClose(stats.trackedTotal(for: base), 4 * 3_600, "tracked total", &problems)

        // An empty day must publish 0, never NaN.
        let emptyStats = DashboardStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                                 now: { clock.value }),
                                        usage: AppUsageArchive(directory: scratchDirectory(),
                                                               now: { clock.value }),
                                        now: { clock.value })
        expect(emptyStats.rankedApps(for: base).isEmpty, "no apps on an empty day", &problems)
        expectClose(emptyStats.trackedTotal(for: base), 0, "empty total", &problems)
        expect(emptyStats.timelineWindow(for: base) == nil,
               "an empty day has no drawing window", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 26

    private static func testTimelineClipsAcrossMidnight() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        // 23:30 to 00:30 — half belongs to each day, and to neither twice.
        let start = dayStart.addingTimeInterval(23.5 * 3_600)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: start, end: start.addingTimeInterval(3_600)))

        let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                            now: { clock.value }),
                                   usage: usage, now: { clock.value })
        let today = stats.timeline(for: base)
        expect(today.count == 1, "one clipped segment today, got \(today.count)", &problems)
        expectClose(today.first?.seconds ?? -1, 1_800, "today keeps the first half hour",
                    &problems)

        let tomorrow = stats.timeline(for: base.addingTimeInterval(86_400))
        expectClose(tomorrow.first?.seconds ?? -1, 1_800,
                    "tomorrow keeps the second half hour", &problems)
        expectClose(stats.trackedTotal(for: base) + stats.trackedTotal(for: base.addingTimeInterval(86_400)),
                    3_600, "the two halves sum to the whole, never double counted", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 27

    private static func testFocusQualityAndRunning() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        func use(_ id: String, fromHour: Double, hours: Double) {
            let start = dayStart.addingTimeInterval(fromHour * 3_600)
            usage.record(AppUsageSession(bundleID: id, appName: id, start: start,
                                         end: start.addingTimeInterval(hours * 3_600)))
        }
        use("com.a", fromHour: 9, hours: 2)     // inside the session below
        use("com.b", fromHour: 13, hours: 2)    // outside it
        sessions.append(SessionRecord(name: "Deep", workType: .deepWork,
                                      start: dayStart.addingTimeInterval(9 * 3_600),
                                      end: dayStart.addingTimeInterval(11 * 3_600),
                                      workSeconds: 7_200))

        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
        let quality = stats.focusQuality(for: base)
        expectClose(quality.insideSessionShare, 0.5,
                    "half of tracked time was inside a session", &problems)
        expect(quality.sessionCount == 1, "one session", &problems)
        expect(quality.byWorkType.first?.workType == .deepWork, "deep work leads", &problems)

        clock.value = dayStart.addingTimeInterval(12 * 3_600)
        let running = stats.runningNow(from: [
            RunningAppInput(bundleID: "com.a", appName: "Alpha",
                            launched: dayStart.addingTimeInterval(9 * 3_600),
                            stretchSeconds: 3 * 3_600),
            RunningAppInput(bundleID: "com.finder", appName: "Finder", launched: nil)
        ])
        expectClose(running.first?.openFor ?? -1, 3 * 3_600,
                    "Alpha frontmost for three hours", &problems)
        expect(running.count == 1,
               "an app with no launch date is excluded, got \(running.count)", &problems)
        expect(running.first?.bundleID == "com.a", "the real app survives", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 28

    private static func testInsightGating() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })

        expect(stats.insights(for: base).isEmpty,
               "no data must produce no insights, not empty cards", &problems)

        let dayStart = Calendar.current.startOfDay(for: base)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600),
                                     end: dayStart.addingTimeInterval(11 * 3_600)))
        let withUsage = stats.insights(for: base)
        expect(withUsage.contains { $0.id == "longest-stretch" },
               "one usage session unlocks the longest-stretch insight", &problems)
        expect(!withUsage.contains { $0.id == "inside-session" },
               "with no focus session the in-session insight stays hidden", &problems)
        expect(!withUsage.contains { $0.id == "vs-yesterday" },
               "with no yesterday data the comparison stays hidden", &problems)

        sessions.append(SessionRecord(name: "Deep", workType: .deepWork,
                                      start: dayStart.addingTimeInterval(9 * 3_600),
                                      end: dayStart.addingTimeInterval(10 * 3_600),
                                      workSeconds: 3_600))
        let withSession = stats.insights(for: base)
        expect(withSession.contains { $0.id == "inside-session" },
               "a focus session unlocks the in-session insight", &problems)
        // Deep-work share is deliberately NOT an insight: the Focus quality
        // section already states it, and repeating a figure erodes trust in both.
        expect(!withSession.contains { $0.id == "deep-work-share" },
               "deep work share belongs to Focus quality, not Insights", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 29

    /// Reproduces the exact state from the reported screenshot: 42 minutes into a
    /// session with nothing completed. Every figure must agree.
    private static func testRunningSessionCountsEverywhere() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Refactor")
        clock.advance(42 * 60)

        expectClose(engine.todayTotal, 42 * 60, "today counts the running session", &problems)
        let streak = engine.archive.currentStreak(includingToday: engine.elapsed)
        expect(streak == 1, "42 minutes of live work should light the streak, got \(streak)",
               &problems)
        expect(engine.sessionsToday == 1,
               "the running session counts as one, got \(engine.sessionsToday)", &problems)
        expectClose(engine.longestToday, 42 * 60,
                    "longest today includes the running session", &problems)

        // Under the 25 minute bar the streak stays honest.
        let clock2 = Clock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Short")
        clock2.advance(10 * 60)
        expect(engine2.archive.currentStreak(includingToday: engine2.elapsed) == 0,
               "10 minutes must not light the streak", &problems)
        return problems
    }

    // MARK: - 30

    /// The Screen Time criticism applied to us: an app left frontmost while
    /// nobody is at the keyboard must not accrue time.
    private static func testIdleTrimsUsage() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        var idle: TimeInterval = 0
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: IdleMonitor(idleSeconds: { idle }),
                                      now: { clock.value })

        tracker.appActivated(bundleID: "com.a", name: "Alpha")
        clock.advance(3_600)          // an hour frontmost
        idle = 2_400                  // but the last 40 minutes had no input
        tracker.suspend()

        expectClose(usage.sessions.first?.seconds ?? -1, 1_200,
                    "idle time must not count as usage", &problems)

        // Below the cutoff nothing is trimmed: a pause to read is still work.
        let dir2 = scratchDirectory()
        let usage2 = AppUsageArchive(directory: dir2, now: { clock.value })
        var idle2: TimeInterval = 0
        let tracker2 = AppUsageTracker(archive: usage2,
                                       ownBundleID: FocusConstants.bundleIdentifier,
                                       idle: IdleMonitor(idleSeconds: { idle2 }),
                                       now: { clock.value })
        tracker2.appActivated(bundleID: "com.b", name: "Beta")
        clock.advance(600)
        idle2 = 60                    // a minute of reading, under the 180s cutoff
        tracker2.suspend()
        expectClose(usage2.sessions.first?.seconds ?? -1, 600,
                    "a short pause must not be trimmed", &problems)

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir2)
        return problems
    }

    // MARK: - 31

    private static func testPreciseDurationAndConsistency() -> [String] {
        var problems: [String] = []

        // D-2: a 45-second stretch rendered as "0m" before this.
        expect(Tokens.preciseDuration(0) == "0s", "zero, got \(Tokens.preciseDuration(0))", &problems)
        expect(Tokens.preciseDuration(45) == "45s", "45s, got \(Tokens.preciseDuration(45))", &problems)
        expect(Tokens.preciseDuration(59) == "59s", "below a minute", &problems)
        expect(Tokens.preciseDuration(60) == "1m", "at a minute", &problems)
        expect(Tokens.preciseDuration(3_599) == "59m", "below an hour", &problems)
        expect(Tokens.preciseDuration(3_600) == "1h", "at an hour", &problems)
        expect(Tokens.preciseDuration(7_980) == "2h 13m", "hours and minutes", &problems)

        // D-1: "1 session today" and "No sessions yet today" must never disagree.
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600),
                                     end: dayStart.addingTimeInterval(10 * 3_600)))

        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
        let running = stats.focusQuality(for: base, runningSeconds: 2_520)
        expect(running.sessionCount == 1,
               "a running session counts, got \(running.sessionCount)", &problems)
        expect(!running.byWorkType.isEmpty,
               "the running session contributes to the work-type split", &problems)
        let idle = stats.focusQuality(for: base, runningSeconds: nil)
        expect(idle.sessionCount == 0, "no running session, no count", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 32

    private static func testWindowSnappingAndStretches() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: base)

        // D-3: four minutes of data must not produce a one-hour axis.
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600 + 120),
                                     end: dayStart.addingTimeInterval(9 * 3_600 + 360)))
        let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                            now: { clock.value }),
                                   usage: usage, now: { clock.value })
        guard let window = stats.timelineWindow(for: base) else {
            problems.append("a day with data must have a window")
            return problems
        }
        let span = window.end.timeIntervalSince(window.start)
        expect(span >= FocusConstants.minimumTimelineSpan,
               "minimum four-hour span, got \(span / 3_600)h", &problems)
        expect(calendar.component(.minute, from: window.start) == 0,
               "window start snaps to the hour", &problems)
        expect(calendar.component(.minute, from: window.end) == 0,
               "window end snaps to the hour", &problems)

        // Grouping, span and hover hit-testing.
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(16 * 3_600),
                                     end: dayStart.addingTimeInterval(16 * 3_600 + 600)))
        let stretches = stats.stretches(for: base, bundleID: "com.a")
        expect(stretches.count == 2, "two stretches, got \(stretches.count)", &problems)
        guard let appSpan = stats.span(for: base, bundleID: "com.a") else {
            problems.append("an app with usage must have a span")
            return problems
        }
        expectClose(appSpan.end.timeIntervalSince(appSpan.start), 7 * 3_600 + 480,
                    "span runs first start to last end", &problems)

        let hit = stats.segment(at: dayStart.addingTimeInterval(9 * 3_600 + 180), on: base)
        expect(hit?.bundleID == "com.a", "hover inside a stretch finds it", &problems)
        expect(stats.segment(at: dayStart.addingTimeInterval(12 * 3_600), on: base) == nil,
               "hover over a gap finds nothing", &problems)

        expect(stats.earliestRecordedDay() != nil,
               "an archive with data reports an earliest day", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 33

    private static func testEndReasonsAndMigration() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        var idle: TimeInterval = 0
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: IdleMonitor(idleSeconds: { idle }),
                                      now: { clock.value })

        tracker.appActivated(bundleID: "com.a", name: "Alpha")
        clock.advance(600)
        tracker.appActivated(bundleID: "com.b", name: "Beta")      // a switch
        clock.advance(900)
        idle = 300                                                  // last 5 min idle
        tracker.suspend()

        let reasons = usage.sessions.map(\.endReason)
        expect(reasons.first == .appSwitch,
               "a switch records .appSwitch, got \(String(describing: reasons.first))",
               &problems)
        expect(reasons.contains(.idle),
               "an idle-trimmed stretch records .idle, saw \(reasons)", &problems)

        // Stretches are no longer merged at write time: the gaps must survive.
        let clock2 = Clock(base)
        let dir2 = scratchDirectory()
        let usage2 = AppUsageArchive(directory: dir2, now: { clock2.value })
        let tracker2 = AppUsageTracker(archive: usage2,
                                       ownBundleID: FocusConstants.bundleIdentifier,
                                       idle: .disabled,
                                       now: { clock2.value })
        tracker2.appActivated(bundleID: "com.a", name: "Alpha")
        clock2.advance(600)
        tracker2.appActivated(bundleID: "com.b", name: "Beta")
        clock2.advance(30)
        tracker2.appActivated(bundleID: "com.a", name: "Alpha")
        clock2.advance(600)
        tracker2.suspend()
        expect(usage2.sessions.filter { $0.bundleID == "com.a" }.count == 2,
               "raw stretches are kept apart; grouping joins them later", &problems)

        // Records written before `endReason` existed must still load.
        let legacyDir = scratchDirectory()
        try? FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacy = "[{\"id\":\"\(UUID().uuidString)\",\"bundleID\":\"com.legacy\","
            + "\"appName\":\"Legacy\",\"start\":\(base.timeIntervalSinceReferenceDate),"
            + "\"end\":\(base.addingTimeInterval(600).timeIntervalSinceReferenceDate)}]"
        try? Data(legacy.utf8).write(to: legacyDir.appendingPathComponent("app-usage.json"))
        let migrated = AppUsageArchive(directory: legacyDir, now: { clock.value })
        expect(migrated.sessions.count == 1,
               "a legacy record must still decode, got \(migrated.sessions.count)", &problems)
        expect(migrated.sessions.first?.endReason == .appSwitch,
               "a legacy record defaults to .appSwitch", &problems)

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir2)
        try? FileManager.default.removeItem(at: legacyDir)
        return problems
    }

    // MARK: - 34

    private static func testSessionGrouping() -> [String] {
        var problems: [String] = []
        let dayStart = Calendar.current.startOfDay(for: base)
        func seg(_ id: String, _ fromMin: Double, _ toMin: Double,
                 _ reason: UsageEndReason = .appSwitch) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: id, appName: id,
                            start: dayStart.addingTimeInterval(fromMin * 60),
                            end: dayStart.addingTimeInterval(toMin * 60),
                            colorIndex: 0, endReason: reason)
        }
        let gap: TimeInterval = 300, bridge: TimeInterval = 900

        // A three-minute detour joins into one sitting with two visits.
        let detour = AppSessionGrouper.group([seg("com.a", 0, 20), seg("com.a", 23, 40)],
                                             others: [seg("com.b", 20, 23)],
                                             sessionGap: gap, awayBridge: bridge)
        expect(detour.count == 1, "a short detour joins, got \(detour.count)", &problems)
        expect(detour.first?.visits == 2, "two visits", &problems)
        expectClose(detour.first?.attended ?? -1, 37 * 60,
                    "attended excludes the gap", &problems)
        expectClose(detour.first?.span ?? -1, 40 * 60, "the span includes the gap", &problems)

        // A lock is a boundary however short the gap.
        let locked = AppSessionGrouper.group([seg("com.a", 0, 20, .systemLock),
                                              seg("com.a", 21, 40)],
                                             others: [], sessionGap: gap, awayBridge: bridge)
        expect(locked.count == 2, "a lock splits, got \(locked.count)", &problems)

        // Real work elsewhere is a context switch, not a detour.
        let switched = AppSessionGrouper.group([seg("com.a", 0, 20), seg("com.a", 24, 40)],
                                               others: [seg("com.b", 20, 24)],
                                               sessionGap: 180, awayBridge: bridge)
        expect(switched.count == 2,
               "another app's real usage splits, got \(switched.count)", &problems)

        // Stepping away and returning to the same app joins, up to the bridge.
        let away = AppSessionGrouper.group([seg("com.a", 0, 20, .idle), seg("com.a", 32, 40)],
                                           others: [], sessionGap: gap, awayBridge: bridge)
        expect(away.count == 1, "an idle gap under the bridge joins, got \(away.count)",
               &problems)

        let longAway = AppSessionGrouper.group([seg("com.a", 0, 20, .idle),
                                                seg("com.a", 60, 70)],
                                               others: [], sessionGap: gap, awayBridge: bridge)
        expect(longAway.count == 2, "beyond the bridge splits", &problems)

        expect(AppSessionGrouper.group([], others: [], sessionGap: gap,
                                       awayBridge: bridge).isEmpty,
               "no stretches, no sessions", &problems)
        return problems
    }

    // MARK: - 35

    private static func testHourlyBuckets() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        // 9:45 to 10:15 — fifteen minutes either side of the hour boundary.
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600 + 2_700),
                                     end: dayStart.addingTimeInterval(10 * 3_600 + 900)))
        let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                            now: { clock.value }),
                                   usage: usage, now: { clock.value })
        let filled = stats.hourlyBuckets(for: base, bundleID: "com.a")
            .filter { $0.seconds > 0 }
        expect(filled.count == 2,
               "a stretch across the hour lands in two buckets, got \(filled.count)",
               &problems)
        expectClose(filled.first?.seconds ?? -1, 900, "fifteen minutes in the first hour",
                    &problems)
        expectClose(filled.reduce(0) { $0 + $1.seconds }, 1_800,
                    "buckets sum to the stretch", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 36

    /// Regression for the dead space in the popover: the fix was written into a
    /// plan and skipped during execution, so it gets a test this time.
    private static func testWeekChartEmptyRule() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        let empty = (0..<7).map {
            DayBar(id: day.addingTimeInterval(Double($0) * 86_400),
                   label: "D", minutes: 0, isToday: $0 == 6)
        }
        expect(!DayBar.hasData(empty),
               "all-zero bars must report no data, or the chart renders dead space",
               &problems)

        var oneDay = empty
        oneDay[3] = DayBar(id: oneDay[3].id, label: "D", minutes: 42, isToday: false)
        expect(DayBar.hasData(oneDay), "one non-zero day is data", &problems)
        return problems
    }

    // MARK: - 37

    private static func testBreakReminder() -> [String] {
        var problems: [String] = []
        let now = base.addingTimeInterval(4 * 3_600)
        func stretch(_ fromMinAgo: Double, _ toMinAgo: Double) -> AppUsageSession {
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: now.addingTimeInterval(-fromMinAgo * 60),
                            end: now.addingTimeInterval(-toMinAgo * 60))
        }
        // 53 minutes of work broken only by a 2 minute gap: continuous as far as
        // the cognitive tier is concerned, since its rest length is five minutes.
        let continuous = [stretch(55, 30), stretch(28, 0)]
        expectClose(BreakReminder.worked(continuous, now: now,
                                         restingAtLeast: BreakTier.cognitive.breakLength),
                    53 * 60,
                    "short gaps neither reset the clock nor count as work", &problems)
        // A two-minute gap does NOT clear even the shallowest tier: below the
        // three-minute idle cutoff the usage archive cannot tell rest from
        // recording noise, so nothing shorter is allowed to reset a clock.
        expectClose(BreakReminder.worked(continuous, now: now,
                                         restingAtLeast: BreakTier.micro.restGap),
                    53 * 60, "a two-minute gap is not observable rest", &problems)
        expect(BreakTier.micro.restGap == AppUsageTracker.idleCutoff,
               "the shallow tier resets at the idle cutoff, not its own 30s",
               &problems)
        expect(BreakReminder.dueTier(continuous, now: now) == .cognitive,
               "53 continuous minutes is a cognitive reset", &problems)

        // A 12 minute gap clears the cognitive tier but not the ultradian one.
        let rested = [stretch(90, 40), stretch(28, 0)]
        expectClose(BreakReminder.worked(rested, now: now,
                                         restingAtLeast: BreakTier.cognitive.breakLength),
                    28 * 60, "a long gap resets the cognitive clock", &problems)
        expect(BreakReminder.dueTier(rested, now: now) == .micro,
               "28 minutes since a rest is an eye break, got "
               + "\(String(describing: BreakReminder.dueTier(rested, now: now)))", &problems)

        // Having just spoken at this depth, it stays quiet until that tier's own
        // interval has passed.
        let saidCognitive = BreakNotice(tier: .cognitive, at: now.addingTimeInterval(-600))
        expect(BreakReminder.prompt(continuous, now: now, last: saidCognitive) == nil,
               "no second nudge ten minutes after the first", &problems)
        let saidLongAgo = BreakNotice(tier: .cognitive, at: now.addingTimeInterval(-60 * 60))
        expect(BreakReminder.prompt(continuous, now: now, last: saidLongAgo) != nil,
               "an hour later, due again", &problems)

        expectClose(BreakReminder.worked([], now: now, restingAtLeast: 300), 0,
                    "no usage, no work", &problems)
        return problems
    }

    // MARK: - 66

    /// The tiered break system: thresholds, escalation, and the wording.
    private static func testBreakTiers() -> [String] {
        var problems: [String] = []
        let now = base.addingTimeInterval(6 * 3_600)
        func run(_ minutes: Double, app: String = "Xcode",
                 bundle: String = "com.apple.dt.Xcode") -> AppUsageSession {
            AppUsageSession(bundleID: bundle, appName: app,
                            start: now.addingTimeInterval(-minutes * 60), end: now)
        }

        expect(BreakReminder.dueTier([run(19)], now: now) == nil,
               "nineteen minutes is not yet anything", &problems)
        expect(BreakReminder.dueTier([run(21)], now: now) == .micro,
               "twenty minutes is an eye break", &problems)
        expect(BreakReminder.dueTier([run(51)], now: now) == .cognitive,
               "fifty minutes escalates past the eye break", &problems)
        expect(BreakReminder.dueTier([run(91)], now: now) == .ultradian,
               "ninety minutes is the deep one", &problems)

        // The deepest due tier wins, and escalation does not wait out the
        // shallower tier's quiet period.
        let justSaidMicro = BreakNotice(tier: .micro, at: now.addingTimeInterval(-120))
        let escalated = BreakReminder.prompt([run(91)], now: now, last: justSaidMicro)
        expect(escalated?.tier == .ultradian,
               "a deeper break must interrupt a shallower one's quiet period", &problems)
        // ...but two prompts inside a minute are noise whatever the tiers say.
        let secondsAgo = BreakNotice(tier: .micro, at: now.addingTimeInterval(-10))
        expect(BreakReminder.prompt([run(91)], now: now, last: secondsAgo) == nil,
               "nothing fires twice inside a minute", &problems)

        // Wording: the app is named, and the figure is what was actually worked
        // rather than the threshold that was crossed.
        guard let prompt = BreakReminder.prompt([run(63)], now: now, last: nil) else {
            problems.append("63 minutes should produce a prompt")
            return problems
        }
        expect(prompt.appName == "Xcode", "the app is named, got "
               + "\(prompt.appName ?? "nil")", &problems)
        expect(prompt.body.contains("Xcode"), "the body names it too", &problems)
        // The real figure, not the 50m threshold that was crossed.
        expect(prompt.body.contains("1h 3m"),
               "should report what was actually worked: \(prompt.body)", &problems)
        expect(!prompt.body.contains("50m"),
               "must not claim the threshold as the elapsed time", &problems)
        expect(prompt.title == BreakTier.cognitive.title, "titled by tier", &problems)

        // No dominant app means no app is named, rather than an arbitrary one.
        let scattered = [
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: now.addingTimeInterval(-60 * 60),
                            end: now.addingTimeInterval(-40 * 60)),
            AppUsageSession(bundleID: "com.b", appName: "Beta",
                            start: now.addingTimeInterval(-40 * 60),
                            end: now.addingTimeInterval(-20 * 60)),
            AppUsageSession(bundleID: "com.c", appName: "Gamma",
                            start: now.addingTimeInterval(-20 * 60), end: now)
        ]
        expect(BreakReminder.dominantApp(scattered, now: now, within: 300) == nil,
               "three equal thirds name nobody", &problems)
        guard let vague = BreakReminder.prompt(scattered, now: now, last: nil) else {
            problems.append("an hour of scattered work is still a break")
            return problems
        }
        expect(!vague.body.contains("Alpha") && !vague.body.contains("Gamma"),
               "no app should be named: \(vague.body)", &problems)

        // An unknown name degrades rather than appearing verbatim.
        expect(BreakReminder.dominantApp([run(30, app: "Unknown", bundle: "com.x")],
                                         now: now, within: 300) == nil,
               "'Unknown' is not an app name", &problems)

        // The countdown names the soonest tier. From a standing start that is
        // the eye break.
        expect(BreakReminder.next([run(10)], now: now)?.tier == .micro,
               "ten minutes in, the eye break is next", &problems)

        // But a pause resets only the shallow clock, so after one the *deeper*
        // tier is often sooner — forty minutes of work then a three-minute
        // breather leaves the cognitive reset ten minutes away and the eye
        // break a full twenty. The countdown has to follow the clocks, not the
        // tier order, or it promises a break later than the one you will get.
        let afterPause = [
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: now.addingTimeInterval(-43 * 60),
                            end: now.addingTimeInterval(-3 * 60))
        ]
        guard let upcoming = BreakReminder.next(afterPause, now: now) else {
            problems.append("something should always be next")
            return problems
        }
        expect(upcoming.tier == .cognitive,
               "the cognitive reset is sooner after a short pause, got "
               + "\(upcoming.tier)", &problems)
        expectClose(upcoming.seconds, 10 * 60, "ten minutes to it", &problems)
        return problems
    }

    // MARK: - 38

    private static func testTimelineLayout() -> [String] {
        var problems: [String] = []
        let dayStart = Calendar.current.startOfDay(for: base)
        func seg(_ fromMin: Double, _ toMin: Double) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: "com.a", appName: "Alpha",
                            start: dayStart.addingTimeInterval(fromMin * 60),
                            end: dayStart.addingTimeInterval(toMin * 60),
                            colorIndex: 0)
        }

        // 30 minutes, three hours of nothing, 30 minutes.
        let layout = TimelineLayout(segments: [seg(0, 30), seg(210, 240)],
                                    gapThreshold: 20 * 60)
        expect(layout.clusters.count == 2, "two clusters, got \(layout.clusters.count)",
               &problems)
        expect(layout.gaps.count == 1, "one elided gap, got \(layout.gaps.count)", &problems)
        expectClose(layout.gaps.first?.duration ?? -1, 180 * 60, "the gap is three hours",
                    &problems)

        let first = layout.clusters[0], second = layout.clusters[1]
        expectClose(first.xEnd - first.xStart, second.xEnd - second.xStart,
                    "equal durations get equal widths", &problems)
        expectClose(layout.clusters.last?.xEnd ?? -1, 1.0, "the band is fully used", &problems)
        expect(first.xEnd <= (layout.gaps.first?.xStart ?? -1) + 0.0001,
               "the separator sits between the clusters", &problems)

        // Under the threshold nothing is elided.
        let tight = TimelineLayout(segments: [seg(0, 30), seg(45, 60)], gapThreshold: 20 * 60)
        expect(tight.clusters.count == 1, "a 15 minute gap stays inside one cluster",
               &problems)
        expect(tight.gaps.isEmpty, "and produces no separator", &problems)

        // Mapping round-trips inside a cluster, refuses inside a gap.
        let inside = dayStart.addingTimeInterval(15 * 60)
        guard let fraction = layout.fraction(for: inside) else {
            problems.append("an instant inside a cluster must have a position")
            return problems
        }
        expectClose(layout.date(at: fraction)?.timeIntervalSince(inside) ?? 999, 0,
                    "fraction and date round-trip", &problems)
        expect(layout.fraction(for: dayStart.addingTimeInterval(120 * 60)) == nil,
               "an instant inside an elided gap has no position", &problems)

        // A tiny cluster beside a huge one stays visible.
        let lopsided = TimelineLayout(segments: [seg(0, 2), seg(120, 360)],
                                      gapThreshold: 20 * 60)
        let tiny = lopsided.clusters[0]
        expect(tiny.xEnd - tiny.xStart >= 0.035,
               "a two-minute cluster keeps a readable width, got \(tiny.xEnd - tiny.xStart)",
               &problems)

        // Hours are drawn inside clusters only.
        expect(layout.hourTicks().allSatisfy { layout.fraction(for: $0) != nil },
               "every hour tick has a position", &problems)
        expect(TimelineLayout(segments: [], gapThreshold: 20 * 60).isEmpty,
               "no segments, no clusters", &problems)
        return problems
    }

    // MARK: - 39

    private static func testInsightCopyAndRunningFilter() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        usage.record(AppUsageSession(bundleID: "com.a", appName: "Claude",
                                     start: dayStart.addingTimeInterval(9 * 3_600),
                                     end: dayStart.addingTimeInterval(9 * 3_600 + 600)))
        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })

        guard let longest = stats.insights(for: base)
            .first(where: { $0.id == "longest-stretch" }) else {
            problems.append("the longest-stretch insight must be present")
            return problems
        }
        expect(longest.headline == "Longest stretch in one app",
               "the headline names the measure, got '\(longest.headline)'", &problems)
        expect(longest.detail.contains("Claude"),
               "the detail names the app, got '\(longest.detail)'", &problems)
        expect(longest.detail.contains("10m"),
               "the detail carries the duration, got '\(longest.detail)'", &problems)
        expect(longest.detail.contains("–"),
               "the detail carries the clock range as evidence, got '\(longest.detail)'",
               &problems)

        // A process with no launch date tells us nothing, so it is not listed.
        let running = stats.runningNow(from: [
            RunningAppInput(bundleID: "com.a", appName: "Claude",
                            launched: dayStart.addingTimeInterval(8 * 3_600)),
            RunningAppInput(bundleID: "com.apple.finder", appName: "Finder", launched: nil)
        ])
        expect(running.count == 1,
               "apps with no launch date are excluded, got \(running.count)", &problems)
        expect(running.first?.bundleID == "com.a", "the real app survives", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 40

    /// Two defects found by tracing what happens across a sleep.
    private static func testSleepWakeTracking() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        // Zero idle throughout: the user is actively typing.
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })

        // An active stretch flushed while the user is typing must NOT be labelled
        // .idle. Comparing a trimmed end against a freshly sampled now() made that
        // true by microseconds, so every stretch claimed to be idle.
        tracker.appActivated(bundleID: "com.a", name: "Alpha")
        clock.advance(600)
        tracker.flush()
        expect(usage.sessions.last?.endReason == .stillOpen,
               "an active flush is .stillOpen, got "
               + "\(String(describing: usage.sessions.last?.endReason))", &problems)

        // Flushing repeatedly must not double-count the same seconds.
        clock.advance(300)
        tracker.flush()
        clock.advance(300)
        tracker.flush()
        let total = usage.sessions.filter { $0.bundleID == "com.a" }
            .reduce(0.0) { $0 + $1.seconds }
        expectClose(total, 1_200, "repeated flushes sum to the real elapsed time",
                    &problems)

        // Sleeping closes the stretch; waking into the SAME app must reopen it,
        // because no activation notification fires in that case.
        tracker.suspend()
        clock.advance(8 * 3_600)
        expect(tracker.currentBundleID == nil, "sleep closes the stretch", &problems)
        tracker.resume(bundleID: "com.a", name: "Alpha")
        expect(tracker.currentBundleID == "com.a",
               "waking into the same app reopens tracking", &problems)
        clock.advance(600)
        tracker.flush()
        let afterWake = usage.sessions.filter { $0.start >= base.addingTimeInterval(8 * 3_600) }
        expect(!afterWake.isEmpty, "work after waking is recorded", &problems)
        expect(afterWake.allSatisfy { $0.seconds <= 601 },
               "the overnight gap is not counted as usage", &problems)

        // resume() must not clobber an already-open stretch or track ourselves.
        tracker.resume(bundleID: "com.b", name: "Beta")
        expect(tracker.currentBundleID == "com.a",
               "resume does not replace an open stretch", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 41

    private static func testPeriodStats() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)

        func use(_ daysAgo: Int, hours: Double) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return
            }
            let start = day.addingTimeInterval(10 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start,
                                         end: start.addingTimeInterval(hours * 3_600)))
        }
        use(0, hours: 2)
        use(1, hours: 1)

        let stats = PeriodStats(sessions: sessions, usage: usage, now: { clock.value })

        let week = stats.days(for: .week, containing: base)
        expect(week.count == 7, "a week has seven days, got \(week.count)", &problems)
        expectClose(week.reduce(0) { $0 + $1.tracked }, 3 * 3_600,
                    "the week's bars sum to the tracked total", &problems)

        let summary = stats.summary(for: .week, containing: base)
        expect(summary.activeDays == 2, "two active days, got \(summary.activeDays)",
               &problems)
        // Averaging a five-day week over seven understates every working day.
        expectClose(summary.averagePerActiveDay, 1.5 * 3_600,
                    "the average divides by active days", &problems)
        expectClose(summary.tracked, 3 * 3_600, "period total", &problems)
        expect(summary.totalDays == 7, "seven calendar days", &problems)

        let month = stats.days(for: .month, containing: base)
        expect(month.count >= 28 && month.count <= 31,
               "a month has 28 to 31 days, got \(month.count)", &problems)
        expect(stats.days(for: .day, containing: base).count == 1,
               "day is one day", &problems)

        // An empty period must be empty, never NaN.
        let emptyStats = PeriodStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                              now: { clock.value }),
                                     usage: AppUsageArchive(directory: scratchDirectory(),
                                                            now: { clock.value }),
                                     now: { clock.value })
        let emptySummary = emptyStats.summary(for: .week, containing: base)
        expect(emptySummary.activeDays == 0, "no active days", &problems)
        expectClose(emptySummary.averagePerActiveDay, 0, "average is 0, never NaN", &problems)
        expect(emptySummary.longest == nil, "no longest session", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 42

    private static func testPeriodLog() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)

        // Today: two visits four minutes apart — one session, two visits.
        let morning = today.addingTimeInterval(10 * 3_600)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: morning,
                                     end: morning.addingTimeInterval(1_200)))
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: morning.addingTimeInterval(1_440),
                                     end: morning.addingTimeInterval(2_400)))
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            let start = yesterday.addingTimeInterval(9 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.b", appName: "Beta",
                                         start: start,
                                         end: start.addingTimeInterval(1_800)))
        }

        let stats = PeriodStats(sessions: SessionArchive(directory: sessionDir,
                                                         now: { clock.value }),
                                usage: usage, now: { clock.value })
        let log = stats.log(for: .week, containing: base)
        expect(log.count == 2, "two grouped sessions across the week, got \(log.count)",
               &problems)
        expect((log.first?.session.start ?? .distantPast)
               > (log.last?.session.start ?? .distantFuture),
               "the log is reverse chronological", &problems)
        expect(log.first?.session.visits == 2,
               "the two visits group into one session, got "
               + "\(log.first?.session.visits ?? -1)", &problems)
        expectClose(log.first?.session.attended ?? -1, 2_160,
                    "attended excludes the four-minute gap", &problems)

        expect(stats.log(for: .day, containing: base).count == 1,
               "the day period sees only today's session", &problems)

        let totals = stats.dayTotals(for: .week, containing: base)
        expect(totals.count == 2, "two days with totals, got \(totals.count)", &problems)
        expectClose(totals.values.reduce(0, +), 2_160 + 1_800,
                    "day totals sum to the log", &problems)

        // The one-pass rollup is what the dashboard actually calls; it must not
        // drift from the piecewise accessors the tests above pin down.
        let rollup = stats.rollup(for: .week, containing: base)
        expect(rollup.days == stats.days(for: .week, containing: base),
               "rollup days match days()", &problems)
        expect(rollup.log == log, "rollup log matches log()", &problems)
        expect(rollup.dayTotals == totals, "rollup totals match dayTotals()", &problems)
        expect(rollup.summary == stats.summary(for: .week, containing: base),
               "rollup summary matches summary()", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 43

    private static func testAppPurpose() -> [String] {
        var problems: [String] = []

        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .active) == .coding,
               "Xcode is coding", &problems)
        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .passive) == .coding,
               "a fixed purpose ignores activity", &problems)
        expect(PurposeMap.purpose(for: "com.anthropic.claudefordesktop", activity: .passive)
               == .writingAI, "Claude is writing/AI", &problems)
        expect(PurposeMap.purpose(for: "com.figma.Desktop", activity: .active) == .design,
               "Figma is design", &problems)

        // The local stack, mapped so it never needs a manual correction. Bundle
        // identifiers read off the installed apps, not guessed.
        for id in ["dev.warp.Warp-Stable", "com.google.antigravity",
                   "com.google.antigravity-ide", "com.mongodb.compass",
                   "com.docker.docker", "com.todesktop.230313mzl4w4u92"] {
            expect(PurposeMap.purpose(for: id, activity: .passive) == .coding,
                   "\(id) is coding whatever the input", &problems)
            expect(CategoryManager.builtInMap[id] == .work,
                   "\(id) is work, so it never pauses a session", &problems)
        }
        // Dia is explicitly neutral: ambiguous purpose must not mean "pauses me".
        expect(CategoryManager.builtInMap["company.thebrowser.dia"] == .neutral,
               "Dia never pauses a session", &problems)
        expect(PurposeMap.purpose(for: "com.netflix.Netflix", activity: .active) == .media,
               "Netflix is media even while typing", &problems)

        // Unmapped falls to utility, not to a guess.
        expect(PurposeMap.purpose(for: "com.example.unknown", activity: .active) == .utility,
               "an unmapped bundle is a utility", &problems)
        expect(PurposeMap.purpose(for: nil, activity: .active) == .utility,
               "no bundle is a utility", &problems)

        // Ambiguous apps are decided by behaviour.
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .active) == .research,
               "Chrome with input is research", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .passive) == .media,
               "Chrome without input is media", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .absent) == .media,
               "an absent user is not doing research", &problems)
        expect(PurposeMap.purpose(for: "company.thebrowser.dia", activity: .active)
               == .writingAI, "Dia with input is writing/AI", &problems)

        // A user override wins over both the map and the behaviour.
        let overrides = ["com.google.Chrome": AppPurpose.coding.rawValue]
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .passive,
                                  overrides: overrides) == .coding,
               "an override beats the ambiguity rule", &problems)
        expect(PurposeMap.purpose(for: "com.example.unknown", activity: .passive,
                                  overrides: ["com.example.unknown": "media"]) == .media,
               "an override maps an unknown app", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .active,
                                  overrides: ["com.google.Chrome": "nonsense"]) == .research,
               "a corrupt override falls back to the rule", &problems)

        return problems
    }

    // MARK: - 44

    private static func testSessionKind() -> [String] {
        var problems: [String] = []

        expect(AppPurpose.coding.isFocused, "coding is focused work", &problems)
        expect(AppPurpose.writingAI.isFocused, "writing/AI is focused work", &problems)
        expect(AppPurpose.design.isFocused, "design is focused work", &problems)
        expect(!AppPurpose.research.isFocused,
               "research supports focus but is not focus on its own", &problems)
        expect(!AppPurpose.communication.isFocused, "communication is not focus", &problems)
        expect(!AppPurpose.media.isFocused, "media is not focus", &problems)
        expect(!AppPurpose.utility.isFocused, "a utility is not focus", &problems)

        // Every purpose has a distinct label and symbol, or the UI cannot draw it.
        var labels = Set<String>()
        var symbols = Set<String>()
        for purpose in AppPurpose.allCases {
            labels.insert(purpose.displayName)
            symbols.insert(purpose.symbolName)
            expect(!purpose.displayName.isEmpty, "\(purpose) has a label", &problems)
        }
        expect(labels.count == AppPurpose.allCases.count,
               "labels are distinct, got \(labels.count)", &problems)
        expect(symbols.count == AppPurpose.allCases.count,
               "symbols are distinct, got \(symbols.count)", &problems)

        return problems
    }

    // MARK: - 45

    private static func testInputDensity() -> [String] {
        var problems: [String] = []
        let start = base

        func feed(keys: UInt32, clicks: UInt32, scrolls: UInt32,
                  samples: Int, idle: TimeInterval = 0) -> InputDensity {
            let density = InputDensity()
            var k: UInt32 = 1_000, c: UInt32 = 50, s: UInt32 = 500
            for index in 0...samples {
                density.record(InputSample(at: start.addingTimeInterval(Double(index) * 20),
                                           keys: k, clicks: c, scrolls: s, idleSeconds: idle))
                k += keys; c += clicks; s += scrolls
            }
            return density
        }

        // One sample is not enough to measure a rate.
        let single = InputDensity()
        single.record(InputSample(at: start, keys: 0, clicks: 0, scrolls: 0, idleSeconds: 0))
        expect(single.activity == .passive,
               "a single sample cannot prove activity, got \(single.activity)", &problems)

        // 8 keys per 20s sample = 24/min, over the 12/min floor.
        expect(feed(keys: 8, clicks: 0, scrolls: 0, samples: 5).activity == .active,
               "sustained typing is active", &problems)

        // 2 keys per 20s = 6/min, under the floor, and no clicks.
        expect(feed(keys: 2, clicks: 0, scrolls: 0, samples: 5).activity == .passive,
               "occasional keys are not active", &problems)

        // Clicking with some keys is active: 2 clicks per 20s = 6/min.
        expect(feed(keys: 1, clicks: 2, scrolls: 0, samples: 5).activity == .active,
               "clicking with keys is active", &problems)

        // Clicking with no keys at all is not active — that is a video player.
        expect(feed(keys: 0, clicks: 2, scrolls: 0, samples: 5).activity == .passive,
               "clicks alone are not active", &problems)

        // Scrolling never qualifies: a film plays while a hand rests on a trackpad.
        expect(feed(keys: 0, clicks: 0, scrolls: 40, samples: 5).activity == .passive,
               "scrolling alone is passive", &problems)

        // Past the idle cutoff nobody is there, whatever the counters say.
        expect(feed(keys: 40, clicks: 40, scrolls: 40, samples: 5,
                    idle: AppUsageTracker.idleCutoff + 1).activity == .absent,
               "past the idle cutoff the user is absent", &problems)

        return problems
    }

    // MARK: - 46

    private static func testInputDensityRing() -> [String] {
        var problems: [String] = []
        let density = InputDensity()
        let start = base

        // Far more samples than the ring holds; memory must not grow.
        var keys: UInt32 = 0
        for index in 0..<(FocusConstants.densityRingSize * 10) {
            keys += 8
            density.record(InputSample(at: start.addingTimeInterval(Double(index) * 20),
                                       keys: keys, clicks: 0, scrolls: 0, idleSeconds: 0))
        }
        expect(density.sampleCount == FocusConstants.densityRingSize,
               "the ring is capped at \(FocusConstants.densityRingSize), got "
               + "\(density.sampleCount)", &problems)
        expect(density.activity == .active, "sustained typing is still active", &problems)

        // An absent sample clears the ring: the counters may have advanced from
        // synthetic events while nobody was there, and a delta measured across
        // that gap would be a lie.
        density.record(InputSample(at: start.addingTimeInterval(10_000),
                                   keys: keys + 5_000, clicks: 0, scrolls: 0,
                                   idleSeconds: AppUsageTracker.idleCutoff + 1))
        expect(density.sampleCount == 0, "absence clears the ring, got "
               + "\(density.sampleCount)", &problems)
        expect(density.activity == .absent, "and reports absence", &problems)

        // Coming back, the first sample after the gap cannot claim activity.
        density.record(InputSample(at: start.addingTimeInterval(10_020),
                                   keys: keys + 5_000, clicks: 0, scrolls: 0,
                                   idleSeconds: 0))
        expect(density.activity == .passive,
               "the first sample after a gap is not proof of activity", &problems)

        return problems
    }

    // MARK: - 47

    private static func testThreadIdentity() -> [String] {
        var problems: [String] = []

        // A record made the ordinary way gets its own thread.
        let a = SessionRecord(name: "Refactor", workType: .deepWork,
                              start: base, end: base.addingTimeInterval(600),
                              workSeconds: 600)
        let b = SessionRecord(name: "Refactor", workType: .deepWork,
                              start: base, end: base.addingTimeInterval(600),
                              workSeconds: 600)
        expect(a.threadID != b.threadID,
               "two independent records are two threads", &problems)

        let thread = UUID()
        let joined = SessionRecord(name: "Refactor", workType: .deepWork,
                                   start: base, end: base.addingTimeInterval(600),
                                   workSeconds: 600, threadID: thread)
        expect(joined.threadID == thread, "an explicit thread is kept", &problems)

        guard let encoded = try? JSONEncoder().encode(joined),
              let decoded = try? JSONDecoder().decode(SessionRecord.self, from: encoded) else {
            problems.append("a record with a thread must round-trip")
            return problems
        }
        expect(decoded.threadID == thread, "the thread survives a round-trip", &problems)

        // Legacy JSON written before threads existed must still decode, each
        // record becoming its own single-segment thread — the truth about it.
        func legacyBlob() -> Data {
            Data("""
            {"id":"\(UUID().uuidString)","name":"Old","workType":"deepWork",
             "start":0,"end":600,"workSeconds":600}
            """.utf8)
        }
        guard let old = try? JSONDecoder().decode(SessionRecord.self, from: legacyBlob()),
              let otherOld = try? JSONDecoder().decode(SessionRecord.self,
                                                       from: legacyBlob()) else {
            problems.append("legacy JSON without threadID must decode")
            return problems
        }
        expect(old.name == "Old", "legacy fields still decode", &problems)
        expect(old.threadID != otherOld.threadID,
               "each legacy record is its own thread", &problems)

        return problems
    }

    // MARK: - 48

    private static func testThreadContinuity() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Refactor")
        let first = engine.activeThreadID
        clock.value = base.addingTimeInterval(600)
        engine.stop()

        guard let firstRecord = engine.archive.records.last else {
            problems.append("the first session must be archived")
            return problems
        }
        expect(firstRecord.threadID == first,
               "the archived record carries the engine's thread", &problems)

        // Continuing reuses the thread.
        clock.value = base.addingTimeInterval(3_600)
        engine.start(workType: .deepWork, intent: "Refactor", threadID: first)
        expect(engine.activeThreadID == first, "continuing adopts the thread", &problems)
        clock.value = base.addingTimeInterval(4_200)
        engine.stop()
        expect(engine.archive.records.last?.threadID == first,
               "the second segment joins the thread", &problems)
        expect(engine.archive.records.count == 2,
               "two segments, two records — the gap is never worked time", &problems)

        // Starting fresh does not.
        clock.value = base.addingTimeInterval(7_200)
        engine.start(workType: .admin, intent: "Email")
        expect(engine.activeThreadID != first,
               "an unrelated session is a new thread", &problems)
        clock.value = base.addingTimeInterval(7_800)
        engine.stop()

        // Restarting mid-session must not lose the link: the thread has to
        // survive the snapshot, not merely live in memory.
        clock.value = base.addingTimeInterval(10_000)
        engine.start(workType: .deepWork, intent: "Refactor", threadID: first)
        guard let blob = try? JSONEncoder().encode(engine.snapshot()),
              let snapshot = try? JSONDecoder().decode(PersistedState.self, from: blob) else {
            problems.append("the snapshot must round-trip")
            return problems
        }
        let restored = SessionEngine(store: engine.store,
                                     archive: engine.archive,
                                     ownBundleID: FocusConstants.bundleIdentifier,
                                     schedulesDwell: false,
                                     now: { clock.value })
        restored.restore(from: snapshot)
        expect(restored.activeThreadID == first,
               "the thread survives a relaunch mid-session", &problems)

        return problems
    }

    // MARK: - 49

    private static func testThreadSummaries() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let sessionDir = scratchDirectory(), usageDir = scratchDirectory()
        let archive = SessionArchive(directory: sessionDir, now: { clock.value })
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)
        let thread = UUID()

        // Two segments of one thread, plus an unrelated session between them.
        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: today.addingTimeInterval(9 * 3_600),
                                     end: today.addingTimeInterval(9 * 3_600 + 3_600),
                                     workSeconds: 3_600, threadID: thread))
        archive.append(SessionRecord(name: "Email", workType: .admin,
                                     start: today.addingTimeInterval(11 * 3_600),
                                     end: today.addingTimeInterval(11 * 3_600 + 600),
                                     workSeconds: 600))
        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: today.addingTimeInterval(13 * 3_600),
                                     end: today.addingTimeInterval(13 * 3_600 + 1_800),
                                     workSeconds: 1_800, threadID: thread))

        // A recorded break is not a thread to continue.
        archive.append(SessionRecord(name: "Break", workType: .breakTime,
                                     start: today.addingTimeInterval(12 * 3_600),
                                     end: today.addingTimeInterval(12 * 3_600 + 900),
                                     workSeconds: 900))

        let stats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        let threads = stats.threads(on: base, running: nil)

        expect(threads.count == 2, "two threads today, got \(threads.count)", &problems)
        expect(!threads.contains { $0.workType == .breakTime },
               "a break is never offered to continue", &problems)
        guard let refactor = threads.first(where: { $0.threadID == thread }) else {
            problems.append("the refactor thread must be present")
            return problems
        }
        expect(refactor.segments == 2, "two segments, got \(refactor.segments)", &problems)
        expectClose(refactor.totalWorked, 5_400,
                    "worked time sums across segments", &problems)
        expect(refactor.name == "Refactor", "the thread takes the segment name", &problems)
        expect(!refactor.isRunning, "nothing is running", &problems)

        // Ordered by last end, newest first: refactor ended at 13:30, email 11:10.
        expect(threads.first?.threadID == thread,
               "the most recently touched thread comes first", &problems)

        // The running session is included and marked, the same rule
        // `sessionsToday` already follows — one surface must never disagree
        // with another.
        clock.value = today.addingTimeInterval(15 * 3_600 + 900)
        let live = RunningThread(threadID: thread, name: "Refactor",
                                 workType: .deepWork,
                                 start: today.addingTimeInterval(15 * 3_600),
                                 worked: 900)
        let withRunning = stats.threads(on: base, running: live)
        guard let merged = withRunning.first(where: { $0.threadID == thread }) else {
            problems.append("the running thread must be present")
            return problems
        }
        expect(merged.segments == 3, "the running segment counts, got \(merged.segments)",
               &problems)
        expectClose(merged.totalWorked, 6_300, "and its time counts", &problems)
        expect(merged.isRunning, "and it is marked running", &problems)

        // A running session on a brand-new thread appears as its own thread.
        let fresh = RunningThread(threadID: UUID(), name: "Design", workType: .deepWork,
                                  start: today.addingTimeInterval(16 * 3_600), worked: 300)
        expect(stats.threads(on: base, running: fresh).count == 3,
               "a new running thread is a third thread", &problems)

        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }

    // MARK: - 50

    private static func testThreadApps() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let sessionDir = scratchDirectory(), usageDir = scratchDirectory()
        let archive = SessionArchive(directory: sessionDir, now: { clock.value })
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)
        let thread = UUID()
        let segmentStart = today.addingTimeInterval(9 * 3_600)

        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: segmentStart,
                                     end: segmentStart.addingTimeInterval(3_600),
                                     workSeconds: 3_600, threadID: thread))

        // Inside the segment: Chrome longest, Xcode second, Terminal third,
        // Finder a flicker.
        usage.record(AppUsageSession(bundleID: "com.google.Chrome", appName: "Chrome",
                                     start: segmentStart,
                                     end: segmentStart.addingTimeInterval(1_800)))
        usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                     start: segmentStart.addingTimeInterval(1_800),
                                     end: segmentStart.addingTimeInterval(3_000)))
        usage.record(AppUsageSession(bundleID: "com.apple.Terminal", appName: "Terminal",
                                     start: segmentStart.addingTimeInterval(3_000),
                                     end: segmentStart.addingTimeInterval(3_400)))
        usage.record(AppUsageSession(bundleID: "com.apple.finder", appName: "Finder",
                                     start: segmentStart.addingTimeInterval(3_400),
                                     end: segmentStart.addingTimeInterval(3_410)))
        // Outside the segment entirely — must not appear at all.
        usage.record(AppUsageSession(bundleID: "com.netflix.Netflix", appName: "Netflix",
                                     start: today.addingTimeInterval(20 * 3_600),
                                     end: today.addingTimeInterval(20 * 3_600 + 3_600)))

        let stats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        guard let summary = stats.threads(on: base, running: nil).first else {
            problems.append("the thread must be present")
            return problems
        }
        let apps = stats.apps(for: summary, on: base)

        // Chrome has the most time, but Xcode is the focused-purpose app and so
        // is what the session was actually *for*.
        expect(apps.primary?.bundleID == "com.apple.dt.Xcode",
               "the primary app is the focused-purpose one, got "
               + "\(apps.primary?.bundleID ?? "nil")", &problems)
        expectClose(apps.primary?.total ?? -1, 1_200, "with its own attended time", &problems)

        let sideIDs = apps.side.map(\.bundleID)
        expect(sideIDs.contains("com.google.Chrome"), "Chrome is a side app", &problems)
        expect(sideIDs.contains("com.apple.Terminal"), "Terminal is a side app", &problems)
        expect(!sideIDs.contains("com.apple.finder"),
               "a ten-second flicker is below the floor", &problems)
        expect(!sideIDs.contains("com.netflix.Netflix"),
               "an app used outside the segment is not a side app", &problems)
        expect(!sideIDs.contains("com.apple.dt.Xcode"),
               "the primary app is not also a side app", &problems)
        expect(sideIDs.first == "com.google.Chrome",
               "side apps rank by attended time", &problems)

        // With no focused-purpose app at all, the most-attended one leads.
        let plainThread = UUID()
        let plainStart = today.addingTimeInterval(14 * 3_600)
        archive.append(SessionRecord(name: "Reading", workType: .learning,
                                     start: plainStart,
                                     end: plainStart.addingTimeInterval(1_800),
                                     workSeconds: 1_800, threadID: plainThread))
        usage.record(AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                     start: plainStart,
                                     end: plainStart.addingTimeInterval(1_500)))
        let plainStats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        if let plain = plainStats.threads(on: base, running: nil)
            .first(where: { $0.threadID == plainThread }) {
            expect(plainStats.apps(for: plain, on: base).primary?.bundleID
                   == "com.apple.Safari",
                   "with no focused app the most-attended one leads", &problems)
        } else {
            problems.append("the reading thread must be present")
        }

        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }

    // MARK: - 51

    private static func testContinueThread() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        let usageDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })

        engine.start(workType: .learning, intent: "Read the paper")
        let thread = engine.activeThreadID
        clock.value = base.addingTimeInterval(1_200)
        engine.stop()

        // A different session runs in between and must be archived, not lost,
        // when the earlier thread is continued.
        clock.value = base.addingTimeInterval(2_000)
        engine.start(workType: .admin, intent: "Email")
        clock.value = base.addingTimeInterval(2_300)

        guard let summary = ThreadStats(sessions: engine.archive, usage: usage,
                                        now: { clock.value })
            .threads(on: base, running: nil)
            .first(where: { $0.threadID == thread }) else {
            problems.append("the earlier thread must be findable")
            try? FileManager.default.removeItem(at: usageDir)
            return problems
        }

        engine.start(workType: summary.workType, intent: summary.name,
                     threadID: summary.threadID)
        expect(engine.activeThreadID == thread, "the thread is adopted", &problems)
        expect(engine.activeWorkType == .learning, "the work type comes back", &problems)
        expect(engine.sessionName == "Read the paper",
               "the name comes back, got \(engine.sessionName)", &problems)
        expect(engine.archive.records.contains { $0.name == "Email" },
               "the interrupted session was archived, not discarded", &problems)

        clock.value = base.addingTimeInterval(3_000)
        engine.stop()
        let segments = engine.archive.records.filter { $0.threadID == thread }
        expect(segments.count == 2, "the thread now has two segments, got "
               + "\(segments.count)", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }

    // MARK: - 52

    private static func testFocusScore() -> [String] {
        var problems: [String] = []
        let scorer = FocusScorer()
        // 15 minutes, matching FocusConstants.focusWindow.
        let window = (start: base, end: base.addingTimeInterval(900))

        // Media veto: Netflix carries most of the window even though Warp is coding.
        let mediaSegments = [
            AppUsageSession(bundleID: "com.netflix.Netflix", appName: "Netflix",
                            start: base, end: base.addingTimeInterval(600)),
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base.addingTimeInterval(600), end: base.addingTimeInterval(900))
        ]
        let vetoed = scorer.score(segments: mediaSegments, activity: .active, window: window)
        expect(vetoed.value == 0, "media veto forces the score to zero, got \(vetoed.value)", &problems)
        expectClose(vetoed.signals.mediaShare, 600.0 / 900.0,
                   "media share is still reported honestly", &problems)
        expectClose(vetoed.signals.focusedShare, 300.0 / 900.0,
                   "focused share is still reported honestly", &problems)
        expect(vetoed.explanation.contains("media"),
              "explanation notes the veto, got '\(vetoed.explanation)'", &problems)

        // Passive scores lower than active for identical segments.
        let steadySegments = [
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base, end: base.addingTimeInterval(900))
        ]
        let activeScore = scorer.score(segments: steadySegments, activity: .active, window: window)
        let passiveScore = scorer.score(segments: steadySegments, activity: .passive, window: window)
        expectClose(activeScore.value, 1.0, "active, single app, no churn scores at full focus", &problems)
        expectClose(passiveScore.value, 0.4, "passive weight is 0.4", &problems)
        expect(activeScore.value > passiveScore.value,
              "active must outscore passive for identical input", &problems)

        // Heavy churn reduces the score even with the same focused share and activity.
        let churnCount = 46
        let step = 900.0 / Double(churnCount)
        var churnSegments: [AppUsageSession] = []
        for index in 0..<churnCount {
            let segStart = base.addingTimeInterval(Double(index) * step)
            let segEnd = base.addingTimeInterval(Double(index + 1) * step)
            churnSegments.append(AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                                                 start: segStart, end: segEnd))
        }
        let churnScore = scorer.score(segments: churnSegments, activity: .active, window: window)
        // (46 - 1) / 15min = 3.0 switches/min; (3.0 - 2.0 calm) * 0.15 penalty = 0.15.
        expectClose(churnScore.signals.switchesPerMinute, 3.0,
                   "switch rate for 46 segments over 15m", &problems)
        expectClose(churnScore.value, 0.85, "churn penalty lowers the score", &problems)
        expect(churnScore.value < activeScore.value,
              "heavy churn must score lower than the equivalent calm stretch", &problems)

        // An empty window returns zero without dividing by zero.
        let empty = scorer.score(segments: [], activity: .active, window: window)
        expect(empty == FocusScore.zero, "no segments yields FocusScore.zero", &problems)
        let outside = [
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base.addingTimeInterval(-3_600), end: base.addingTimeInterval(-1_800))
        ]
        let noOverlap = scorer.score(segments: outside, activity: .active, window: window)
        expect(noOverlap == FocusScore.zero,
              "segments entirely outside the window also yield zero", &problems)

        // Explanation names the dominant app.
        let namedSegments = [
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base, end: base.addingTimeInterval(360))
        ]
        let named = scorer.score(segments: namedSegments, activity: .active, window: window)
        expect(named.explanation.contains("Warp"),
              "explanation names the dominant app, got '\(named.explanation)'", &problems)
        expect(named.explanation.contains("6m"),
              "explanation states the dominant app's attended minutes, got '\(named.explanation)'",
              &problems)
        expect(named.signals.dominantApp == "dev.warp.Warp-Stable", "dominantApp is the bundle ID",
              &problems)
        expect(named.signals.dominantAppName == "Warp", "dominantAppName is the app name", &problems)
        expect(named.signals.dominantPurpose == .coding, "dominantPurpose is Warp's purpose", &problems)

        return problems
    }

    // MARK: - 53

    // MARK: - (N)

    /// The daily goal must judge "on track" against the user's own recent
    /// history at this same hour, not against the clock or the raw target.
    private static func testDailyGoal() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: base)
        let current = dayStart.addingTimeInterval(10 * 3_600)   // "now" is 10am
        clock.value = current

        func addDay(offset: Int, hours: Double) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else {
                return
            }
            let start = calendar.startOfDay(for: day).addingTimeInterval(9 * 3_600)
            archive.append(SessionRecord(name: "s", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval(hours * 3_600),
                                         workSeconds: hours * 3_600))
        }

        let todayStart = dayStart.addingTimeInterval(9 * 3_600)
        archive.append(SessionRecord(name: "s", workType: .deepWork,
                                     start: todayStart, end: todayStart.addingTimeInterval(3_600),
                                     workSeconds: 3_600))
        // The goal is the intersection of "a session ran" and "you were at the
        // keyboard", so the fixture has to supply both halves. Without the
        // hands-on side it reads zero — correctly, since an archived session
        // with no record of anyone using the machine is not evidence of work.
        let handsOn = [AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                       start: todayStart,
                                       end: todayStart.addingTimeInterval(3_600))]

        // Only two active days in history — below the 3-day minimum.
        addDay(offset: 1, hours: 0.5)
        addDay(offset: 2, hours: 0.5)

        let underGoal = DailyGoal(archive: archive, goal: 2 * 3_600,
                                  usage: handsOn, now: { clock.value }).progress()
        expectClose(underGoal.achieved, 3_600, "under-goal achieved", &problems)
        expectClose(underGoal.share, 0.5, "under-goal share", &problems)
        expect(!underGoal.isMet, "1h against a 2h goal should not be met", &problems)
        expect(underGoal.typicalByNow == nil, "two active days is below the minimum", &problems)
        expect(underGoal.aheadBy == nil, "aheadBy must be nil when typicalByNow is nil", &problems)

        // An archived session with no hands-on time behind it fills nothing —
        // the rule that stops a wall-clock session from claiming a goal.
        let unattended = DailyGoal(archive: archive, goal: 2 * 3_600,
                                   now: { clock.value }).progress()
        expectClose(unattended.achieved, 0,
                    "a session nobody was present for fills no goal", &problems)

        let overGoal = DailyGoal(archive: archive, goal: 1_800,
                                 usage: handsOn, now: { clock.value }).progress()
        expectClose(overGoal.share, 2.0, "over-goal share is uncapped", &problems)
        expect(overGoal.isMet, "1h against a 30m goal should be met", &problems)

        try? FileManager.default.removeItem(at: dir)

        // Five active days with a clean median, plus two inactive days inside
        // the same window that must not drag the median down.
        let dir2 = scratchDirectory()
        let archive2 = SessionArchive(directory: dir2, now: { clock.value })
        let todayStart2 = dayStart.addingTimeInterval(9 * 3_600)
        archive2.append(SessionRecord(name: "s", workType: .deepWork,
                                      start: todayStart2, end: todayStart2.addingTimeInterval(3_600),
                                      workSeconds: 3_600))

        func addDay2(offset: Int, minutesByNow: Double) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else {
                return
            }
            let start = calendar.startOfDay(for: day).addingTimeInterval(9 * 3_600)
            archive2.append(SessionRecord(name: "s", workType: .deepWork,
                                          start: start,
                                          end: start.addingTimeInterval(minutesByNow * 60),
                                          workSeconds: minutesByNow * 60))
        }
        // Active days at offsets 1-5 reach 10, 50, 30, 40, 20 minutes by 10am;
        // sorted that is 10/20/30/40/50 so the median is 30 minutes. Offsets 6
        // and 7 (inside the 14-day window) are left with no records at all —
        // if they were folded in as zeros the median would drop to 20 minutes
        // instead of staying at 30, so this assertion also covers that rule.
        addDay2(offset: 1, minutesByNow: 10)
        addDay2(offset: 2, minutesByNow: 50)
        addDay2(offset: 3, minutesByNow: 30)
        addDay2(offset: 4, minutesByNow: 40)
        addDay2(offset: 5, minutesByNow: 20)

        let handsOn2 = [AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                        start: todayStart2,
                                        end: todayStart2.addingTimeInterval(3_600))]
        let goal2 = DailyGoal(archive: archive2, goal: 3_600,
                              usage: handsOn2, now: { clock.value }).progress()
        expect(goal2.typicalByNow != nil, "five active days should be enough for a median",
               &problems)
        if let typical = goal2.typicalByNow {
            expectClose(typical, 30 * 60, "median of five active days", &problems)
        }
        expect(goal2.aheadBy != nil, "aheadBy should exist once typicalByNow exists", &problems)
        if let ahead = goal2.aheadBy {
            expectClose(ahead, 3_600 - 30 * 60, "aheadBy is achieved minus the median", &problems)
        }

        try? FileManager.default.removeItem(at: dir2)
        return problems
    }

    /// Shared by tests 54 and 55: a score with only the fields the
    /// detector reads, so a test never depends on the scorer's arithmetic.
    private static func makeFocusScore(_ value: Double,
                                        purpose: AppPurpose = .coding,
                                        explanation: String = "test") -> FocusScore {
        let signals = FocusSignals(focusedShare: value, mediaShare: 0, activity: .active,
                                   switchesPerMinute: 0, attended: 60,
                                   dominantPurpose: purpose, dominantApp: "com.test.app",
                                   dominantAppName: "Test")
        return FocusScore(value: value, signals: signals, explanation: explanation)
    }

    // MARK: - 54

    private static func testAutoSessionDetector() -> [String] {
        var problems: [String] = []
        let t0 = base
        let highScore = makeFocusScore(0.8, purpose: .coding, explanation: "Warp 5m")

        // Starts only after sustained qualification, not on a single high reading.
        var detector = AutoSessionDetector(breakLength: 600)
        var d = detector.evaluate(score: highScore, at: t0, sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(d == .none, "a single high reading is not enough to start", &problems)

        d = detector.evaluate(score: highScore, at: t0.addingTimeInterval(240),
                              sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(d == .none, "240s of qualification is still short of the 300s dwell", &problems)

        d = detector.evaluate(score: highScore, at: t0.addingTimeInterval(300),
                              sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        if case .start(let workType, _, let backdatedTo, let because) = d {
            expect(workType == .deepWork, "coding purpose maps to deep work", &problems)
            expect(backdatedTo == t0,
                  "backdated to when the qualifying run began, not the decision moment", &problems)
            expect(because == highScore.explanation, "because carries the score's explanation", &problems)
        } else {
            problems.append("expected .start after sustained qualification, got \(d)")
        }

        // A dip below threshold resets the run — verified with a fresh detector.
        var resetter = AutoSessionDetector(breakLength: 600)
        _ = resetter.evaluate(score: highScore, at: t0, sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        let lowScore = makeFocusScore(0.2, explanation: "idle")
        _ = resetter.evaluate(score: lowScore, at: t0.addingTimeInterval(200),
                              sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        let afterDip = resetter.evaluate(score: highScore, at: t0.addingTimeInterval(200 + 300),
                                         sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(afterDip == .none, "a dip below threshold resets the qualifying run", &problems)

        // A hand-started session is never touched, whatever the score does.
        var handsOff = AutoSessionDetector(breakLength: 600)
        let untouched1 = handsOff.evaluate(score: lowScore, at: t0, sessionRunning: true, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(untouched1 == .none, "a hand-started session is never paused", &problems)
        let stillHigh = makeFocusScore(0.9)
        let untouched2 = handsOff.evaluate(score: stillHigh, at: t0.addingTimeInterval(10_000),
                                           sessionRunning: true, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(untouched2 == .none, "a hand-started session is never ended either", &problems)

        // Media/low score pauses rather than ends, and a pause that outlives
        // breakLength ends at the moment the pause began.
        var running = AutoSessionDetector(breakLength: 600)
        _ = running.evaluate(score: highScore, at: t0, sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        let started = running.evaluate(score: highScore, at: t0.addingTimeInterval(300),
                                       sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        guard case .start = started else {
            problems.append("setup failed: expected the session to auto-start")
            return problems
        }
        let startMoment = t0.addingTimeInterval(300)

        // Too soon after starting: rule 4 protects it even though score has cratered.
        let mediaScore = makeFocusScore(0.1, purpose: .media, explanation: "Netflix 10m · media")
        let tooSoon = running.evaluate(score: mediaScore, at: startMoment.addingTimeInterval(60),
                                       sessionRunning: true, sessionWasAutoStarted: true,
                                       enginePaused: false)
        expect(tooSoon == .none, "one minute in is inside autoMinRunDwell, so no pause yet", &problems)

        let pauseMoment = startMoment.addingTimeInterval(FocusConstants.autoMinRunDwell + 30)
        let paused = running.evaluate(score: mediaScore, at: pauseMoment,
                                      sessionRunning: true, sessionWasAutoStarted: true,
                                       enginePaused: false)
        if case .pause(let because) = paused {
            expect(because == mediaScore.explanation, "pause explanation carries the score's reason", &problems)
        } else {
            problems.append("expected .pause once the score dropped and min run dwell had passed, got \(paused)")
        }

        // Still within the break allowance: stays paused, no repeat decision.
        let stillPaused = running.evaluate(score: mediaScore, at: pauseMoment.addingTimeInterval(300),
                                           sessionRunning: true, sessionWasAutoStarted: true,
                                           enginePaused: true)
        expect(stillPaused == .none, "a pause shorter than breakLength does not end the session", &problems)

        // Outlives the break length: ends, backdated to when the pause began.
        let endMoment = pauseMoment.addingTimeInterval(601)
        let ended = running.evaluate(score: mediaScore, at: endMoment,
                                     sessionRunning: true, sessionWasAutoStarted: true,
                                     enginePaused: true)
        if case .end(let at, _) = ended {
            expect(at == pauseMoment,
                  "end is backdated to when the pause began, not the timeout moment", &problems)
        } else {
            problems.append("expected .end once the pause outlived breakLength, got \(ended)")
        }

        return problems
    }

    // MARK: - 55

    private static func testAutoSessionHysteresis() -> [String] {
        var problems: [String] = []
        var detector = AutoSessionDetector(breakLength: 600)
        let t0 = base
        // Both readings sit strictly between autoStopThreshold (0.35) and
        // autoStartThreshold (0.65) — the flapping zone. Alternate across far
        // more evaluations than any dwell constant so a bug that averages, or
        // that treats "not below start" as "above stop", gets every chance to
        // show up.
        let low = makeFocusScore(0.5, explanation: "drifting")
        let high = makeFocusScore(0.6, explanation: "drifting")
        var moment = t0
        for i in 0..<200 {
            let score = (i % 2 == 0) ? low : high
            let decision = detector.evaluate(score: score, at: moment,
                                             sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
            expect(decision == .none,
                  "evaluation \(i) at \(moment.timeIntervalSince(t0))s in the hysteresis band produced \(decision)",
                  &problems)
            moment = moment.addingTimeInterval(30)
        }
        // 200 * 30s = 6000s (100 minutes), comfortably past autoStartDwell (300s),
        // autoMinRunDwell (180s), and the 600s breakLength used elsewhere.
        return problems
    }

    // MARK: - 56

    // MARK: - RewardEngine

    /// Reward engine: gating rules must skip fabricated comparisons and never nag.
    private static func testRewardEngine() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)

        func neutralGoal(goal: TimeInterval = 4 * 3_600, achieved: TimeInterval = 0,
                         typicalByNow: TimeInterval? = nil) -> GoalProgress {
            GoalProgress(goal: goal, achieved: achieved, typical: typicalByNow)
        }

        func neutralContext(focusedToday: TimeInterval = 0,
                            sameWeekdayLastWeek: TimeInterval? = nil,
                            streak: Int = 0, bestStreak: Int = 0,
                            goal: GoalProgress = neutralGoal(),
                            endedMedia: (appName: String, seconds: TimeInterval)? = nil,
                            musicPairing: TimeInterval? = nil,
                            isSessionRunning: Bool = false) -> RewardContext {
            RewardContext(focusedToday: focusedToday, sameWeekdayLastWeek: sameWeekdayLastWeek,
                         streak: streak, bestStreak: bestStreak, goal: goal,
                         endedMedia: endedMedia, musicPairing: musicPairing,
                         isSessionRunning: isSessionRunning)
        }

        // No streakRecord when the streak merely equals the best.
        let tiedStreak = neutralContext(streak: 3, bestStreak: 3)
        let tiedEngine = RewardEngine(log: [:], now: { clock.value })
        expect(tiedEngine.next(for: tiedStreak) == nil,
               "a tied streak must not fire a record", &problems)

        // No goalPace when aheadBy is nil, even though achieved looks generous.
        let noAheadGoal = neutralGoal(achieved: 3_000, typicalByNow: nil)
        let noAheadContext = neutralContext(goal: noAheadGoal)
        let noAheadEngine = RewardEngine(log: [:], now: { clock.value })
        expect(noAheadEngine.next(for: noAheadContext) == nil,
               "goalPace must not fire without a real aheadBy figure", &problems)

        // Milestone: comparison omitted when there is no same-weekday figure...
        let milestoneNoCompare = neutralContext(focusedToday: 3_700, isSessionRunning: true)
        let milestoneEngine = RewardEngine(log: [:], now: { clock.value })
        if let reward = milestoneEngine.next(for: milestoneNoCompare) {
            expect(reward.kind == .milestone, "expected a milestone reward, got \(reward.kind)",
                   &problems)
            expect(!reward.detail.contains("last week"),
                   "detail must not claim a comparison it has no data for: \(reward.detail)",
                   &problems)
        } else {
            problems.append("an hour of running focus should fire a milestone")
        }

        // ...and included when it is present.
        let milestoneCompare = neutralContext(focusedToday: 3_700, sameWeekdayLastWeek: 2_000,
                                              isSessionRunning: true)
        let milestoneCompareEngine = RewardEngine(log: [:], now: { clock.value })
        if let reward = milestoneCompareEngine.next(for: milestoneCompare) {
            expect(reward.detail.contains("last week"),
                   "detail should carry the comparison once real data exists: \(reward.detail)",
                   &problems)
        } else {
            problems.append("an hour of running focus with a comparison should fire a milestone")
        }

        // A media stretch under the ten-minute floor produces nothing.
        let shortMedia = neutralContext(endedMedia: (appName: "Trailer", seconds: 300))
        let shortMediaEngine = RewardEngine(log: [:], now: { clock.value })
        expect(shortMediaEngine.next(for: shortMedia) == nil,
               "a sub-ten-minute media stretch must not fire", &problems)

        // A media stretch at or above the floor does.
        let longMedia = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let longMediaEngine = RewardEngine(log: [:], now: { clock.value })
        expect(longMediaEngine.next(for: longMedia)?.kind == .mediaEnded,
               "a ten-minute-plus media stretch should fire mediaEnded", &problems)

        // Fixed times comfortably inside one calendar day, away from midnight,
        // so calendar.isDate(inSameDayAs:) checks are never accidentally tripped
        // by timezone edge effects.
        let refDay = Calendar.current.startOfDay(for: base).addingTimeInterval(14 * 3_600)

        // Per-day cap: once the log already has rewardsPerDay entries today,
        // nothing more fires even for an otherwise-eligible candidate.
        var fullLog: [String: Date] = [:]
        for (index, kind) in [RewardKind.goalReached, .streakRecord, .milestone, .goalPace]
            .enumerated() {
            fullLog[kind.rawValue] = refDay.addingTimeInterval(-Double(index + 1) * 3_600)
        }
        let cappedContext = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let cappedEngine = RewardEngine(log: fullLog, now: { refDay })
        expect(cappedEngine.next(for: cappedContext) == nil,
               "the daily cap must block a fifth reward even with a fresh candidate",
               &problems)

        // Same-kind-once-per-day: a kind that already fired today must not fire
        // again today, even with nothing else competing for the slot.
        let sameKindLog: [String: Date] = [RewardKind.mediaEnded.rawValue:
                                           refDay.addingTimeInterval(-4 * 3_600)]
        let sameKindContext = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let sameKindEngine = RewardEngine(log: sameKindLog, now: { refDay })
        expect(sameKindEngine.next(for: sameKindContext) == nil,
               "mediaEnded must not fire twice in the same day", &problems)

        // Cooldown: a log rebuilt from persisted values (as after a relaunch)
        // with its most recent entry inside the cooldown window blocks the next
        // reward, whatever kind it is.
        let cooldownLog: [String: Date] = [RewardKind.workWithMusic.rawValue:
                                           refDay.addingTimeInterval(-10 * 60)]
        let cooldownContext = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let cooldownEngine = RewardEngine(log: cooldownLog, now: { refDay })
        expect(cooldownEngine.next(for: cooldownContext) == nil,
               "a reward inside the cooldown window must block the next one", &problems)

        // Outside the cooldown window, the same setup fires normally.
        let clearLog: [String: Date] = [RewardKind.workWithMusic.rawValue:
                                        refDay.addingTimeInterval(-FocusConstants.rewardCooldown - 60)]
        let clearEngine = RewardEngine(log: clearLog, now: { refDay })
        expect(clearEngine.next(for: cooldownContext)?.kind == .mediaEnded,
               "once outside the cooldown, a new reward should fire", &problems)

        return problems
    }

    // MARK: - 57

    /// Regression for the worst defect the final review found: a qualifying run
    /// begun before the user pressed Start survived the whole manual session and
    /// fired the instant it ended, backdated across work already archived —
    /// double-counting hours into the day's total.
    private static func testNoStaleQualifyingRun() -> [String] {
        var problems: [String] = []
        var detector = AutoSessionDetector(breakLength: 600)
        let high = makeFocusScore(0.8, purpose: .coding, explanation: "Warp 5m")
        let t0 = base

        // Working, but not yet long enough to auto-start.
        _ = detector.evaluate(score: high, at: t0, sessionRunning: false,
                              sessionWasAutoStarted: false, enginePaused: false)

        // The user presses Start by hand and works for two hours.
        for minutes in stride(from: 3, through: 120, by: 15) {
            let decision = detector.evaluate(score: high,
                                             at: t0.addingTimeInterval(Double(minutes) * 60),
                                             sessionRunning: true,
                                             sessionWasAutoStarted: false,
                                             enginePaused: false)
            expect(decision == .none, "a hand-started session is never touched", &problems)
        }

        // They stop. The very next evaluation must not fire instantly.
        let afterStop = detector.evaluate(score: high, at: t0.addingTimeInterval(121 * 60),
                                          sessionRunning: false,
                                          sessionWasAutoStarted: false, enginePaused: false)
        expect(afterStop == .none,
               "the first evaluation after a manual session must not auto-start, got "
               + "\(afterStop)", &problems)

        // It must serve a fresh dwell, and backdate no further than that.
        let restart = t0.addingTimeInterval(121 * 60)
        let tooSoon = detector.evaluate(score: high, at: restart.addingTimeInterval(240),
                                        sessionRunning: false,
                                        sessionWasAutoStarted: false, enginePaused: false)
        expect(tooSoon == .none, "the new run must serve the full dwell", &problems)
        let fired = detector.evaluate(score: high,
                                      at: restart.addingTimeInterval(FocusConstants.autoStartDwell),
                                      sessionRunning: false,
                                      sessionWasAutoStarted: false, enginePaused: false)
        if case .start(_, _, let backdatedTo, _) = fired {
            expect(backdatedTo >= restart,
                   "backdating must not reach behind the manual session", &problems)
        } else {
            problems.append("expected a start after a fresh dwell, got \(fired)")
        }

        // And an undone session cannot immediately return.
        detector.suppressStarts(until: restart.addingTimeInterval(3_600))
        let suppressed = detector.evaluate(score: high,
                                           at: restart.addingTimeInterval(1_800),
                                           sessionRunning: false,
                                           sessionWasAutoStarted: false, enginePaused: false)
        expect(suppressed == .none, "a rejected session stays rejected", &problems)

        return problems
    }

    // MARK: - 58

    private static func testAdoptAndSystemProcesses() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        // An automatic session is running.
        engine.start(workType: .deepWork, intent: "", isAuto: true)
        let thread = engine.activeThreadID
        clock.value = base.addingTimeInterval(1_800)

        // Pressing Start on the same kind of work continues it: same session,
        // same thread, clock untouched, nothing archived.
        expect(engine.wouldAdopt(workType: .deepWork), "same work type adopts", &problems)
        engine.adopt(intent: "Refactor the parser")
        expectClose(engine.elapsed, 1_800, "adopting does not reset the clock", &problems)
        expect(engine.archive.records.isEmpty, "adopting archives nothing", &problems)
        expect(engine.activeThreadID == thread, "the thread survives", &problems)
        expect(engine.sessionName == "Refactor the parser", "the intent is taken", &problems)
        expect(!engine.activeIsAuto,
               "a claimed session is the user's, so the app may not end it", &problems)

        // A different work type is different work: that starts a new session.
        expect(!engine.wouldAdopt(workType: .meetings),
               "a different work type does not adopt", &problems)
        engine.start(workType: .meetings, intent: "Standup")
        expect(engine.archive.records.count == 1,
               "starting different work archives the previous session", &problems)
        expect(engine.activeThreadID != thread, "and begins a new thread", &problems)

        // The lock screen is never app usage, however long it is frontmost.
        let usageDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.value = base.addingTimeInterval(3_600)
        tracker.appActivated(bundleID: "com.apple.loginwindow", name: "loginwindow")
        clock.value = base.addingTimeInterval(3_600 + 6 * 3_600)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        tracker.flush()

        expect(!usage.sessions.contains { $0.bundleID == "com.apple.loginwindow" },
               "six hours at the lock screen is not six hours of app usage", &problems)
        expect(usage.sessions.contains { $0.bundleID == "com.apple.dt.Xcode" },
               "real usage either side of it survives", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }

    // MARK: - 59

    private static func testPurposeLearner() -> [String] {
        var problems: [String] = []
        let base = FocusConstants.autoStartThreshold

        // Nothing learned yet: the shared default stands.
        let cold = PurposeLearner(signals: [:])
        expectClose(cold.startThreshold(for: "com.google.Chrome"), base,
                    "an app with no history uses the default", &problems)
        expect(cold.summary(for: "com.google.Chrome") == nil,
               "no claim is made without observations", &problems)

        // One rejection is not a pattern. Adapting to it would make the app
        // erratic in exactly the way an automatic mode must not be.
        var signals = PurposeLearner(signals: [:]).recordingUndone("com.google.Chrome")
        expectClose(PurposeLearner(signals: signals).startThreshold(for: "com.google.Chrome"),
                    base, "one undo is below the minimum and moves nothing", &problems)

        // Three rejections are. The app becomes harder to convince.
        signals = PurposeLearner(signals: signals).recordingUndone("com.google.Chrome")
        signals = PurposeLearner(signals: signals).recordingUndone("com.google.Chrome")
        let cautious = PurposeLearner(signals: signals)
        expect(cautious.startThreshold(for: "com.google.Chrome") > base,
               "repeated undos demand more evidence", &problems)
        expect(cautious.summary(for: "com.google.Chrome")?.contains("Slower") == true,
               "and the app can say so in plain words", &problems)

        // Sessions kept pull the other way.
        var kept: [String: LearnedSignal] = [:]
        for _ in 0..<4 {
            kept = PurposeLearner(signals: kept).recordingKept("com.apple.dt.Xcode")
        }
        let eager = PurposeLearner(signals: kept)
        expect(eager.startThreshold(for: "com.apple.dt.Xcode") < base,
               "sessions consistently kept make the app quicker to start", &problems)

        // Bounded both ways: learning may not cross the stop threshold, or
        // starting and stopping would fight each other.
        var lopsided: [String: LearnedSignal] = [:]
        for _ in 0..<50 {
            lopsided = PurposeLearner(signals: lopsided).recordingKept("com.apple.Terminal")
        }
        let floor = PurposeLearner(signals: lopsided).startThreshold(for: "com.apple.Terminal")
        expect(floor > FocusConstants.autoStopThreshold,
               "the learned threshold stays above the stop threshold, got \(floor)", &problems)
        var undone: [String: LearnedSignal] = [:]
        for _ in 0..<50 {
            undone = PurposeLearner(signals: undone).recordingUndone("com.apple.Terminal")
        }
        expect(PurposeLearner(signals: undone).startThreshold(for: "com.apple.Terminal") <= 0.9,
               "and never rises past 0.9, which would mute it entirely", &problems)

        // Learning never touches recorded facts, only the threshold.
        expect(PurposeLearner(signals: signals).startThreshold(for: nil) == base,
               "an unknown app cannot be learned about", &problems)
        return problems
    }

    // MARK: - 61

    /// The reported defect: a session read as stopped until the away card was
    /// answered, and the gap counted as work while it sat there. Both directions
    /// matter — the clock must keep running, and the unanswered default must be
    /// the honest one rather than the flattering one.
    private static func testUnansweredAwayIsHonest() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 600
        // Long enough to raise the card, short enough not to trip the cap that
        // ends a session outright — a lunch, not a night.
        let away: TimeInterval = 2 * 3_600
        let since: TimeInterval = 480

        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.transition(on: .launch)
        clock.advance(work)
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        clock.advance(away)
        engine.transition(on: .awayEnded)

        // Nothing answered yet.
        expectClose(engine.elapsed, work, "the gap is excluded before any answer", &problems)
        clock.advance(since)
        expectClose(engine.elapsed, work + since,
                    "the clock keeps running while the card is up", &problems)
        expect(engine.state != .idle, "an unanswered card must not idle the session",
               &problems)

        // Answering "I was working" is the only thing that adds the gap back.
        engine.transition(on: .decision(.mergeTime))
        expectClose(engine.elapsed, work + away + since,
                    "merge adds the gap back exactly once", &problems)

        // A card left up across a quit must not turn the downtime into work.
        let saved = Clock(base)
        let stale = makeEngine(saved)
        stale.transition(on: .launch)
        saved.advance(work)
        stale.transition(on: .awayBegan(trigger: .systemSleep))
        saved.advance(away)
        stale.transition(on: .awayEnded)
        let snapshot = stale.snapshot()

        let later = Clock(saved.value.addingTimeInterval(2 * 86_400))
        let reopened = makeEngine(later)
        reopened.restore(from: snapshot)
        expectClose(reopened.elapsed, work,
                    "two days with the app shut must not become work", &problems)
        return problems
    }

    // MARK: - 63

    /// An absence long enough to be a night ends the session where it began,
    /// rather than holding it open and asking about it later. Sessions kept open
    /// across a night produced records spanning thirty-two hours, and every
    /// per-day figure in the app then had to guess which day the work belonged to.
    private static func testLongAwayEndsSession() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 40 * 60

        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.sessionName = "Evening"
        engine.transition(on: .launch)
        clock.advance(work)
        let leftAt = clock.value
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        clock.advance(9 * 3_600)
        engine.transition(on: .awayEnded)

        expect(engine.state == .idle,
               "a nine-hour absence should end the session, got \(engine.state)", &problems)
        guard let record = engine.archive.records.last else {
            problems.append("the ended session should be archived")
            return problems
        }
        expectClose(record.workSeconds, work, "archived work is what was worked", &problems)
        expectClose(record.end.timeIntervalSince(leftAt), 0,
                    "the record ends where the user walked away", &problems)
        expectClose(record.span, work, "span must not swallow the night", &problems)

        // The threshold is a cap, not a replacement for the card: a two-hour
        // lunch still asks.
        let lunchClock = Clock(base)
        let lunch = makeEngine(lunchClock)
        lunch.transition(on: .launch)
        lunchClock.advance(work)
        lunch.transition(on: .awayBegan(trigger: .screenLock))
        lunchClock.advance(2 * 3_600)
        lunch.transition(on: .awayEnded)
        if case .awaitingUserDecision = lunch.state {} else {
            problems.append("a two-hour absence should still ask, got \(lunch.state)")
        }

        // The cap is a setting, not a constant: raise it and the same nine-hour
        // absence becomes a question again rather than an ending.
        let patientClock = Clock(base)
        let patient = makeEngine(patientClock)
        patient.store.longAwayCap = 12 * 3_600
        patient.transition(on: .launch)
        patientClock.advance(work)
        patient.transition(on: .awayBegan(trigger: .systemSleep))
        patientClock.advance(9 * 3_600)
        patient.transition(on: .awayEnded)
        if case .awaitingUserDecision = patient.state {} else {
            problems.append("with a 12h cap, nine hours should still ask, got "
                            + "\(patient.state)")
        }

        // A misclick is not history.
        let quickClock = Clock(base)
        let quick = makeEngine(quickClock)
        quick.start(workType: .deepWork, intent: "oops")
        quickClock.advance(3)
        quick.stop()
        expect(quick.archive.records.isEmpty,
               "a three-second session must not be archived", &problems)
        return problems
    }

    // MARK: - 62

    private static func testManualAway() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.transition(on: .launch)
        clock.advance(300)
        engine.transition(on: .markedAway)
        expect(engine.state == .paused(reason: .away),
               "marking away should pause with an away reason, got \(engine.state)", &problems)

        clock.advance(1_800)
        // Saying it twice must not restart the pause clock and hand back the
        // half hour already spent away as work.
        engine.transition(on: .markedAway)
        clock.advance(600)
        let thread = engine.activeThreadID
        engine.transition(on: .manualResume)
        // Forty minutes away is a break, and a break ends a stretch: the work
        // before it is archived where they left, the gap is written down as
        // Away, and a new stretch begins now on the same thread.
        expect(engine.state == .running, "coming back resumes", &problems)
        expectClose(engine.elapsed, 0, "a new stretch, clock from zero", &problems)
        expect(engine.activeThreadID == thread, "on the same thread", &problems)
        let records = engine.archive.records.suffix(2)
        let away = records.first { $0.workType == .breakTime }
        let stretch = records.first { $0.workType != .breakTime }
        expectClose(away?.workSeconds ?? 0, 2_400, "the whole away is written down as one break", &problems)
        expect(away?.name == "Away", "named Away, got \(away?.name ?? "nil")", &problems)
        expectClose(stretch?.workSeconds ?? 0, 300, "the stretch carries only the work before it", &problems)
        expectClose(stretch?.end.timeIntervalSince(base) ?? 0, 300, "and ends where they left", &problems)

        // A short away stays a pause inside the stretch.
        let short = makeEngine(Clock(base))
        short.breakThreshold = 5 * 60
        short.transition(on: .launch)
        short.transition(on: .markedAway)
        let shortClock = Clock(base)
        _ = shortClock
        short.transition(on: .manualResume)
        expect(short.state == .running && short.archive.records.isEmpty,
               "a short away resumes the same stretch, nothing written", &problems)

        // The reason survives a save/load cycle, or the menu bar forgets.
        let reloaded = try? JSONDecoder().decode(
            PersistedState.self,
            from: JSONEncoder().encode(makeAwayEngine().snapshot()))
        expect(reloaded?.restoredPauseReason == .away,
               "an away pause must survive persistence", &problems)
        return problems
    }

    private static func makeAwayEngine() -> SessionEngine {
        let engine = makeEngine(Clock(base))
        engine.transition(on: .launch)
        engine.transition(on: .markedAway)
        return engine
    }

    // MARK: - 64

    /// The defect behind almost every wrong figure in the app: a record was
    /// filed under the day it *ended*, so a session begun on Friday and stopped
    /// on Sunday made Friday read as a day with no focus at all — blanking its
    /// bar, breaking the streak through it, and dropping it from the "usual
    /// pace" median as an inactive day.
    private static func testDayAttribution() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day2 = calendar.startOfDay(for: base)
        guard let day1 = calendar.date(byAdding: .day, value: -1, to: day2),
              let day3 = calendar.date(byAdding: .day, value: 1, to: day2) else {
            return ["could not build a three-day window"]
        }

        // Starts 22:00 on day 1, ends 02:00 on day 2: six hours of span, three
        // of them on each side of midnight, carrying 60 minutes of work.
        let record = SessionRecord(name: "Overnight", workType: .deepWork,
                                   start: day1.addingTimeInterval(22 * 3_600),
                                   end: day2.addingTimeInterval(2 * 3_600),
                                   workSeconds: 3_600)
        expectClose(record.workSeconds(on: day1, calendar: calendar), 1_800,
                    "half the work belongs to the first day", &problems)
        expectClose(record.workSeconds(on: day2, calendar: calendar), 1_800,
                    "half the work belongs to the second day", &problems)
        expectClose(record.workSeconds(on: day3, calendar: calendar), 0,
                    "no work belongs to a day the record never touched", &problems)
        expectClose(record.workSeconds(on: day1, calendar: calendar)
                    + record.workSeconds(on: day2, calendar: calendar),
                    record.workSeconds, "the split adds back up", &problems)

        // A zero-length record has no span to spread and belongs where it fell.
        let instant = SessionRecord(name: "", workType: .deepWork,
                                    start: day2.addingTimeInterval(600),
                                    end: day2.addingTimeInterval(600),
                                    workSeconds: 120)
        expectClose(instant.workSeconds(on: day2, calendar: calendar), 120,
                    "a zero-span record still lands on its own day", &problems)
        expectClose(instant.workSeconds(on: day1, calendar: calendar), 0,
                    "and on no other", &problems)

        // Through the archive: the streak must not break on the earlier day.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fc-attribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(day2.addingTimeInterval(12 * 3_600))
        let archive = SessionArchive(directory: directory, now: { clock.value })
        // 50 minutes each side of midnight — both days clear the 25-minute bar
        // only if the split happens.
        archive.append(SessionRecord(name: "Split", workType: .deepWork,
                                     start: day1.addingTimeInterval(22 * 3_600),
                                     end: day2.addingTimeInterval(2 * 3_600),
                                     workSeconds: 100 * 60))
        expectClose(archive.workSeconds(on: day1), 50 * 60,
                    "the earlier day gets its half", &problems)
        expectClose(archive.workSeconds(on: day2), 50 * 60,
                    "the later day gets its half", &problems)
        expect(archive.currentStreak() == 2,
               "both days qualify, got a streak of \(archive.currentStreak())", &problems)
        expect(archive.records(on: day1).count == 1,
               "the record is visible on the day it started", &problems)
        let bars = archive.weekBars()
        expect(bars.last?.minutes == 50, "today's bar shows its own half, got "
               + "\(bars.last?.minutes ?? -1)", &problems)
        return problems
    }

    // MARK: - 65

    /// Two accounting leaks in the "at the Mac" figure, both of which only ever
    /// pushed it downward.
    private static func testFlushAndTotalToday() -> [String] {
        var problems: [String] = []
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fc-flush-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = Clock(base)
        let archive = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: archive, ownBundleID: "self",
                                      idle: .disabled, now: { clock.value })

        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        // Flushes fire on every app switch, lock and wake, so two landing inside
        // the archive's five-second floor is routine. The rejected write used to
        // advance the segment's start anyway, deleting the seconds between them.
        clock.advance(2)
        tracker.flush()
        clock.advance(2)
        tracker.flush()
        expect(archive.sessions.isEmpty, "neither short flush should be recorded", &problems)
        expectClose(tracker.openSeconds(), 4,
                    "the refused seconds must still be on the open stretch", &problems)

        clock.advance(56)
        tracker.flush()
        expectClose(archive.totalToday(), 60,
                    "the whole minute survives, not just the last flush", &problems)

        // System processes are not the user working. This total was the one
        // query in the app reading past the filter.
        tracker.appActivated(bundleID: "com.apple.loginwindow", name: "loginwindow")
        clock.advance(3_600)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(60)
        tracker.flush()
        expectClose(archive.totalToday(), 120,
                    "an hour on the lock screen is not an hour at the Mac", &problems)

        // A stretch running through midnight belongs to both days it covers.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: clock.value)
        let split = AppUsageArchive(directory: directory
            .appendingPathComponent("split"), now: { midnight.addingTimeInterval(3_600) })
        split.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                     start: midnight.addingTimeInterval(-1_800),
                                     end: midnight.addingTimeInterval(1_800)))
        expectClose(split.totalToday(), 1_800,
                    "only the half after midnight counts toward today", &problems)
        return problems
    }

    // MARK: - 67

    /// "It was a break" costs the session exactly what "I was away" costs it,
    /// and buys a record that explains the gap. The record must never reach the
    /// day's focused total — recording rest in order to have it counted as work
    /// would be worse than not recording it at all.
    private static func testRecordedBreak() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 30 * 60
        let away: TimeInterval = 33 * 60

        func engineAfter(_ decision: UserDecision) -> (SessionEngine, Date) {
            let clock = Clock(base)
            let engine = makeEngine(clock)
            engine.transition(on: .launch)
            clock.advance(work)
            let leftAt = clock.value
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)
            engine.transition(on: .decision(decision))
            return (engine, leftAt)
        }

        let (rested, leftAt) = engineAfter(.tookBreak)
        let (gone, _) = engineAfter(.continueSession)
        expect(rested.state == .running, "a new session is running", &problems)
        expectClose(rested.elapsed, gone.elapsed,
                    "a break costs the session what an absence costs it", &problems)
        expectClose(rested.elapsed, 0,
                    "and both start a fresh clock on return", &problems)

        guard let record = rested.archive.records
            .first(where: { $0.workType == .breakTime }) else {
            problems.append("the break should be written down")
            return problems
        }
        expectClose(record.start.timeIntervalSince(leftAt), 0,
                    "it starts where the user left", &problems)
        expectClose(record.span, away, "and spans the whole absence", &problems)
        expect(record.threadID != rested.activeThreadID,
               "a break is not a segment of the work it interrupts", &problems)

        // The whole point: none of the rest counts as focus. The session that
        // closed does, so the day's total is the work, never the work plus the
        // break.
        expectClose(rested.archive.todayTotal(), work,
                    "the day counts the work and not the rest", &problems)
        expect(rested.archive.sessionsToday() == 1,
               "one focus session archived, not two, got "
               + "\(rested.archive.sessionsToday())", &problems)
        expectClose(rested.archive.longestToday(), work,
                    "the closed session is the longest; the break is not a "
                    + "candidate", &problems)
        expect(rested.archive.records.count == 2,
               "the break and the closed session, got "
               + "\(rested.archive.records.count)", &problems)
        expect(!gone.archive.records.contains { $0.workType == .breakTime },
               "being away records no break", &problems)
        expect(gone.archive.records.count == 1,
               "being away still closes the session it interrupted", &problems)

        // Against a real focus record, the break must be invisible to totals but
        // visible to anything listing the day.
        let clock = Clock(base)
        let mixed = makeArchive(clock)
        mixed.append(SessionRecord(name: "Work", workType: .deepWork,
                                   start: base, end: base.addingTimeInterval(3_600),
                                   workSeconds: 3_600))
        mixed.append(SessionRecord(name: "Break", workType: .breakTime,
                                   start: base.addingTimeInterval(3_600),
                                   end: base.addingTimeInterval(5_400),
                                   workSeconds: 1_800))
        expectClose(mixed.todayTotal(), 3_600,
                    "the hour of work, not the half hour of rest", &problems)
        expect(mixed.records(on: base).count == 2,
               "both are still listed for the day", &problems)
        expect(mixed.weekBars().last?.minutes == 60,
               "the week chart shows focus only, got "
               + "\(mixed.weekBars().last?.minutes ?? -1)", &problems)
        return problems
    }

    // MARK: - 68

    /// Sitting idle pauses the session backdated to when input actually stopped,
    /// so the ten minutes that prove the user is gone are excluded too. Only an
    /// idle pause auto-resumes: a pause the user pressed is a deliberate act.
    private static func testIdleAutoPause() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.transition(on: .launch)
        clock.advance(600)                       // ten minutes of real work

        // Nine minutes idle is tolerated — reading and calls are work.
        clock.advance(540)
        engine.transition(on: .idleObserved(seconds: 540))
        expect(engine.state == .running, "nine minutes idle keeps the session", &problems)
        expectClose(engine.elapsed, 1_140, "and counts", &problems)

        // Past the threshold it pauses, backdated to the last keypress.
        clock.advance(60)
        engine.transition(on: .idleObserved(seconds: 600))
        expect(engine.state == .paused(reason: .idle),
               "ten minutes idle pauses, got \(engine.state)", &problems)
        expectClose(engine.elapsed, 600,
                    "the whole idle stretch is excluded, not just the tail", &problems)

        // Still idle: no further effect, and no time accrues.
        clock.advance(240)
        engine.transition(on: .idleObserved(seconds: 840))
        expectClose(engine.elapsed, 600, "four more minutes away add nothing", &problems)

        // Input resumes it — quietly, because fourteen minutes is under the
        // asking threshold.
        engine.transition(on: .idleObserved(seconds: 0))
        expect(engine.state == .running, "input resumes an idle pause", &problems)
        clock.advance(300)
        expectClose(engine.elapsed, 900, "and the clock runs again", &problems)

        // Past the threshold the absence is asked about, exactly as a locked
        // one is: the idle pause was the app's observation, and the question
        // is the same whether or not the screen happened to lock.
        clock.advance(FocusConstants.idlePauseThreshold)
        engine.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock.advance(1_800)
        engine.transition(on: .idleObserved(seconds: 0))
        guard case .awaitingUserDecision(let asked, _) = engine.state else {
            return problems + ["forty idle minutes should raise the card, got \(engine.state)"]
        }
        expectClose(asked, 2_400, "naming the whole absence", &problems)
        engine.transition(on: .decision(.mergeTime))
        expect(engine.state == .running, "'I was working' resumes", &problems)
        expectClose(engine.elapsed, 3_300, "with the absence added back as work", &problems)

        // A pause the user pressed must not be undone by typing.
        let manualClock = Clock(base)
        let manual = makeEngine(manualClock)
        manual.transition(on: .launch)
        manualClock.advance(60)
        manual.transition(on: .manualPause)
        manual.transition(on: .idleObserved(seconds: 0))
        expect(manual.state == .paused(reason: .manual),
               "input must not undo a deliberate pause, got \(manual.state)", &problems)

        // The reason survives persistence.
        let idleClock = Clock(base)
        let persisted = makeEngine(idleClock)
        persisted.transition(on: .launch)
        idleClock.advance(1_200)
        persisted.transition(on: .idleObserved(seconds: 700))
        let blob = try? JSONEncoder().encode(persisted.snapshot())
        let reloaded = blob.flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        expect(reloaded?.restoredPauseReason == .idle,
               "an idle pause must survive a save/load cycle", &problems)
        return problems
    }

    // MARK: - 69

    /// The goal counts only seconds that are both inside a declared session and
    /// within reach of real input. Either alone is a lie: wall-clock sessions
    /// counted an untouched machine, and raw hands-on time would let an hour of
    /// messaging fill a focus goal.
    private static func testFocusedActiveTime() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }
        func record(_ from: Double, _ to: Double,
                    type: WorkType = .deepWork) -> SessionRecord {
            SessionRecord(name: "S", workType: type, start: at(from), end: at(to),
                          workSeconds: (to - from) * 3_600)
        }
        func used(_ from: Double, _ to: Double) -> AppUsageSession {
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: at(from), end: at(to))
        }
        func seconds(_ records: [SessionRecord], _ usage: [AppUsageSession],
                     running: (start: Date, end: Date)? = nil) -> TimeInterval {
            FocusedActiveTime.seconds(on: day, records: records, usage: usage,
                                      running: running, calendar: calendar)
        }

        expectClose(seconds([record(9, 11)], [used(13, 14)]), 0,
                    "no overlap, nothing counted", &problems)
        expectClose(seconds([record(9, 11)], []), 0,
                    "a session with nobody at the keyboard counts nothing", &problems)
        expectClose(seconds([], [used(9, 11)]), 0,
                    "hands-on outside any session counts nothing", &problems)
        expectClose(seconds([record(9, 11)], [used(10, 12)]), 3_600,
                    "only the overlapping hour", &problems)

        // Two overlapping records must not count one second twice.
        expectClose(seconds([record(9, 11), record(10, 12)], [used(9, 12)]), 3 * 3_600,
                    "overlapping sessions are merged, not summed", &problems)
        // Nor two overlapping usage stretches.
        expectClose(seconds([record(9, 12)], [used(9, 11), used(10, 12)]), 3 * 3_600,
                    "overlapping usage is merged, not summed", &problems)

        // Breaks are not focus, so a break covering hands-on time counts nothing.
        expectClose(seconds([record(9, 11, type: .breakTime)], [used(9, 11)]), 0,
                    "a recorded break cannot fill the goal", &problems)

        // The running session participates.
        expectClose(seconds([], [used(9, 11)], running: (at(10), at(12))), 3_600,
                    "the in-flight session counts its overlap too", &problems)

        // Everything is clipped to the day.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let overnight = SessionRecord(name: "S", workType: .deepWork,
                                      start: yesterday.addingTimeInterval(22 * 3_600),
                                      end: at(2), workSeconds: 4 * 3_600)
        let overnightUse = AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                           start: yesterday.addingTimeInterval(22 * 3_600),
                                           end: at(2))
        expectClose(seconds([overnight], [overnightUse]), 2 * 3_600,
                    "only the hours after midnight belong to today", &problems)
        return problems
    }

    // MARK: - 70

    /// Every answer but "I was working" closes the session where the user
    /// walked away and opens a new one when they got back. What separates them
    /// is the thread: an afternoon split by lunch is still one piece of work.
    private static func testAwayEndsSession() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 40 * 60
        let away: TimeInterval = 33 * 60

        func run(_ decision: UserDecision) -> (engine: SessionEngine,
                                               left: Date, back: Date) {
            let clock = Clock(base)
            let engine = makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Refactor")
            clock.advance(work)
            let left = clock.value
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            let back = clock.value
            engine.transition(on: .awayEnded)
            engine.transition(on: .decision(decision))
            return (engine, left, back)
        }

        for decision in [UserDecision.continueSession, .tookBreak, .resetTimer] {
            let (engine, left, back) = run(decision)
            expect(engine.state == .running,
                   "\(decision): a new session should be running", &problems)
            expectClose(engine.elapsed, 0,
                        "\(decision): the new session starts fresh", &problems)
            expectClose(engine.sessionStartDate.timeIntervalSince(back), 0,
                        "\(decision): and starts when the user got back", &problems)
            guard let closed = engine.archive.records
                .last(where: { $0.workType.countsAsFocus }) else {
                problems.append("\(decision): the old session should be archived")
                continue
            }
            expectClose(closed.workSeconds, work,
                        "\(decision): archived work is what was worked", &problems)
            expectClose(closed.end.timeIntervalSince(left), 0,
                        "\(decision): archived end is where they left", &problems)
        }

        // Thread identity is the whole difference between the three.
        let awayRun = run(.continueSession)
        expect(awayRun.engine.activeThreadID
                == awayRun.engine.archive.records.last?.threadID,
               "'I was away' keeps the thread", &problems)

        let freshRun = run(.resetTimer)
        expect(freshRun.engine.activeThreadID
                != freshRun.engine.archive.records.last?.threadID,
               "'Start fresh' takes a new thread", &problems)

        let breakRun = run(.tookBreak)
        let focusRecords = breakRun.engine.archive.records.filter {
            $0.workType.countsAsFocus
        }
        expect(breakRun.engine.activeThreadID == focusRecords.last?.threadID,
               "'It was a break' keeps the thread", &problems)
        expect(breakRun.engine.archive.records.contains { $0.workType == .breakTime },
               "and still records the break", &problems)

        // "I was working" is the one answer that does not split anything.
        let (merged, _, _) = run(.mergeTime)
        expect(merged.archive.records.isEmpty,
               "merging archives nothing, got \(merged.archive.records.count)", &problems)
        expectClose(merged.elapsed, work + away,
                    "and the gap becomes work", &problems)
        return problems
    }

    // MARK: - 71

    /// `Now: Claude 6h 50m` was the time since the process launched, rendered
    /// directly above `Claude 53m` in Top Apps. Two labels that read alike must
    /// not measure different things.
    private static func testRunningStretch() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fc-stretch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stats = DashboardStats(
            sessions: SessionArchive(directory: directory, now: { clock.value }),
            usage: AppUsageArchive(directory: directory, now: { clock.value }),
            now: { clock.value })
        let launched = base.addingTimeInterval(-6 * 3_600)

        let apps = stats.runningNow(from: [
            RunningAppInput(bundleID: "com.a", appName: "Alpha",
                            launched: launched, stretchSeconds: 12 * 60),
            RunningAppInput(bundleID: "com.b", appName: "Beta",
                            launched: launched, stretchSeconds: nil)
        ])

        guard let alpha = apps.first(where: { $0.bundleID == "com.a" }) else {
            problems.append("the frontmost app should be listed")
            return problems
        }
        expectClose(alpha.openFor ?? -1, 12 * 60,
                    "the current stretch, not six hours of uptime", &problems)

        let beta = apps.first { $0.bundleID == "com.b" }
        expect(beta?.openFor == nil,
               "an app with no open stretch reports no figure", &problems)
        expect(apps.first?.bundleID == "com.a",
               "the app you are actually in sorts first", &problems)
        return problems
    }

    // MARK: - 72

    /// The panel had a fixed width and unbounded height, so its lower half ran
    /// off a 14" display once Settings was expanded.
    private static func testPopoverMetrics() -> [String] {
        var problems: [String] = []

        // 14" MacBook Pro, menu bar and Dock removed.
        let laptop = PopoverMetrics.fitting(CGSize(width: 1_512, height: 900))
        expect(laptop.maxHeight < 900,
               "the panel must be shorter than the screen", &problems)
        expect(laptop.maxHeight >= 600,
               "but not uselessly short, got \(laptop.maxHeight)", &problems)

        // A short laptop screen gets two panes precisely *because* it is short:
        // one column there is roughly twice the height the screen can hold.
        let small = PopoverMetrics.fitting(CGSize(width: 1_366, height: 700))
        expect(small.maxHeight < 700, "shorter than a small screen too", &problems)
        expect(small.twoColumn,
               "a short screen needs two panes most, not least", &problems)

        // Genuinely narrow displays stay single-column: 560pt would be most of
        // the screen, and two panes of 250pt hold nothing.
        let narrow = PopoverMetrics.fitting(CGSize(width: 1_100, height: 900))
        expect(!narrow.twoColumn, "a narrow screen cannot host two panes", &problems)
        expect(narrow.width == Tokens.popoverWidth,
               "and keeps the single-column width", &problems)

        // A large display earns the second column, which roughly halves the
        // height — that is what buys the extra width back.
        let desktop = PopoverMetrics.fitting(CGSize(width: 2_560, height: 1_440))
        expect(desktop.twoColumn, "a large screen affords two panes", &problems)
        expect(desktop.width > Tokens.popoverWidth,
               "which needs more width, got \(desktop.width)", &problems)
        expect(desktop.width <= 640, "but never a whole window", &problems)

        // A 13" MacBook Pro is the tightest machine the panel must fit, and the
        // one where a single column would be twice the screen's height. It must
        // therefore qualify for two panes and for the tighter density.
        let thirteen = PopoverMetrics.fitting(CGSize(width: 1_440, height: 845))
        expect(thirteen.twoColumn,
               "a 13-inch must get two panes; one column does not fit it", &problems)
        expect(thirteen.dense, "and the tighter density", &problems)
        expect(thirteen.rowHeight < 26 && thirteen.outerPadding < Tokens.Space.l,
               "which must actually change the measurements", &problems)
        // Measured from the rendered states: the tallest is 778pt with settings
        // expanded. Leave headroom, but not so much that a regression hides.
        expect(thirteen.maxHeight >= 780,
               "the panel must be allowed the 778pt its tallest state needs, got "
               + "\(thirteen.maxHeight)", &problems)

        // A roomy screen keeps the comfortable density.
        let roomy = PopoverMetrics.fitting(CGSize(width: 2_560, height: 1_440))
        expect(!roomy.dense, "a large screen has no need to tighten", &problems)
        expect(roomy.topAppCount > thirteen.topAppCount,
               "and can show more apps", &problems)

        // The scrolling middle always gets a usable share, and never more than
        // the panel itself — a `ScrollView` given no height renders nothing.
        for size in [CGSize(width: 1_512, height: 900),
                     CGSize(width: 1_366, height: 700),
                     CGSize(width: 800, height: 400)] {
            let metrics = PopoverMetrics.fitting(size)
            expect(metrics.scrollCap >= 200,
                   "the middle must never be given zero height at \(size)", &problems)
            expect(metrics.scrollCap < metrics.maxHeight,
                   "and never more than the whole panel at \(size)", &problems)
        }
        return problems
    }

    // MARK: - 73

    /// Stepping the dashboard to Yesterday must not re-scope the menu bar. They
    /// shared one `dayOffset`, so the panel that exists to answer "how am I
    /// doing right now" quietly started answering it about a day that had
    /// ended. This pins the two computations apart so a refactor cannot
    /// collapse them back into one.
    private static func testGlanceStaysToday() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = Clock(base)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.value)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return ["could not build a two-day window"]
        }
        usage.record(AppUsageSession(bundleID: "com.today", appName: "TodayApp",
                                     start: today.addingTimeInterval(3_600),
                                     end: today.addingTimeInterval(7_200)))
        usage.record(AppUsageSession(bundleID: "com.past", appName: "PastApp",
                                     start: yesterday.addingTimeInterval(3_600),
                                     end: yesterday.addingTimeInterval(7_200)))

        let stats = DashboardStats(
            sessions: SessionArchive(directory: directory, now: { clock.value }),
            usage: usage, now: { clock.value })

        // The glance is built for today whatever day is selected.
        let todayApps = stats.rankedApps(for: today)
        let pastApps = stats.rankedApps(for: yesterday)
        expect(todayApps.first?.appName == "TodayApp",
               "today's glance names today's app", &problems)
        expect(pastApps.first?.appName == "PastApp",
               "and the selected day is a separate question", &problems)
        expect(todayApps.first?.appName != pastApps.first?.appName,
               "the two must not be the same computation", &problems)
        return problems
    }

    // MARK: - 74

    /// A second absence while the away card is up must not dissolve into the
    /// successor session as work. `apply` used to drop the recorded interval on
    /// the floor, so locking the screen again before answering credited the
    /// whole second absence to whichever session survived the decision.
    private static func testShadowAwayIsNotWork() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 40 * 60
        let away: TimeInterval = 33 * 60          // past the default 15m threshold
        let secondAway: TimeInterval = 30 * 60
        let workedBetween: TimeInterval = 7 * 60  // back and working, then locked again
        let workedAfter: TimeInterval = 5 * 60    // unlocked and working, then answered

        func run(_ decision: UserDecision) -> SessionEngine {
            let clock = Clock(base)
            let engine = makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Refactor")
            clock.advance(work)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)          // the card goes up
            clock.advance(workedBetween)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(secondAway)
            engine.transition(on: .awayEnded)          // banked; card still up
            clock.advance(workedAfter)
            engine.transition(on: .decision(decision))
            return engine
        }

        let kept = run(.continueSession)
        expectClose(kept.elapsed, workedBetween + workedAfter,
                    "'I was away': the new session holds only worked minutes",
                    &problems)

        let merged = run(.mergeTime)
        expectClose(merged.elapsed, work + away + workedBetween + workedAfter,
                    "'I was working' merges the first gap and only the first",
                    &problems)
        return problems
    }

    // MARK: - 75

    /// An absence with the screen never locked used to escape the long-away
    /// rule entirely: the lock path ends a session past the cap, but a lid left
    /// open overnight held it paused forever and produced a record spanning the
    /// whole night on resume.
    private static func testUnlockedAbsenceEndsSession() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Evening")
        clock.advance(50 * 60)
        // Input stops; ten minutes later the ticker's sample crosses the
        // threshold and the pause is backdated to the last keystroke.
        clock.advance(FocusConstants.idlePauseThreshold)
        engine.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        let left = clock.value.addingTimeInterval(-FocusConstants.idlePauseThreshold)
        expect(engine.state == .paused(reason: .idle), "idle pauses first", &problems)

        // The absence grows past the cap with no lock and no wake event.
        let cap = engine.store.longAwayCap
        clock.advance(cap)
        engine.transition(on: .idleObserved(
            seconds: cap + FocusConstants.idlePauseThreshold))
        expect(engine.state == .idle, "past the cap the session ends", &problems)
        guard let record = engine.archive.records.last else {
            return problems + ["a record should have been written"]
        }
        expectClose(record.workSeconds, 50 * 60,
                    "with only the worked minutes", &problems)
        expectClose(record.end.timeIntervalSince(left), 0,
                    "ending where input stopped", &problems)

        // The marked-away version comes back through a button, not a tick.
        let clock2 = Clock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Errand")
        clock2.advance(20 * 60)
        let marked = clock2.value
        engine2.transition(on: .markedAway)
        clock2.advance(engine2.store.longAwayCap + 60)
        let thread = engine2.activeThreadID
        engine2.transition(on: .manualResume)   // "I'm back"
        expect(engine2.state == .running,
               "coming back starts a fresh session", &problems)
        expectClose(engine2.elapsed, 0, "whose clock starts now", &problems)
        expect(engine2.activeThreadID == thread, "on the same thread", &problems)
        guard let closed = engine2.archive.records.last else {
            return problems + ["the marked-away session should be archived"]
        }
        expectClose(closed.end.timeIntervalSince(marked), 0,
                    "archived where they marked away", &problems)
        expectClose(closed.workSeconds, 20 * 60,
                    "with the work done before it", &problems)
        return problems
    }

    // MARK: - 76

    /// A distraction pause is hands-on by definition — the dwell that paused
    /// the session required using the break app — so the span-times-usage
    /// intersection credited every paused YouTube minute to the focus goal.
    /// Each record's credit is now capped at the work actually done in it.
    private static func testGoalDistractionCap() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }

        // Two hours at the Mac, but 45 minutes of the session were paused on a
        // distraction: the record spans 9-11 while its work is 1h 15m.
        let record = SessionRecord(name: "S", workType: .deepWork,
                                   start: at(9), end: at(11),
                                   workSeconds: 1.25 * 3_600)
        let used = AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                   start: at(9), end: at(11))
        expectClose(FocusedActiveTime.seconds(on: day, records: [record],
                                              usage: [used], running: nil,
                                              calendar: calendar),
                    1.25 * 3_600,
                    "hands-on time inside a pause cannot outgrow the work",
                    &problems)

        // The idle case is unchanged: hands-off time was never in the overlap.
        let idleUse = AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                      start: at(9), end: at(10.25))
        expectClose(FocusedActiveTime.seconds(on: day, records: [record],
                                              usage: [idleUse], running: nil,
                                              calendar: calendar),
                    1.25 * 3_600,
                    "an idle pause is already outside hands-on", &problems)

        // The running session gets the same cap when its work is known.
        expectClose(FocusedActiveTime.seconds(on: day, records: [],
                                              usage: [used],
                                              running: (at(9), at(11)),
                                              runningWork: 30 * 60,
                                              calendar: calendar),
                    30 * 60,
                    "the in-flight session is capped at its work", &problems)
        return problems
    }

    // MARK: - 77

    /// The ordinary overnight: input stops, the session pauses itself, the
    /// display sleeps and locks, and the next thing the engine hears is the
    /// unlock in the morning. The unlock used to drop the interval because the
    /// session was already paused, and the first sample afterwards already saw
    /// fresh input, so the night was merged back into a surviving session —
    /// the lock-while-running path ended it, the idle-then-lock path did not.
    private static func testIdleThenLockedNightEndsSession() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Evening")
        clock.advance(45 * 60)
        let left = clock.value                                    // last keystroke
        clock.advance(FocusConstants.idlePauseThreshold)
        engine.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        expect(engine.state == .paused(reason: .idle), "pauses itself first", &problems)

        // Display sleep locks the screen a few minutes later; the ticker stops
        // with the usage stretch. Nothing is heard until morning.
        clock.advance(5 * 60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(9 * 3_600)
        engine.transition(on: .awayEnded)
        expect(engine.state == .idle,
               "the unlock ends a session whose absence outgrew the cap, got \(engine.state)",
               &problems)
        guard let record = engine.archive.records.last else {
            return problems + ["a record should have been written"]
        }
        expectClose(record.workSeconds, 45 * 60, "with only the evening's work", &problems)
        expectClose(record.end.timeIntervalSince(left), 0,
                    "ending at the last keystroke", &problems)

        // The same night with the machine never locked and the app relaunched
        // in the morning: the first sample after restore already sees input.
        let clock2 = Clock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Evening")
        clock2.advance(30 * 60)
        clock2.advance(FocusConstants.idlePauseThreshold)
        engine2.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        let blob = engine2.snapshot()
        clock2.advance(8 * 3_600)
        let morning = makeEngine(clock2)                          // fresh process
        morning.restore(from: blob)
        expect(morning.state == .paused(reason: .idle), "restores paused", &problems)
        morning.transition(on: .idleObserved(seconds: 1))         // the user is typing
        expect(morning.state == .idle,
               "a sample showing input does not rescue a night past the cap, got \(morning.state)",
               &problems)
        expectClose(morning.archive.records.last?.workSeconds ?? -1, 30 * 60,
                    "and the record holds the evening's work only", &problems)

        // Under the asking threshold, input still resumes an idle pause quietly.
        let clock3 = Clock(base)
        let engine3 = makeEngine(clock3)
        engine3.start(workType: .deepWork, intent: "Short")
        clock3.advance(20 * 60)
        clock3.advance(FocusConstants.idlePauseThreshold)
        engine3.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock3.advance(2 * 60)
        engine3.transition(on: .idleObserved(seconds: 0))
        expect(engine3.state == .running, "a twelve-minute idle resumes", &problems)
        expectClose(engine3.elapsed, 20 * 60,
                    "having excluded exactly the absence", &problems)

        // Between the threshold and the cap it is asked about, like a lock.
        clock3.advance(5 * 60)
        clock3.advance(FocusConstants.idlePauseThreshold)
        engine3.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock3.advance(25 * 60)
        engine3.transition(on: .idleObserved(seconds: 0))
        guard case .awaitingUserDecision(let asked, _) = engine3.state else {
            return problems + ["a 35-minute idle absence should be asked about, got \(engine3.state)"]
        }
        expectClose(asked, 35 * 60, "and the card names the whole absence", &problems)
        engine3.transition(on: .decision(.continueSession))
        expectClose(engine3.archive.records.last?.workSeconds ?? -1, 25 * 60,
                    "'I was away' closes the session with its 25 worked minutes", &problems)

        // The same through an unlock: idle, then locked, then back under the cap.
        let clock4 = Clock(base)
        let engine4 = makeEngine(clock4)
        engine4.start(workType: .deepWork, intent: "Lunch")
        clock4.advance(30 * 60)
        clock4.advance(FocusConstants.idlePauseThreshold)
        engine4.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock4.advance(3 * 60)
        engine4.transition(on: .awayBegan(trigger: .screenLock))
        clock4.advance(40 * 60)
        engine4.transition(on: .awayEnded)
        guard case .awaitingUserDecision(let lunch, _) = engine4.state else {
            return problems + ["an idle-then-locked lunch should be asked about, got \(engine4.state)"]
        }
        expectClose(lunch, 53 * 60, "measured from the last keystroke, not the lock", &problems)
        return problems
    }

    // MARK: - 78

    /// The shadow of a second absence is persisted. Bank thirty minutes while
    /// the card is up, quit, relaunch, answer: the successor used to inherit
    /// those thirty minutes as work because the bank lived only in memory. And
    /// an absence still *open* at the quit is measured from when it began, not
    /// from the write.
    private static func testShadowAwaySurvivesRelaunch() -> [String] {
        var problems: [String] = []
        // A closed second absence, then a quit while working.
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Refactor")
        clock.advance(40 * 60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(33 * 60)
        engine.transition(on: .awayEnded)                          // card up
        clock.advance(7 * 60)                                      // working
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(30 * 60)
        engine.transition(on: .awayEnded)                          // banked
        clock.advance(5 * 60)                                      // working
        let blob = engine.snapshot()
        expectClose(blob.shadowAway ?? 0, 30 * 60, "the bank is written down", &problems)
        clock.advance(2 * 3_600)                                   // quit; two hours pass
        let relaunched = makeEngine(clock)
        relaunched.restore(from: blob)
        guard case .awaitingUserDecision = relaunched.state else {
            return problems + ["should still be awaiting, got \(relaunched.state)"]
        }
        relaunched.transition(on: .decision(.continueSession))
        // The closed session: 40m before leaving, plus the 7m and 5m worked
        // under the card — the successor can only start at the relaunch.
        // Nothing of the 33m, the 30m or the two hours is in it.
        expectClose(relaunched.archive.records.last?.workSeconds ?? -1, 52 * 60,
                    "the closed session holds only worked minutes", &problems)
        expectClose(relaunched.elapsed, 0,
                    "and the successor starts from the relaunch", &problems)

        // The same, but the second absence is still open at the quit.
        let clock2 = Clock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Refactor")
        clock2.advance(40 * 60)
        engine2.transition(on: .awayBegan(trigger: .screenLock))
        clock2.advance(33 * 60)
        engine2.transition(on: .awayEnded)                         // card up
        clock2.advance(7 * 60)
        engine2.transition(on: .awayBegan(trigger: .screenLock))   // locked…
        clock2.advance(10 * 60)
        let blob2 = engine2.snapshot()                             // …written while locked
        clock2.advance(50 * 60)                                    // still locked; quit; relaunch
        let relaunched2 = makeEngine(clock2)
        relaunched2.restore(from: blob2)
        relaunched2.transition(on: .decision(.mergeTime))
        // 40m worked + 33m merged + 7m worked. The locked hour is not work.
        expectClose(relaunched2.elapsed, 80 * 60,
                    "an absence open at the quit is excluded from its start", &problems)
        return problems
    }

    // MARK: - 79

    /// The stat row's Sessions, Focused and Longest must answer about the
    /// selected day. They read the engine's today-only figures whatever day the
    /// dashboard was browsing, so Yesterday showed yesterday's Tracked beside
    /// today's session count. And Longest named the busiest app, which is not
    /// what the figure measures.
    private static func testDayScopedSessionFigures() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let archive = makeArchive(clock)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.value)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return ["could not build a two-day window"]
        }
        func record(_ name: String, day: Date, hour: Double, minutes: Double,
                    type: WorkType = .deepWork) {
            let start = day.addingTimeInterval(hour * 3_600)
            archive.append(SessionRecord(name: name, workType: type, start: start,
                                         end: start.addingTimeInterval(minutes * 60),
                                         workSeconds: minutes * 60))
        }
        record("Slides", day: yesterday, hour: 9, minutes: 50)
        record("Review", day: yesterday, hour: 14, minutes: 95)
        record("Lunch", day: yesterday, hour: 12, minutes: 40, type: .breakTime)
        record("Parser", day: today, hour: 10, minutes: 30)

        expect(archive.focusCount(on: yesterday) == 2,
               "two focus sessions yesterday, the break not among them", &problems)
        expect(archive.focusCount(on: today) == 1, "one today", &problems)
        expectClose(archive.workSeconds(on: yesterday), 145 * 60,
                    "focused yesterday", &problems)
        let longest = archive.longestRecord(on: yesterday)
        expect(longest?.record.name == "Review",
               "the longest is named by its intent", &problems)
        expectClose(longest?.seconds ?? 0, 95 * 60, "with its length", &problems)
        expect(archive.longestRecord(on: today)?.record.name == "Parser",
               "and today's is today's", &problems)
        // A session across midnight is judged on each day's share.
        record("Night", day: yesterday, hour: 23, minutes: 120)    // 23:00 → 01:00
        expectClose(archive.longestRecord(on: today)?.seconds ?? 0, 60 * 60,
                    "a midnight-spanning record offers today only its hour after midnight",
                    &problems)
        return problems
    }

    // MARK: - 80

    /// Seven distinct app colours in both appearances, clamped past the end,
    /// and a total work-type mapping. Pins the palette so a later edit cannot
    /// quietly give two apps one colour or leave a work type on a default.
    private static func testPalette() -> [String] {
        var problems: [String] = []
        for dark in [false, true] {
            var seen: Set<String> = []
            for rank in 0..<7 {
                let c = Tokens.Palette.resolved(rank: rank, dark: dark)
                seen.insert(String(format: "%.3f-%.3f-%.3f", c.r, c.g, c.b))
            }
            expect(seen.count == 7,
                   "seven distinct app colours in \(dark ? "dark" : "light"), got \(seen.count)",
                   &problems)
        }
        let light0 = Tokens.Palette.resolved(rank: 0, dark: false)
        let dark0 = Tokens.Palette.resolved(rank: 0, dark: true)
        expect(light0 != dark0, "the pair flips with the appearance", &problems)
        let beyond = Tokens.Palette.resolved(rank: 42, dark: false)
        let other = Tokens.Palette.resolved(rank: 6, dark: false)
        expect(beyond == other, "ranks past the end read as Other", &problems)
        let negative = Tokens.Palette.resolved(rank: -1, dark: false)
        let first = Tokens.Palette.resolved(rank: 0, dark: false)
        expect(negative == first, "a negative rank clamps to the first", &problems)
        for type in WorkType.allCases {
            _ = Tokens.Palette.workType(type)   // total: every case compiles to a colour
        }
        return problems
    }

    // MARK: - 81

    /// The status-item ring renders for every state it can be in. A nil image
    /// would fall back to the infinity glyph silently, which is exactly the
    /// kind of quiet regression a test exists to shout about.
    private static func testMenuBarGlyph() -> [String] {
        var problems: [String] = []
        let states: [(Double, Bool, Bool, Bool)] = [
            (0, false, false, false), (0.63, false, false, false),
            (0.63, true, false, false), (0.63, false, true, false),
            (1.0, false, false, true)
        ]
        for (progress, paused, attention, met) in states {
            // Booleans out, not the image: `NSImage` is not `Sendable` before
            // macOS 14, and the result only needs to say what was rendered.
            let result: (exists: Bool, template: Bool, sized: Bool) = MainActor.assumeIsolated {
                let image = MenuBarGlyph.image(progress: progress, paused: paused,
                                               attention: attention, isMet: met)
                return (image != nil,
                        image?.isTemplate == true,
                        image.map { $0.size.width == 16 && $0.size.height == 16 } == true)
            }
            expect(result.exists, "glyph renders for progress \(progress) paused \(paused) "
                   + "attention \(attention) met \(met)", &problems)
            expect(result.template, "and is a template image", &problems)
            expect(result.sized, "at 16×16 points", &problems)
        }
        return problems
    }

    // MARK: - 82

    /// Every settings write lands in the store and fires `onChange` exactly
    /// once, so the surfaces that read the store refresh, and a tracking toggle
    /// reaches the owner of the tracker rather than only the preference.
    private static func testSettingsModel() -> [String] {
        var problems: [String] = []
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        var changes = 0
        var tracking: [Bool] = []
        let model = SettingsModel(store: store, isTrackingEnabled: true,
                                  onChange: { changes += 1 },
                                  onTrackingChanged: { tracking.append($0) })

        model.dailyGoal = 2 * 3_600
        expectClose(store.dailyGoal, 2 * 3_600, "daily goal writes through", &problems)
        model.autoSessionsEnabled = false
        expect(store.autoSessionsEnabled == false, "auto sessions write through", &problems)
        model.rewardsEnabled = false
        expect(store.rewardsEnabled == false, "rewards write through", &problems)
        model.remindersEnabled = false
        expect(store.remindersEnabled == false, "reminders write through", &problems)
        model.breakThreshold = 1_800
        expectClose(store.breakThreshold, 1_800, "ask-me-after writes through", &problems)
        model.longAwayCap = 2 * 3_600
        expectClose(store.longAwayCap, 2 * 3_600, "end-after writes through", &problems)
        model.breakLength = 15 * 60
        expectClose(store.breakLength, 15 * 60, "auto-session gap writes through", &problems)
        model.menuSessionCount = 7
        expect(store.menuSessionCount == 7, "sessions per app writes through", &problems)
        model.fullPromptAfter = 3_600
        expectClose(store.fullPromptAfter ?? -1, 3_600, "full-prompt threshold writes through", &problems)
        model.fullPromptAfter = 0
        expect(store.fullPromptAfter == nil, "zero means Never", &problems)
        expect(changes == 10, "one change notification per write, got \(changes)", &problems)

        model.isTrackingEnabled = false
        expect(tracking == [false], "tracking goes to the tracker's owner", &problems)
        expect(model.isTrackingEnabled == false, "and the model remembers it", &problems)
        expect(changes == 10, "tracking does not double-fire onChange", &problems)
        return problems
    }

    // MARK: - 83

    /// "vs last week" needs last week. The figure is the same rollup the chart
    /// uses, one period back, so it can never disagree with the bars.
    private static func testPreviousPeriodTracked() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(base)
        let calendar = Calendar.current
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let stats = PeriodStats(sessions: SessionArchive(directory: directory,
                                                         now: { clock.value }),
                                usage: usage, now: { clock.value })

        let thisWeek = stats.bounds(for: .week, containing: clock.value)
        guard let lastWeekDay = calendar.date(byAdding: .day, value: -3, to: thisWeek.start),
              let twoWeeksDay = calendar.date(byAdding: .day, value: -10, to: thisWeek.start)
        else { return ["could not build the weeks"] }
        func record(_ day: Date, minutes: Double) {
            let start = calendar.startOfDay(for: day).addingTimeInterval(10 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start,
                                         end: start.addingTimeInterval(minutes * 60)))
        }
        record(clock.value, minutes: 30)       // this week
        record(lastWeekDay, minutes: 45)       // last week
        record(twoWeeksDay, minutes: 70)       // the week before — must not count

        expectClose(stats.previousPeriodTracked(for: .week, containing: clock.value),
                    45 * 60, "last week's tracked total", &problems)
        expectClose(stats.previousPeriodTracked(for: .week, containing: lastWeekDay),
                    70 * 60, "and the week before that, one step back", &problems)
        expectClose(PeriodStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                         now: { clock.value }),
                                usage: AppUsageArchive(directory: scratchDirectory(),
                                                       now: { clock.value }),
                                now: { clock.value })
                        .previousPeriodTracked(for: .month, containing: clock.value),
                    0, "nothing recorded reads as zero", &problems)
        return problems
    }

    // MARK: - 84

    /// The popover must still fit a 13" screen after the hero grew a ring and
    /// the glance became cards. Measured with the real view: render the
    /// densest fixture at the 13" metrics and check its height against the
    /// screen's share, the same way the harness does.
    private static func testPopoverStillFits13Inch() -> [String] {
        var problems: [String] = []
        let metrics = PopoverMetrics.fitting(CGSize(width: 1_440, height: 845))
        let height: CGFloat = MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .needsResolution)
            let view = PopoverView(store: store, metricsOverride: metrics, scrolls: false)
                .frame(width: metrics.width)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return renderer.nsImage?.size.height ?? .infinity
        }
        expect(height <= metrics.maxHeight,
               "needs-resolution panel is \(Int(height))pt, budget \(Int(metrics.maxHeight))",
               &problems)
        return problems
    }

    // MARK: - 85

    /// Which prompt an absence gets is a pure rule, and "Never" must mean the
    /// quick one rather than none — the question is still asked.
    private static func testAwayPromptTier() -> [String] {
        var problems: [String] = []
        expect(AwayPromptTier.tier(forAbsence: 20 * 60, fullPromptAfter: 30 * 60) == .quick,
               "under the threshold is quick", &problems)
        expect(AwayPromptTier.tier(forAbsence: 30 * 60, fullPromptAfter: 30 * 60) == .full,
               "at the threshold is full", &problems)
        expect(AwayPromptTier.tier(forAbsence: 3 * 3_600, fullPromptAfter: 30 * 60) == .full,
               "well over is full", &problems)
        expect(AwayPromptTier.tier(forAbsence: 3 * 3_600, fullPromptAfter: nil) == .quick,
               "Never means always quick", &problems)

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        expectClose(store.fullPromptAfter ?? -1, FocusConstants.defaultFullPromptAfter,
                    "missing key reads as the default", &problems)
        store.fullPromptAfter = nil
        expect(store.fullPromptAfter == nil, "Never round-trips as nil", &problems)
        store.fullPromptAfter = 3_600
        expectClose(store.fullPromptAfter ?? -1, 3_600, "a value round-trips", &problems)
        return problems
    }

    // MARK: - 86

    /// The card says when, not only how long. The range is derived from the
    /// return moment the engine already stamps, so it cannot disagree with the
    /// length beside it.
    private static func testPendingAwayRange() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Range")
        expect(engine.pendingAwayRange == nil, "nothing pending while running", &problems)
        clock.advance(600)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(22 * 60)
        engine.transition(on: .awayEnded)
        guard let range = engine.pendingAwayRange else {
            return problems + ["a 22-minute lock should leave a pending range"]
        }
        expectClose(range.end.timeIntervalSince(range.start), 22 * 60,
                    "the range spans the absence", &problems)
        expectClose(range.end.timeIntervalSince(clock.value), 0,
                    "and ends when the user came back", &problems)

        // A relaunch three hours later must not move the absence: the card
        // still says when it was, not when the app came back up.
        let snapshot = engine.snapshot()
        let returned = clock.value
        clock.advance(3 * 3_600)
        let revived = makeEngine(clock)
        revived.restore(from: snapshot)
        guard let kept = revived.pendingAwayRange else {
            return problems + ["restored card should still carry its range"]
        }
        expectClose(kept.end.timeIntervalSince(returned), 0,
                    "the range still ends at the real return", &problems)
        expectClose(kept.end.timeIntervalSince(kept.start), 22 * 60,
                    "and still spans the absence", &problems)

        engine.transition(on: .decision(.continueSession))
        expect(engine.pendingAwayRange == nil, "answered means no range", &problems)
        return problems
    }

    // MARK: - 87

    /// After a break the clock must pick up where it left off: the running
    /// thread's earlier stretches today plus the live one, never a stretch
    /// alone, and never another thread's work.
    private static func testThreadClock() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let archive = SessionArchive(directory: directory)
        let engine = SessionEngine(store: prefs, archive: archive,
                                   ownBundleID: "com.test", schedulesDwell: false)
        let thread = UUID()
        let now = anchoredNow()
        archive.append(SessionRecord(name: "Deep work", workType: .deepWork,
                                     start: now.addingTimeInterval(-3_000),
                                     end: now.addingTimeInterval(-1_200),
                                     workSeconds: 1_800, threadID: thread))
        archive.append(SessionRecord(name: "Deep work", workType: .deepWork,
                                     start: now.addingTimeInterval(-900),
                                     end: now.addingTimeInterval(-300),
                                     workSeconds: 600, threadID: thread))
        archive.append(SessionRecord(name: "Email", workType: .admin,
                                     start: now.addingTimeInterval(-2_400),
                                     end: now.addingTimeInterval(-2_100),
                                     workSeconds: 300))
        engine.start(workType: .deepWork, intent: "Deep work", threadID: thread)

        let store = SessionStore(engine: engine)
        store.refresh()
        expect(abs(store.threadElapsed - 2_400) < 5,
               "thread clock carries both earlier stretches, got \(Int(store.threadElapsed))",
               &problems)
        expect(store.threadSegments == 3, "three stretches, got \(store.threadSegments)", &problems)
        expect(store.continuationNote?.contains("Deep work continues") == true,
               "the card says which work carries on", &problems)

        engine.stop()
        store.refresh()
        expect(store.threadElapsed == 0 && store.threadSegments == 0,
               "idle means no thread clock", &problems)
        return problems
    }

    // MARK: - 88

    /// Back from the kitchen into the same app: the same thread, clock and
    /// all. Back into something unrelated: new work, and the old thread kept
    /// for Continue rather than stretched over it. "I was working" and "Start
    /// fresh" are unaffected — they already say what they mean.
    private static func testAppAwareContinuity() -> [String] {
        var problems: [String] = []
        func scenario(returnTo app: String?, decision: UserDecision,
                      matcher: ((String?) -> Bool)?) -> (same: Bool, name: String) {
            let clock = Clock(base)
            let engine = makeEngine(clock)
            engine.threadContextMatcher = matcher
            engine.transition(on: .appActivated(bundleID: "com.ide", name: "IDE"))
            engine.start(workType: .deepWork, intent: "Refactor")
            let thread = engine.activeThreadID
            clock.advance(1_800)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(22 * 60)
            engine.transition(on: .awayEnded)
            if let app {
                engine.transition(on: .appActivated(bundleID: app, name: app))
            }
            engine.transition(on: .decision(decision))
            return (engine.activeThreadID == thread, engine.sessionName)
        }
        let ideOnly: (String?) -> Bool = { $0 == "com.ide" }

        expect(scenario(returnTo: nil, decision: .tookBreak, matcher: ideOnly).same,
               "same app on return keeps the thread", &problems)
        expect(scenario(returnTo: "com.ide", decision: .continueSession, matcher: ideOnly).same,
               "re-activating the same app keeps it too", &problems)
        let switched = scenario(returnTo: "com.browser", decision: .tookBreak, matcher: ideOnly)
        expect(!switched.same, "a different app starts new work", &problems)
        expect(switched.name.isEmpty, "and the new work does not inherit the old name", &problems)
        expect(scenario(returnTo: "com.browser", decision: .tookBreak, matcher: nil).same,
               "without a matcher the thread is kept — callers without usage data", &problems)
        expect(scenario(returnTo: "com.browser", decision: .mergeTime, matcher: ideOnly).same,
               "'I was working' never re-threads", &problems)
        expect(!scenario(returnTo: nil, decision: .resetTimer, matcher: ideOnly).same,
               "'Start fresh' always does", &problems)
        return problems
    }

    // MARK: - 89

    /// The rhythm chart sums tracked seconds per hour, splitting a stretch that
    /// crosses the hour, colours the hour by the app that took most of it, and
    /// names the busiest run.
    private static func testRhythm() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func seg(_ fromMinutes: Double, _ toMinutes: Double, color: Int) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: "b\(color)", appName: "A\(color)",
                            start: day.addingTimeInterval(fromMinutes * 60),
                            end: day.addingTimeInterval(toMinutes * 60), colorIndex: color)
        }
        // 9:00–10:30 app 0 (crosses 10:00), 10:20–10:40 app 1, 11:00–11:10 app 2.
        let segments = [seg(9 * 60, 10 * 60 + 30, color: 0),
                        seg(10 * 60 + 20, 10 * 60 + 40, color: 1),
                        seg(11 * 60, 11 * 60 + 10, color: 2)]
        let hours = Rhythm.hours(segments: segments,
                                 window: (day.addingTimeInterval(9 * 3_600),
                                          day.addingTimeInterval(12 * 3_600)),
                                 calendar: calendar)
        expect(hours.count == 3, "three hours in the window, got \(hours.count)", &problems)
        guard hours.count == 3 else { return problems }
        expectClose(hours[0].seconds, 3_600, "9am is a full hour of app 0", &problems)
        expect(hours[0].colorIndex == 0, "and coloured by it", &problems)
        expectClose(hours[1].seconds, 1_800 + 1_200, "10am sums both apps", &problems)
        expect(hours[1].colorIndex == 0, "app 0's 30m beats app 1's 20m", &problems)
        expectClose(hours[2].seconds, 600, "11am has ten minutes", &problems)
        let label = Rhythm.peakLabel(hours) { date in
            "\(calendar.component(.hour, from: date))h"
        }
        // The run covers the 9 and 10 o'clock hours, so it ends at 11 — the
        // same convention as "4–6am" for the hours 4 and 5.
        expect(label == "9h–11h", "peak run is 9–11, got \(label ?? "nil")", &problems)
        expect(Rhythm.peakLabel([]) { _ in "" } == nil, "no hours, no peak", &problems)
        return problems
    }

    // MARK: - 90

    /// "Dinner" in the reason field becomes the break record's name — what the
    /// timeline labels the gap — capitalised and trimmed; no name means
    /// "Break"; and a label given with any other answer is consumed, not kept
    /// for the next question.
    private static func testNamedBreak() -> [String] {
        var problems: [String] = []
        func absence(_ engine: SessionEngine, _ clock: Clock) {
            clock.advance(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(22 * 60)
            engine.transition(on: .awayEnded)
        }
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Work")
        absence(engine, clock)
        engine.decide(.tookBreak, label: "  dinner ")
        let named = engine.archive.records.last { $0.workType == .breakTime }
        expect(named?.name == "Dinner", "the break is recorded as Dinner, got \(named?.name ?? "nil")",
               &problems)
        expectClose(named?.workSeconds ?? 0, 22 * 60, "for the absence's length", &problems)

        absence(engine, clock)
        engine.decide(.tookBreak)
        let plain = engine.archive.records.last { $0.workType == .breakTime }
        expect(plain?.name == "Break", "no name means Break", &problems)

        absence(engine, clock)
        engine.decide(.continueSession, label: "lunch")
        let count = engine.archive.records.filter { $0.workType == .breakTime }.count
        expect(count == 2, "'I was away' with a label records nothing", &problems)
        absence(engine, clock)
        engine.decide(.tookBreak)
        expect(engine.archive.records.last { $0.workType == .breakTime }?.name == "Break",
               "and the label did not leak into the next break", &problems)
        return problems
    }

    // MARK: - 91

    /// The Sessions card's rows: two stretches of one thread with a break
    /// between them are one session with two stretches and a rest row; a
    /// different thread is its own session; the running session joins its
    /// thread and is marked.
    private static func testSessionDigest() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        let thread = UUID()
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
        let records = [
            SessionRecord(name: "Refactor", workType: .deepWork, start: at(9), end: at(10),
                          workSeconds: 3_600, threadID: thread),
            SessionRecord(name: "Dinner", workType: .breakTime, start: at(10), end: at(10.5),
                          workSeconds: 1_800),
            SessionRecord(name: "Refactor", workType: .deepWork, start: at(10.5), end: at(11),
                          workSeconds: 1_800, threadID: thread),
            SessionRecord(name: "Email", workType: .admin, start: at(13), end: at(13.5),
                          workSeconds: 1_800)
        ]
        let running = RunningThread(threadID: thread, name: "Refactor", workType: .deepWork,
                                    start: at(15), worked: 600)
        let entries = SessionDigest.entries(records: records, running: running, now: at(15.2))
        expect(entries.count == 4, "session, rest, session, running session → 4 rows, got \(entries.count)",
               &problems)
        guard entries.count == 4 else { return problems }
        guard case .session(let first) = entries[0] else { return problems + ["first row is a session"] }
        expect(first.stretches == 2, "two stretches fold into one session, got \(first.stretches)", &problems)
        expectClose(first.worked, 5_400, "worked sums the stretches", &problems)
        expect(first.spans.count == 2, "and keeps both spans", &problems)
        guard case .rest(let rest) = entries[1] else { return problems + ["second row is the rest"] }
        expect(rest.name == "Dinner", "the rest keeps its name", &problems)
        guard case .session(let email) = entries[2] else { return problems + ["third row is Email"] }
        expect(email.workType == .admin && email.stretches == 1, "another thread is its own row", &problems)
        guard case .session(let live) = entries[3] else { return problems + ["fourth row is the running one"] }
        expect(live.isRunning && live.threadID == thread, "the running session is marked", &problems)
        expect(live.stretches == 1, "and, separated by another thread, starts its own row", &problems)
        return problems
    }

    // MARK: - 92

    /// "Apps used inside this session": usage intersected with the session's
    /// spans, ranked, with shares out of the inside rather than the day.
    private static func testAppsWithinSpans() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(base)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let day = Calendar.current.startOfDay(for: base)
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
        usage.record(AppUsageSession(bundleID: "com.a", appName: "A", start: at(9), end: at(10)))   // 1h
        usage.record(AppUsageSession(bundleID: "com.b", appName: "B", start: at(10), end: at(10.5))) // 30m
        usage.record(AppUsageSession(bundleID: "com.c", appName: "C", start: at(14), end: at(16)))  // outside
        let stats = DashboardStats(sessions: SessionArchive(directory: directory, now: { clock.value }),
                                   usage: usage, now: { clock.value })
        let inside = stats.rankedApps(for: day, within: [DateInterval(start: at(9.5), end: at(10.5))])
        expect(inside.map(\.bundleID) == ["com.a", "com.b"], "A then B, C excluded, got \(inside.map(\.bundleID))",
               &problems)
        expectClose(inside.first?.total ?? 0, 1_800, "A counts only its 30m inside the span", &problems)
        expectClose(inside.first?.share ?? 0, 0.5, "shares are of the inside (30m of 60m)", &problems)
        expectClose(stats.trackedTotal(for: day, within: [DateInterval(start: at(9.5), end: at(10.5))]),
                    3_600, "hands-on inside the span", &problems)
        return problems
    }

    // MARK: - 93

    /// The summary is the figures in words. A full day names its time, its
    /// sessions, its apps and the day before; an empty day says it is empty;
    /// a share over 100% is never written; today speaks in the present.
    private static func testSummaryText() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
        let thread = UUID()
        let deep = DaySession(id: UUID(), threadID: thread, name: "Refactor the parser",
                              workType: .deepWork, start: at(8.75), end: at(15.9),
                              worked: 3 * 3_600 + 47 * 60, stretches: 4,
                              spans: [DateInterval(start: at(8.75), end: at(12)),
                                      DateInterval(start: at(12.5), end: at(15.9))],
                              isRunning: false)
        let email = DaySession(id: UUID(), threadID: UUID(), name: "", workType: .admin,
                               start: at(16), end: at(16.5), worked: 1_800, stretches: 1,
                               spans: [DateInterval(start: at(16), end: at(16.5))], isRunning: false)
        let lunch = RestEntry(id: UUID(), name: "Lunch", start: at(12), end: at(12.5))
        var input = DaySummaryInput(
            day: day, isToday: false,
            tracked: 8 * 3_600 + 6 * 60, firstSeen: at(8.7), lastSeen: at(23.35),
            focused: 4 * 3_600 + 17 * 60, goal: 4 * 3_600,
            sessions: [deep, email], rests: [lunch],
            apps: [AppRank(bundleID: "a", appName: "Dia", total: 3 * 3_600 + 4 * 60, share: 0.38, longest: 0),
                   AppRank(bundleID: "b", appName: "Claude", total: 2 * 3_600 + 19 * 60, share: 0.29, longest: 0),
                   AppRank(bundleID: "c", appName: "Finder", total: 600, share: 0.02, longest: 0)],
            peak: "1pm–4pm", insideSessionShare: 0.45, switchesPerStretch: 57.3,
            workTypes: [WorkTypeShare(workType: .deepWork, seconds: 3_000, share: 0.94),
                        WorkTypeShare(workType: .breakTime, seconds: 200, share: 0.06)],
            previousTracked: 9 * 3_600, previousFocused: 3 * 3_600 + 7 * 60)
        let text = SummaryText.plain(SummaryText.day(input))
        for needle in ["You were at the Mac for 8h 6m", "focused for 4h 17m in 2 sessions",
                       "53% of that time", "goal met",
                       "The longest, Deep work, Refactor the parser, ran", "for 3h 47m in 4 stretches with one break (Lunch 30m)",
                       "Most of the time went to Dia (3h 4m, 38%) and Claude (2h 19m, 29%), across 3 apps in all",
                       "the busiest hours were 1pm–4pm",
                       "45% of the time at the Mac fell inside a session, with about 57 app switches per stretch",
                       "by type, Deep work 94%, Break 6%",
                       "54m less at the Mac and 1h 10m more focused"] {
            expect(text.contains(needle), "summary says “\(needle)”, got: \(text)", &problems)
        }
        expect(!text.contains("**"), "plain text carries no bold marks", &problems)
        expect(SummaryText.day(input).count == 5, "five sentences for a full day", &problems)

        // Short of the goal, written as a shortfall on a past day.
        input.focused = 3 * 3_600 + 47 * 60
        expect(SummaryText.plain(SummaryText.day(input)).contains("13m short of the 4h goal"),
               "a past day fell short", &problems)

        // Today: present tense, "to the goal", and a running session is said to run.
        input.isToday = true
        input.sessions = [DaySession(id: deep.id, threadID: thread, name: deep.name, workType: .deepWork,
                                     start: deep.start, end: deep.end, worked: deep.worked, stretches: 4,
                                     spans: deep.spans, isRunning: true), email]
        let today = SummaryText.plain(SummaryText.day(input))
        expect(today.hasPrefix("So far today you've been at the Mac for 8h 6m, since"),
               "today speaks in the present, got: \(today)", &problems)
        expect(today.contains("13m to the 4h goal"), "today has a goal to reach", &problems)
        expect(today.contains("and it's still running"), "the running session is named as running", &problems)
        expect(today.contains("Against the whole of yesterday"), "today compares against all of yesterday", &problems)

        // Focused above tracked: the share is not a share, so it is not said.
        input.focused = 9 * 3_600
        expect(!SummaryText.plain(SummaryText.day(input)).contains("% of that time"),
               "no share above 100%", &problems)

        // Nothing at all.
        input = DaySummaryInput(day: day, isToday: false, tracked: 0, firstSeen: nil, lastSeen: nil,
                                focused: 0, goal: 4 * 3_600, sessions: [], rests: [], apps: [], peak: nil,
                                insideSessionShare: 0, switchesPerStretch: 0, workTypes: [],
                                previousTracked: 0, previousFocused: 0)
        expect(SummaryText.day(input) == ["Nothing was recorded on this day."],
               "an empty day says so and nothing else", &problems)

        // A week.
        let week = SummaryText.plain(SummaryText.period(PeriodSummaryInput(
            period: .week, containsToday: true, tracked: 31 * 3_600 + 20 * 60, activeDays: 5, totalDays: 7,
            averagePerActiveDay: 6 * 3_600 + 16 * 60, previousTracked: 29 * 3_600 + 10 * 60,
            focused: 14 * 3_600, sessions: 9, goal: 4 * 3_600, goalMetDays: 2,
            busiestDay: day, busiestTracked: 8 * 3_600 + 6 * 60,
            longestSitting: ("Dia", 95 * 60, day), apps: [("Dia", 12 * 3_600, 0.38)], appCount: 14,
            workTypes: [])))
        for needle in ["This week you were at the Mac for 31h 20m across 5 of 7 days — 6h 16m per active day, 2h 10m more than the week before.",
                       "You focused for 14h in 9 sessions, meeting the 4h goal on 2 days.",
                       "(8h 6m); the longest single sitting was 1h 35m in Dia on",
                       "All of the time was in Dia, across 14 apps in all."] {
            expect(week.contains(needle), "week summary says “\(needle)”, got: \(week)", &problems)
        }
        return problems
    }

    // MARK: - 94

    /// A session is a thread. Two stretches of one thread are one session with
    /// their work added; the running stretch joins its thread's count rather
    /// than adding one; a different thread is another session.
    private static func testSessionsAreThreads() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let archive = SessionArchive(directory: directory)
        let engine = SessionEngine(store: prefs, archive: archive,
                                   ownBundleID: "com.test", schedulesDwell: false)
        let thread = UUID()
        let now = anchoredNow()
        archive.append(SessionRecord(name: "Parser", workType: .deepWork,
                                     start: now.addingTimeInterval(-7_200),
                                     end: now.addingTimeInterval(-5_400),
                                     workSeconds: 1_800, threadID: thread))
        archive.append(SessionRecord(name: "Parser, tests", workType: .deepWork,
                                     start: now.addingTimeInterval(-5_000),
                                     end: now.addingTimeInterval(-2_300),
                                     workSeconds: 2_700, threadID: thread))
        archive.append(SessionRecord(name: "Email", workType: .admin,
                                     start: now.addingTimeInterval(-2_000),
                                     end: now.addingTimeInterval(-1_000),
                                     workSeconds: 1_000))
        archive.append(SessionRecord(name: "Lunch", workType: .breakTime,
                                     start: now.addingTimeInterval(-5_400),
                                     end: now.addingTimeInterval(-5_000),
                                     workSeconds: 400))
        expect(archive.focusCount(on: now) == 3, "three focus stretches", &problems)
        expect(archive.threadCount(on: now) == 2,
               "two sessions — the thread once, got \(archive.threadCount(on: now))", &problems)
        let longest = archive.longestThread(on: now)
        expectClose(longest?.seconds ?? 0, 4_500, "the thread's stretches add up", &problems)
        expect(longest?.name == "Parser, tests", "named by its latest stretch, got \(longest?.name ?? "nil")",
               &problems)
        expectClose(archive.threadWork(thread, on: now), 4_500, "thread work on the day", &problems)
        expect(archive.sessionsToday() == 2 && abs(archive.longestToday() - 4_500) < 1,
               "today's figures count threads", &problems)

        // Running on the same thread: still two sessions; the longest grows.
        engine.start(workType: .deepWork, intent: "Parser", threadID: thread)
        expect(engine.sessionsToday == 2, "the running stretch joins its thread, got \(engine.sessionsToday)",
               &problems)
        expect(engine.longestToday >= 4_500, "longest is the thread with its live stretch", &problems)
        engine.stop()
        // Running on a new thread: a third session.
        engine.start(workType: .deepWork, intent: "Fresh")
        expect(engine.sessionsToday == 3, "a new thread is a new session, got \(engine.sessionsToday)",
               &problems)
        engine.stop()
        return problems
    }

    // MARK: - 95

    /// The lid closes at T (away begins). The machine sleeps; during a dark
    /// wake the idle sampler, whose clock did not run while asleep, back-dates
    /// a pause only to T+86m. The wake at T+132m must measure the absence from
    /// T: past the cap the session ends where the lid closed, and below the
    /// cap the question is about the whole of it.
    private static func testAbsenceFromWhereItBegan() -> [String] {
        var problems: [String] = []
        func scenario(capHours: Double) -> (engine: SessionEngine, archive: SessionArchive, clock: Clock) {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = capHours * 3_600
            let clock = Clock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Lid test")
            clock.advance(30 * 60)                                     // 30m of work
            engine.transition(on: .awayBegan(trigger: .systemSleep))    // T: lid closes
            clock.advance(96 * 60)                                     // asleep, dark wakes
            engine.transition(on: .idleObserved(seconds: 600))         // sampler: "idle 10m" → pause at T+86m
            guard engine.state.isPaused else { problems.append("the sampler pauses"); return (engine, archive, clock) }
            clock.advance(36 * 60)                                     // T+132m: lid opens
            engine.transition(on: .awayEnded)
            return (engine, archive, clock)
        }

        // Cap one hour: 132 minutes away ends the session where the lid closed.
        let capped = scenario(capHours: 1)
        expect(capped.engine.state == .idle, "past the cap the session is over, got \(capped.engine.state)", &problems)
        let record = capped.archive.records.last
        expectClose(record?.end.timeIntervalSince(base) ?? 0, 30 * 60,
                    "the record ends where the lid closed, not at the late pause", &problems)
        expectClose(record?.workSeconds ?? 0, 30 * 60, "and carries only the work before it", &problems)

        // Cap four hours: the question is about 132 minutes, not the pause's 46.
        let asked = scenario(capHours: 4)
        if case .awaitingUserDecision(let away, _) = asked.engine.state {
            expectClose(away, 132 * 60, "the whole absence is asked about, got \(Int(away / 60))m", &problems)
        } else {
            problems.append("below the cap the absence is asked about, got \(asked.engine.state)")
        }
        return problems
    }

    // MARK: - 96

    /// The app comes back up while the screen is still locked. The snapshot
    /// says the absence began at T; nobody has returned, so it must stay open
    /// and the unlock must measure all of it — not the slice up to the launch.
    private static func testRestoreBehindLock() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        prefs.longAwayCap = 4 * 3_600
        let clock = Clock(base)
        let archive = SessionArchive(directory: directory, now: { clock.value })
        let first = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                  schedulesDwell: false, now: { clock.value })
        first.start(workType: .deepWork, intent: "Lock test")
        clock.advance(20 * 60)
        first.transition(on: .awayBegan(trigger: .screenLock))      // T: locked
        let snapshot = first.snapshot()

        // Relaunched 10 minutes later, still locked; unlocked 30 minutes after that.
        clock.advance(10 * 60)
        let relaunched = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
        relaunched.restore(from: snapshot, awayAtLaunch: true)
        expect(relaunched.state == .running, "still running, nothing resolved yet, got \(relaunched.state)", &problems)
        clock.advance(30 * 60)
        relaunched.transition(on: .awayEnded)
        if case .awaitingUserDecision(let away, _) = relaunched.state {
            expectClose(away, 40 * 60, "the unlock measures from the lock, got \(Int(away / 60))m", &problems)
        } else {
            problems.append("the unlock asks about the absence, got \(relaunched.state)")
        }

        // Not locked at launch: the gap since the snapshot is resolved at once, as before.
        clock.advance(5 * 60)
        let unlockedLaunch = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                           schedulesDwell: false, now: { clock.value })
        unlockedLaunch.restore(from: snapshot, awayAtLaunch: false)
        if case .awaitingUserDecision(let away, _) = unlockedLaunch.state {
            expectClose(away, 45 * 60, "an unlocked launch resolves the gap since the lock", &problems)
        } else {
            problems.append("an unlocked launch resolves at once, got \(unlockedLaunch.state)")
        }
        return problems
    }

    // MARK: - 97

    /// The popover's Today band is today's whatever day the dashboard shows:
    /// stepping the dashboard to yesterday must leave the glance segments,
    /// brackets and hover on today. It used to draw the selected day's
    /// segments on today's axis, which emptied the band.
    private static func testGlanceStaysOnToday() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return ["calendar"] }
        let usage = AppUsageArchive(directory: directory)
        usage.record(AppUsageSession(bundleID: "com.y", appName: "Y",
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(10 * 3_600)))
        usage.record(AppUsageSession(bundleID: "com.t", appName: "T",
                                     start: today.addingTimeInterval(60),
                                     end: today.addingTimeInterval(3_500)))
        let archive = SessionArchive(directory: directory)
        archive.append(SessionRecord(name: "Y work", workType: .deepWork,
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(10 * 3_600), workSeconds: 3_600))
        archive.append(SessionRecord(name: "T work", workType: .deepWork,
                                     start: today.addingTimeInterval(60),
                                     end: today.addingTimeInterval(3_500), workSeconds: 3_440))
        let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                   schedulesDwell: false)
        let store = SessionStore(engine: engine)
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.test", idle: .disabled)
        store.attach(tracker: tracker, usage: usage)
        store.refresh()
        expect(store.timelineSegments.map(\.bundleID) == ["com.t"],
               "today's segments on today, got \(store.timelineSegments.map(\.bundleID))", &problems)
        store.stepDay(by: -1)
        expect(store.timelineSegments.map(\.bundleID) == ["com.y"],
               "the dashboard browses yesterday, got \(store.timelineSegments.map(\.bundleID))", &problems)
        expect(store.glanceTimeline.map(\.bundleID) == ["com.t"],
               "the glance band stays on today, got \(store.glanceTimeline.map(\.bundleID))", &problems)
        expect(store.glanceBrackets.count == 1 && store.focusBrackets.count == 1,
               "brackets: today's for the glance, yesterday's for the page", &problems)
        store.hoverTimeline(at: 0.5, glance: true)
        expect(store.hoveredSegment?.bundleID == "com.t",
               "hovering the glance band names today's app, got \(store.hoveredSegment?.bundleID ?? "nil")",
               &problems)
        store.hoverTimeline(at: 0.5)
        expect(store.hoveredSegment?.bundleID == "com.y",
               "hovering the page names yesterday's, got \(store.hoveredSegment?.bundleID ?? "nil")", &problems)
        return problems
    }

    // MARK: - 98

    /// Watching is presence, not absence: a Deep work session quietly pauses
    /// behind a film and writes it down as "Watching"; a Meetings session keeps
    /// counting; once the film ends, idle counts from then; a lock mid-film
    /// begins the absence at the lock.
    private static func testWatchingIsNotAbsence() -> [String] {
        var problems: [String] = []
        func make(_ type: WorkType) -> (engine: SessionEngine, archive: SessionArchive, clock: Clock) {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = 4 * 3_600
            prefs.breakThreshold = 5 * 60
            let clock = Clock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: type, intent: "Watch test")
            clock.advance(20 * 60)                                   // 20m of work, then the film
            return (engine, archive, clock)
        }

        // Deep work: ten quiet minutes behind a film → a quiet pause, back-dated.
        let deep = make(.deepWork)
        deep.clock.advance(10 * 60)
        deep.engine.transition(on: .watchingObserved(seconds: 600))
        expect(deep.engine.state == .paused(reason: .watching),
               "watching pauses deep work quietly, got \(deep.engine.state)", &problems)
        deep.clock.advance(35 * 60)                                  // the film runs on
        deep.engine.transition(on: .watchingObserved(seconds: 45 * 60))
        deep.engine.transition(on: .idleObserved(seconds: 2))        // a keypress
        expect(deep.engine.state == .running, "input resumes without a question, got \(deep.engine.state)",
               &problems)
        expectClose(deep.engine.elapsed, 20 * 60, "the film is not work", &problems)
        let watched = deep.archive.records.last
        expect(watched?.workType == .breakTime && watched?.name == "Watching",
               "a Watching rest is written down, got \(String(describing: watched?.name))", &problems)
        expectClose(watched?.workSeconds ?? 0, 45 * 60, "for the time watched", &problems)

        // Meetings: the same quiet is attendance.
        let meeting = make(.meetings)
        meeting.clock.advance(10 * 60)
        meeting.engine.transition(on: .watchingObserved(seconds: 600))
        expect(meeting.engine.state == .running, "a meeting keeps counting while watched", &problems)
        expectClose(meeting.engine.elapsed, 30 * 60, "and the minutes are kept", &problems)

        // The film ends at T+60 and nobody touches the machine: idle counts
        // from the film's end, and the question on return is about that.
        let left = make(.deepWork)
        left.clock.advance(10 * 60)
        left.engine.transition(on: .watchingObserved(seconds: 600))
        left.clock.advance(42 * 60)                                  // T+72: 12m since the film ended
        left.engine.transition(on: .idleObserved(seconds: 12 * 60))
        expect(left.engine.state == .paused(reason: .idle),
               "after the film, quiet is idle, got \(left.engine.state)", &problems)
        expectClose(left.archive.records.last?.workSeconds ?? 0, 40 * 60,
                    "the Watching rest ends where the film did", &problems)
        left.clock.advance(3 * 60)                                   // T+75
        left.engine.transition(on: .idleObserved(seconds: 1))        // back
        if case .awaitingUserDecision(let away, _) = left.engine.state {
            expectClose(away, 15 * 60, "asked about the 15m after the film, not the film, got \(Int(away / 60))m",
                        &problems)
        } else {
            problems.append("asked about the absence after the film, got \(left.engine.state)")
        }

        // A lock mid-film: the absence begins at the lock.
        let locked = make(.deepWork)
        locked.clock.advance(10 * 60)
        locked.engine.transition(on: .watchingObserved(seconds: 600))
        locked.clock.advance(20 * 60)                                // T+50
        locked.engine.transition(on: .awayBegan(trigger: .screenLock))
        locked.clock.advance(8 * 60)                                 // T+58
        locked.engine.transition(on: .awayEnded)
        if case .awaitingUserDecision(let away, _) = locked.engine.state {
            expectClose(away, 8 * 60, "the question is about the time away, not the film, got \(Int(away / 60))m",
                        &problems)
        } else {
            problems.append("a lock mid-film asks about the lock, got \(locked.engine.state)")
        }
        return problems
    }

    // MARK: - 99

    /// A question is pending; the user walks off for forty minutes without
    /// locking anything. That quiet is banked as a second absence, so neither
    /// "I was working" nor "It was a break" can hand it to a session.
    private static func testQuietWhileAwaiting() -> [String] {
        var problems: [String] = []
        func scenario(_ decision: UserDecision) -> SessionEngine {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = 4 * 3_600
            prefs.breakThreshold = 5 * 60
            let clock = Clock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Pending test")
            clock.advance(20 * 60)
            engine.transition(on: .awayBegan(trigger: .screenLock))   // T+20
            clock.advance(10 * 60)
            engine.transition(on: .awayEnded)                          // T+30: asked about 10m
            guard case .awaitingUserDecision = engine.state else {
                problems.append("the ten minutes are asked about, got \(engine.state)"); return engine
            }
            clock.advance(2 * 60)                                      // T+32: two ordinary minutes
            clock.advance(10 * 60)                                     // T+42: ten quiet minutes
            engine.transition(on: .idleObserved(seconds: 600))         // opens the second absence at T+32
            clock.advance(30 * 60)                                     // T+72: still gone
            engine.transition(on: .idleObserved(seconds: 40 * 60))
            engine.transition(on: .idleObserved(seconds: 1))           // T+72: back; 40m banked
            clock.advance(60)                                          // T+73: answers
            engine.transition(on: .decision(decision))
            return engine
        }
        let merged = scenario(.mergeTime)
        expectClose(merged.elapsed, 33 * 60,
                    "I was working: 20 + the 10 merged + 3 ordinary, never the 40 quiet, got \(Int(merged.elapsed / 60))m",
                    &problems)
        let broke = scenario(.tookBreak)
        expectClose(broke.elapsed, 3 * 60,
                    "It was a break: the new stretch holds 3 ordinary minutes, not 43, got \(Int(broke.elapsed / 60))m",
                    &problems)
        return problems
    }

    // MARK: - 100

    /// An app's self-declared App Store category names its purpose only when
    /// neither a rule nor an override speaks — and automatic sessions carry a
    /// name from what the user is doing, "Browsing" in anything ambiguous.
    private static func testCategoryFallbackAndNames() -> [String] {
        var problems: [String] = []
        // The pure mapping.
        expect(PurposeMap.categoryFallback("public.app-category.developer-tools") == .coding,
               "developer-tools reads as coding", &problems)
        expect(PurposeMap.categoryFallback("public.app-category.social-networking") == .communication,
               "social-networking reads as communication", &problems)
        expect(PurposeMap.categoryFallback("public.app-category.music") == .media,
               "music reads as media", &problems)
        expect(PurposeMap.categoryFallback("public.app-category.lifestyle") == nil
                   && PurposeMap.categoryFallback(nil) == nil,
               "a category with nothing to say stays silent", &problems)

        // Precedence, with the injected lookup saved and restored: it is
        // process-global and the other tests assume the default.
        let saved = PurposeMap.declaredCategory
        defer { PurposeMap.declaredCategory = saved }
        PurposeMap.declaredCategory = { bundleID in
            switch bundleID {
            case "com.example.unmapped-ide": return "public.app-category.developer-tools"
            case "com.apple.dt.Xcode": return "public.app-category.music"   // a lie a rule outranks
            default: return nil
            }
        }
        expect(PurposeMap.purpose(for: "com.example.unmapped-ide", activity: .active) == .coding,
               "an unmapped app is read from its declared category", &problems)
        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .active) == .coding,
               "a rule outranks the declared category", &problems)
        expect(PurposeMap.purpose(for: "com.example.mystery", activity: .active) == .utility,
               "unmapped and unlabelled stays a utility", &problems)
        expect(PurposeMap.purpose(for: "com.example.unmapped-ide", activity: .active,
                                  overrides: ["com.example.unmapped-ide": "media"]) == .media,
               "the user's override outranks everything", &problems)

        // Names.
        expect(AutoSessionDetector.sessionName(forApp: "company.thebrowser.dia", purpose: .writingAI)
                   == "Browsing",
               "an ambiguous app names the act, not the tool", &problems)
        expect(AutoSessionDetector.sessionName(forApp: "com.apple.dt.Xcode", purpose: .coding)
                   == "Coding", "coding names itself", &problems)
        expect(AutoSessionDetector.sessionName(forApp: "com.example.mystery", purpose: .utility)
                   == "", "a utility has no name to give", &problems)
        return problems
    }

    // MARK: - 101

    /// The lid closes; the machine dark-wakes all evening. No wake event ends
    /// the absence any more — only confirmed input does — so the whole of it
    /// is measured from the lid close: past the cap the session ends there,
    /// and a late idle pause cannot shorten what is asked.
    private static func testWakeIsNotAReturn() -> [String] {
        var problems: [String] = []
        func make(capHours: Double) -> (engine: SessionEngine, archive: SessionArchive, clock: Clock) {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = capHours * 3_600
            prefs.breakThreshold = 5 * 60
            let clock = Clock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Lid test")
            clock.advance(20 * 60)
            engine.transition(on: .awayBegan(trigger: .systemSleep))    // T+20: lid closes
            return (engine, archive, clock)
        }

        // Six hours of dark wakes, the ticker frozen throughout; the first
        // confirmed input resolves the whole absence and ends the session
        // where the lid closed.
        let capped = make(capHours: 1)
        capped.clock.advance(6 * 3_600)
        capped.engine.transition(on: .idleObserved(seconds: 2))          // real input
        expect(capped.engine.state == .idle, "past the cap the session is over, got \(capped.engine.state)",
               &problems)
        let record = capped.archive.records.last
        expectClose(record?.end.timeIntervalSince(base) ?? 0, 20 * 60,
                    "the record ends where the lid closed", &problems)
        expectClose(record?.workSeconds ?? 0, 20 * 60, "and carries only the work before it", &problems)

        // The same evening under a large cap: the question is about all six
        // hours, not the sliver since the last wake.
        let asked = make(capHours: 8)
        asked.clock.advance(6 * 3_600)
        asked.engine.transition(on: .idleObserved(seconds: 2))
        if case .awaitingUserDecision(let away, _) = asked.engine.state {
            expectClose(away, 6 * 3_600, "the whole absence is asked about, got \(Int(away / 60))m", &problems)
        } else {
            problems.append("below the cap the absence is asked about, got \(asked.engine.state)")
        }

        // A ticker that survived long enough to raise a late idle pause must
        // not shorten the measure: the pause folds back to the lid close.
        let folded = make(capHours: 1)
        folded.clock.advance(2 * 3_600)
        folded.engine.transition(on: .idleObserved(seconds: 7_200))      // pause back-dated to T+20
        expect(folded.engine.state.isPaused, "quiet pauses the session", &problems)
        folded.clock.advance(4 * 3_600)
        folded.engine.transition(on: .idleObserved(seconds: 2))          // real input, six hours on
        expect(folded.engine.state == .idle,
               "the folded absence outgrew the cap, got \(folded.engine.state)", &problems)
        expectClose(folded.archive.records.last?.end.timeIntervalSince(base) ?? 0, 20 * 60,
                    "ended where the lid closed, not at the late pause", &problems)
        return problems
    }

    // MARK: - 60

    private static func testLogAppGroups() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        func entry(_ bundleID: String, _ name: String,
                   startMinute: Double, minutes: Double, visits: Int = 1) -> LogEntry {
            let start = day.addingTimeInterval(startMinute * 60)
            return LogEntry(session: AppSession(bundleID: bundleID, appName: name,
                                                start: start,
                                                end: start.addingTimeInterval(minutes * 60),
                                                attended: minutes * 60,
                                                visits: visits),
                            day: day)
        }
        // The shape from the real screenshot: one app scattered across the day.
        let entries = [
            entry("com.anthropic.claudefordesktop", "Claude", startMinute: 700, minutes: 5),
            entry("company.thebrowser.dia", "Dia", startMinute: 690, minutes: 1),
            entry("com.anthropic.claudefordesktop", "Claude", startMinute: 600, minutes: 13,
                  visits: 2),
            entry("com.anthropic.claudefordesktop", "Claude", startMinute: 500, minutes: 11,
                  visits: 6),
            entry("net.whatsapp.WhatsApp", "WhatsApp", startMinute: 400, minutes: 3)
        ]
        let groups = PeriodStats.appGroups(from: entries)

        expect(groups.count == 3, "three apps from five sessions, got \(groups.count)", &problems)
        expect(groups.first?.appName == "Claude", "largest first", &problems)
        expectClose(groups.first?.total ?? 0, 29 * 60,
                    "an app's total is the sum of its sessions", &problems)
        expect(groups.first?.sessions.count == 3,
               "and it keeps every one of them for the expanded view", &problems)
        expect(groups.first?.visits == 9, "visits add up across sessions", &problems)
        expectClose(groups.map(\.share).reduce(0, +), 1.0,
                    "shares cover the whole period exactly once", &problems)
        expect(groups.map(\.total) == groups.map(\.total).sorted(by: >),
               "rows are ordered by time spent", &problems)

        // Order must not shuffle between refreshes when two apps tie.
        let tied = [entry("com.b", "Beta", startMinute: 10, minutes: 5),
                    entry("com.a", "Alpha", startMinute: 20, minutes: 5)]
        expect(PeriodStats.appGroups(from: tied).map(\.appName) == ["Alpha", "Beta"],
               "ties break on name, so the order is stable", &problems)

        expect(PeriodStats.appGroups(from: []).isEmpty,
               "no sessions, no rows", &problems)

        // The expanded panel's figures.
        guard let claude = groups.first else { return problems }
        expectClose(claude.longest, 13 * 60, "longest is the biggest session", &problems)
        expectClose(claude.averageSession, 29 * 60 / 3,
                    "average is the total over the session count", &problems)

        // Its own chart across a period, including days it was never used —
        // a gap has to look like a gap, not be skipped.
        let calendar = Calendar.current
        guard let weekStart = calendar.date(byAdding: .day, value: -3, to: day),
              let weekEnd = calendar.date(byAdding: .day, value: 2, to: day) else {
            return problems
        }
        let daily = claude.dailyTotals(from: weekStart, to: weekEnd)
        expect(daily.count == 6, "one entry per calendar day, got \(daily.count)", &problems)
        expect(daily.filter { $0.seconds > 0 }.count == 1,
               "only the day it was used carries time", &problems)
        expectClose(daily.first(where: { $0.seconds > 0 })?.seconds ?? 0, 29 * 60,
                    "and that day carries all of it", &problems)
        expect(daily.map(\.day) == daily.map(\.day).sorted(),
               "days run oldest first", &problems)

        // The tail: barely-touched apps collapse behind one line, and hiding
        // them must not move anyone else's share.
        let withTail = entries + [
            entry("com.apple.finder", "Finder", startMinute: 300, minutes: 11.0 / 60),
            entry("com.example.flow", "Flow", startMinute: 310, minutes: 5.0 / 60)
        ]
        let all = PeriodStats.appGroups(from: withTail)
        let split = PeriodStats.splitMinor(all)
        expect(split.major.count == 3, "three real apps stay, got \(split.major.count)",
               &problems)
        expect(split.minor.count == 2, "two stragglers collapse, got \(split.minor.count)",
               &problems)
        expect(split.major.allSatisfy { $0.total >= FocusConstants.minorAppFloor },
               "nothing under the floor survives into the main list", &problems)
        expectClose(all.map(\.share).reduce(0, +), 1.0,
                    "shares still cover the period exactly once", &problems)

        // A single straggler is not worth a line that costs the row it saves.
        let one = PeriodStats.appGroups(from: entries + [
            entry("com.apple.finder", "Finder", startMinute: 300, minutes: 11.0 / 60)
        ])
        expect(PeriodStats.splitMinor(one).minor.isEmpty,
               "one straggler is shown rather than collapsed", &problems)
        return problems
    }

    // MARK: - 10

    private static func testExhaustiveTransitions() -> [String] {
        var problems: [String] = []

        let setups: [(String, (SessionEngine, Clock) -> Void)] = [
            ("idle", { _, _ in }),
            ("running", { engine, _ in engine.transition(on: .launch) }),
            ("paused", { engine, _ in
                engine.transition(on: .launch)
                engine.transition(on: .manualPause)
            }),
            ("awaiting", { engine, clock in
                engine.transition(on: .launch)
                engine.transition(on: .awayBegan(trigger: .screenLock))
                clock.advance(1_320)
                engine.transition(on: .awayEnded)
            })
        ]

        let events: [SessionEvent] = [
            .launch,
            .awayBegan(trigger: .screenLock),
            .awayBegan(trigger: .systemSleep),
            .awayEnded,
            .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"),
            .appActivated(bundleID: "com.spotify.client", name: "Spotify"),
            .appActivated(bundleID: nil, name: ""),
            .dwellExpired(bundleID: "com.spotify.client"),
            .dwellExpired(bundleID: "com.unknown.app"),
            .manualPause,
            .manualResume,
            .markedAway,
            .idleObserved(seconds: 0),
            .idleObserved(seconds: FocusConstants.idlePauseThreshold + 1),
            .decision(.continueSession),
            .decision(.mergeTime),
            .decision(.tookBreak),
            .decision(.resetTimer),
            .resetSession,
            .overrideApplied(bundleID: "com.apple.Terminal")
        ]

        for (label, setup) in setups {
            for event in events {
                let clock = Clock(base)
                let engine = makeEngine(clock)
                setup(engine, clock)
                let before = engine.state
                clock.advance(10)
                engine.transition(on: event)
                clock.advance(10)

                if engine.elapsed < 0 {
                    problems.append("\(label) + \(event): negative elapsed")
                }
                if engine.totalPausedDuration < 0 {
                    problems.append("\(label) + \(event): negative totalPaused")
                }
                if before == .idle, engine.state != .idle {
                    // Only launch, a work activation, or an explicit reset may
                    // start a session from idle.
                    let allowed: Bool
                    switch event {
                    case .launch, .resetSession:
                        allowed = true
                    case .appActivated(let bundleID, _):
                        allowed = engine.categories.category(for: bundleID) == .work
                    default:
                        allowed = false
                    }
                    if !allowed {
                        problems.append("\(label) + \(event): unexpected exit from idle")
                    }
                }
            }
        }
        return problems
    }
}
