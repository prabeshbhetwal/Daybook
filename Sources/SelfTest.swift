import Foundation
import SwiftUI
import Combine
import AppKit

/// Headless logic tests (§7). Pure state-machine and time arithmetic with an
/// injected clock — no UI, no notifications, no run loop.
enum SelfTest {

    private final class Clock {
        var value: Date
        init(_ start: Date) { value = start }
        func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
    }

    private final class MutableDate {
        var value: Date
        init(_ value: Date) { self.value = value }
    }

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let suiteName = "com.prabesh.focuscontinuity.selftest"
    private static var scratchDirectories: [URL] = []

    private struct UsageEnvelopeFixture: Codable {
        let metadata: AppUsageMetadata
        let sessions: [AppUsageSession]
    }

    /// A scratch directory per archive so tests never touch real history.
    private static func scratchDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-selftest-\(UUID().uuidString)", isDirectory: true)
        scratchDirectories.append(directory)
        return directory
    }

    private static func makeArchive(_ clock: Clock) -> SessionArchive {
        SessionArchive(directory: scratchDirectory(), now: { clock.value })
    }

    private static func makeArchive(_ clock: Clock,
                                    records: [SessionRecord],
                                    calendar: Calendar = .current) -> SessionArchive {
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: directory.appendingPathComponent("sessions.json"),
                            options: .atomic)
        }
        return SessionArchive(directory: directory, calendar: calendar,
                              now: { clock.value })
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

    private static func makeUsageArchive(_ clock: Clock,
                                         sessions: [AppUsageSession],
                                         accurateFrom: Date? = nil) -> AppUsageArchive {
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let envelope = UsageEnvelopeFixture(
            metadata: AppUsageMetadata(accurateFrom: accurateFrom ?? clock.value),
            sessions: sessions)
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: directory.appendingPathComponent("app-usage.json"),
                            options: .atomic)
        }
        return AppUsageArchive(directory: directory, now: { clock.value })
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

    /// An anchor that is safely inside its own week and month: fixtures that
    /// seed "today, yesterday, two days ago" and then roll them up by week or
    /// month must not straddle a boundary. On a Monday the plain anchor put
    /// yesterday in the previous week, which emptied the week's chart and made
    /// the anchor day the first day of its own period.
    private static func periodAnchor(calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
        for _ in 0..<40 {
            let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            let daysIntoWeek = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            let dayOfMonth = calendar.component(.day, from: day)
            if daysIntoWeek >= 2, dayOfMonth >= 10 { return day }
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return day
    }

    private static func cleanUp() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories.removeAll()
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
            ("Self-test scratch directories are removed during cleanup", testScratchDirectoryCleanup),
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
            ("Usage waiting state stays live and clears terminally", testUsageWaitingStateLifecycle),
            ("Wake HID resets require confirmed human presence", testWakePresenceGate),
            ("A wake candidate records only after confirmed presence", testWakeDoesNotCreateUsage),
            ("An aged HID reset still resolves the engine absence", testAgedWakeResetEndsAbsence),
            ("App activation updates a waiting usage candidate", testWaitingActivationUpdatesCandidate),
            ("Wake activation defers engine work and automation until presence",
             testWakeActivationDefersEngineAndAutomation),
            ("An unprepared wake activation remains non-recording",
             testUnpreparedWakeActivationRemainsGated),
            ("Launch never seeds usage behind a lock or sleeping display",
             testLaunchUsageSeedRequiresVisiblePresence),
            ("Usage tracker lifecycle callbacks publish only final states",
             testUsageTrackerLifecycleCallbacks),
            ("Legacy app usage migration preserves history", testLegacyUsageMigrationPreservesHistory),
            ("Usage checkpoints replace records by identity", testUsageCheckpointReplacesByIdentity),
            ("Clock regression cannot shorten durable usage without idle evidence",
             testUsageClockRegressionSafety),
            ("Usage mutations publish only after durable filesystem writes",
             testUsageWriteFailureRollsBack),
            ("Failed terminal usage checkpoints retain their original boundary",
             testFailedTerminalCheckpointRetainsOriginalBoundary),
            ("Confirmed queued usage survives later lifecycle events",
             testConfirmedPendingUsageSurvivesLaterLifecycleEvents),
            ("Queued usage intervals reconcile tracked and focused-active totals",
             testQueuedUsageIntervalsFeedFocusedActiveTotals),
            ("Pending usage retries even without a minute of additive tail",
             testPendingUsageRetriesWithoutTailThreshold),
            ("Pending usage overlays durable UUIDs across every consumer",
             testAuthoritativePendingUsageOverlay),
            ("Failed usage preservation keeps source evidence read-only",
             testUsagePreservationFailureFailsClosed),
            ("Future usage schema stays byte-identical and read-only",
             testFutureUsageSchemaIsReadOnly),
            ("Integrity usage query filters system processes and respects bounds",
             testIntegrityUsageQuery),
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
            ("Period chart bars use tracked time, not focus composition",
             testPeriodChartUsesTrackedTime),
            ("Dashboard day slices invalidate on archive revision",
             testDashboardDaySliceInvalidatesOnRevision),
            ("Dashboard refreshes archive changes only while visible",
             testDashboardArchiveVisibility),
            ("A checkpoint callback coalesces into one full dashboard rebuild",
             testDashboardRefreshCoalescesCheckpointCallback),
            ("Pre-accuracy usage is qualified on the selected day",
             testSelectedDayIntegrityNote),
            ("Week and Month qualify legacy usage anywhere in their range",
             testPeriodIntegrityNoteCoversCompleteRange),
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
            ("Daily goal: historical pace uses focused-active time", testHistoricalPaceUsesFocusedActiveTime),
            ("Daily goal: active days remain samples after the cutoff", testHistoricalPaceKeepsZeroCutoffSamples),
            ("Daily goal: historical cutoffs match local DST clock time", testHistoricalPaceDSTCutoffs),
            ("Daily goal: live usage advances and clips at local midnight",
             testLiveUsageFeedsGoalAndClipsMidnight),
            ("Daily goal: cached historical pace refreshes each local minute",
             testHistoricalPaceRefreshesOnMinuteBoundary),
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
            ("Historical goal status uses focused-active time",
             testHistoricalGoalStatusUsesFocusedActiveTime),
            ("Palette: seven distinct app colours, both appearances, total work types",
             testPalette),
            ("Menu-bar glyph renders a template ring for every state", testMenuBarGlyph),
            ("Settings model writes through and notifies once per change", testSettingsModel),
            ("Reveal data folder creates pristine storage and reports failures",
             testRevealDataFolderWorkflow),
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
            ("Day digest and focus metrics stay clipped to the selected day",
             testDayDigestAndFocusAreDayScoped),
            ("Live focus quality clips running work at midnight",
             testLiveFocusQualityClipsAtMidnight),
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
             testWakeIsNotAReturn),
            ("Main navigation and interface preferences persist across reload",
             testMainNavigationAndInterfacePreferences),
            ("System appearance clears an explicit application override",
             testSystemAppearanceClearsApplicationOverride),
            ("Warm-precision design tokens preserve practical density and semantic signals",
             testWarmPrecisionDesignTokensAndDensity),
            ("Main-window deep links and commands select their exact routes",
             testMainWindowRoutesAndCommands),
            ("Unified window chrome keeps context beside tabs without a native focus ring",
             testUnifiedWindowChrome),
            ("Native chrome uses individual tabs and a compact app mark",
             testNativeChromePresentation),
            ("Today preserves day scope and clears only its inspector selection",
             testTodaySurfaceScopeAndInspector),
            ("Review keeps tracked bars canonical and History filters by intersection",
             testReviewHistoryFiltersAndDayRouting),
            ("A selected Review day derives canonical, day-scoped detail",
             testReviewSelectedDayDetail),
            ("Period charts reserve a whole calendar day at each edge",
             testPeriodChartLayout),
            ("History states its range once and its columns in a header",
             testHistoryRangeAndTableAnatomy),
            ("History disclosures keep their selected row visually joined",
             testHistoryDisclosurePresentation),
            ("Review reads period answer, trend, selected day, then evidence",
             testReviewContentHierarchy),
            ("Today qualifies before it charts; Focus stays an instrument",
             testDayAndFocusHierarchy),
            ("Insights lead with the finding; Settings keeps a native measure",
             testInsightAndSettingsPresentation),
            ("Awards are earned from the record, never invented",
             testAwardsAreEvidenceBacked),
            ("Insights render statements only when canonical evidence exists",
             testInsightSurfaceRequiresEvidence),
            ("Insights rhythm and active days exclude pre-accuracy usage",
             testInsightsExcludePreAccuracyUsage),
            ("Insights quality deduplicates resumed threads across its full range",
             testInsightQualityDeduplicatesThreadsAcrossRange),
            ("Tracker checkpoints refresh visible and next-open Insights",
             testTrackerTransitionsInvalidateInsights),
            ("Insights preserve tiny positive quality facts without zero labels",
             testInsightQualityPreservesTinyPositiveEvidence),
            ("Period logs retain the newest 500 sessions consistently",
             testPeriodLogRetainsNewestLimit),
            ("Selected Review days retain app evidence beyond the period-log cap",
             testReviewDetailRetainsUncappedDayEntries),
            ("Review keeps focus-only periods out of the empty state",
             testReviewFocusOnlyPeriodEvidence),
            ("Dense focus Review shows the newest 500 rows without capping evidence",
             testReviewFocusRowsAreBoundedAndQualified),
            ("History query matches the displayed app name",
             testHistorySearchesDisplayedAppName),
            ("History bounds malformed spans but keeps ordinary midnight clipping",
             testHistoryBoundsMalformedSpans),
            ("History discloses legacy accuracy and span-bound derived omissions",
             testHistoryDisclosesLegacyAndDroppedSpans),
            ("Review longest focus clips period boundaries and excludes breaks",
             testReviewLongestFocusClipsBoundsAndExcludesBreaks),
            ("Timeline rests stay clipped inside otherwise unknown gaps",
             testTimelineRestEvidenceStaysCanonical),
            ("Focus states keep one honest action and continuations stop at three",
             testFocusSurfaceStateAndContinuationLimit),
            ("Focus composition guards decisions and keeps automatic corrections available",
             testFocusSurfaceCompositionGuards),
            ("Unresolved Away decisions reject ordinary session mutations",
             testAwayDecisionRejectsOrdinarySessionMutations),
            ("The global hotkey routes unresolved Away evidence to its decision surface",
             testHotKeyRoutesPendingAwayDecision),
            ("Sessions per app limits the real Today app-session list",
             testSessionsPerAppLimitsProductionAppHistory),
            ("Focus quality counts threads and real app transitions",
             testFocusQualityCountsThreadsAndTransitions),
            ("Declared-Away automatic corrections resume tracking exactly once",
             testDeclaredAwayAutomaticCorrectionRoutes),
            ("Settings groups contain only backed controls",
             testSettingsGroupsContainOnlyBackedControls),
            ("The window opens on the story the preference names",
             testWindowOpensOnPreferredStory),
            ("Narrative diagnostics use a full-width status layout",
             testSettingsDiagnosticLayout),
            ("Settings privacy distinguishes monitoring from entered session data",
             testSettingsPrivacyDisclosure),
            ("Shared panels consume the interface density environment",
             testSharedPanelDensityEnvironment),
            ("Settings narrow navigation is reachable at the production minimum width",
             testSettingsProductionBreakpoint),
            ("Settings accuracy epoch always includes its year",
             testSettingsAccuracyEpochYear),
            ("Compact Focus snapshots retain the title and status band",
             testCompactFocusSnapshotStructure),
            ("Accessible navigation and charts expose literal selected-state evidence",
             testAccessibleNavigationAndChartSummaries),
            ("History date controls provide real 28 point hit targets",
             testHistoryDateControlsMeetTarget),
            ("Expanded app rows retain daily accessibility and keyboard actions",
             testPeriodAppRowsExposeDailyAccessibility),
            ("Today session selection and disclosure are independent accessible controls",
             testTodaySessionRowControlsAreIndependent),
            ("Snapshot matrix covers every material surface",
             testSnapshotMatrixCoversEveryMaterialSurface),
            ("Simultaneous snapshots keep isolated presentation preferences",
             testSimultaneousSnapshotsKeepIsolatedPreferences),
            ("Away snapshots retain production prompt chrome",
             testAwaySnapshotsRetainProductionPromptChrome)
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

    /// WCAG 2.x contrast from literal sRGB values. Test-only and independent
    /// of the production colour provider under test.
    private static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let component = Double((hex >> UInt32(shift)) & 0xFF) / 255
                return component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let values = [luminance(first), luminance(second)]
        return ((values.max() ?? 0) + 0.05) / ((values.min() ?? 0) + 0.05)
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
        let ring = SessionArchive(directory: dir, now: { clock.value }, capacity: 3)
        let overflow = 5
        for index in 0..<overflow {
            ring.append(SessionRecord(name: "s\(index)", workType: .deepWork,
                                      start: base, end: base.addingTimeInterval(60),
                                      workSeconds: Double(index)))
        }
        expect(ring.records.count == 3,
               "ring should cap at 3, got \(ring.records.count)",
               &problems)
        expect(ring.records.map(\.name) == ["s2", "s3", "s4"],
               "ring should retain the newest entries in order, got \(ring.records.map(\.name))",
               &problems)
        expect(ring.sessionsToday() == 3,
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

    private static func testScratchDirectoryCleanup() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        expect(FileManager.default.fileExists(atPath: directory.path),
               "scratch directory should exist before cleanup", &problems)
        cleanUp()
        expect(!FileManager.default.fileExists(atPath: directory.path),
               "cleanup should remove every tracked scratch directory", &problems)
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

    /// Waiting is an observation state, not a stopped tracker: the ticker must
    /// keep sampling until real presence is known. Suspension and disabling are
    /// terminal for that candidate, so an old confirmation cannot reopen it.
    private static func testUsageWaitingStateLifecycle() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let tracker = AppUsageTracker(archive: AppUsageArchive(directory: directory,
                                                                 now: { clock.value }),
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled, now: { clock.value })

        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        expect(tracker.isObserving,
               "waiting for presence must keep the ticker observing", &problems)
        tracker.suspend()
        expect(!tracker.isObserving,
               "suspending a waiting tracker must stop observation", &problems)
        tracker.confirmPresence(at: clock.value)
        expect(tracker.currentBundleID == nil && !tracker.isObserving,
               "a stale confirmation after suspend must not reopen tracking", &problems)

        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        expect(tracker.isObserving,
               "a second waiting candidate must also keep the ticker alive", &problems)
        tracker.setEnabled(false)
        expect(!tracker.isObserving,
               "disabling a waiting tracker must stop observation", &problems)
        tracker.setEnabled(true)
        tracker.confirmPresence(at: clock.value)
        expect(tracker.currentBundleID == nil && !tracker.isObserving,
               "a stale confirmation after disable must not reopen tracking", &problems)
        return problems
    }

    /// A wake resets macOS's HID idle counter even when nobody touched the
    /// machine. The reset itself and its increasing tail must stay quiet; only
    /// an unlock or a second, downward reset is evidence of a person.
    private static func testWakePresenceGate() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        var gate = PresenceGate()
        gate.confirm(at: clock.value)

        clock.advance(600)
        gate.noteMachineWake()
        for raw in [0.5, 1.5, 2.5] {
            let observation = gate.observe(rawIdleSeconds: raw,
                                           at: clock.value,
                                           displayAwake: true,
                                           screenLocked: false)
            if case .quiet(let seconds) = observation {
                expect(seconds >= 600,
                       "an increasing post-wake counter stays quiet, got \(seconds)s",
                       &problems)
            } else {
                problems.append("an increasing post-wake counter must not confirm presence")
            }
            clock.advance(1)
        }

        let resetAt = clock.value
        let reset = gate.observe(rawIdleSeconds: 0.25,
                                 at: resetAt,
                                 displayAwake: true,
                                 screenLocked: false)
        if case .active(let since) = reset {
            expectClose(since.timeIntervalSince(resetAt), -0.25,
                        "a downward reset confirms from the last input", &problems)
        } else {
            problems.append("a later downward reset should confirm presence")
        }

        var unlockGate = PresenceGate()
        unlockGate.noteMachineWake()
        clock.advance(60)
        let unlockedAt = clock.value
        unlockGate.confirm(at: unlockedAt)
        clock.advance(1)
        let afterUnlock = unlockGate.observe(rawIdleSeconds: 1,
                                             at: clock.value,
                                             displayAwake: true,
                                             screenLocked: false)
        if case .active(let since) = afterUnlock {
            expectClose(since.timeIntervalSince(unlockedAt), 0,
                        "unlock confirms presence immediately", &problems)
        } else {
            problems.append("an explicit unlock should clear wake suppression")
        }
        return problems
    }

    /// Preparing the frontmost app after wake is deliberately non-recording.
    /// The first real HID reset confirms the candidate and starts a new UUID at
    /// that confirmed return, never at the machine wake.
    private static func testWakeDoesNotCreateUsage() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })
        var gate = PresenceGate()

        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        gate.noteMachineWake()
        for raw in [0.25, 1.25, 2.25] {
            clock.advance(1)
            if case .quiet(let seconds) = gate.observe(rawIdleSeconds: raw,
                                                       at: clock.value,
                                                       displayAwake: true,
                                                       screenLocked: false) {
                tracker.observeIdle(seconds: seconds)
            } else {
                problems.append("machine-wake idle must remain non-recording")
            }
        }
        tracker.flush()
        expect(usage.sessions.isEmpty && tracker.currentBundleID == nil,
               "a prepared wake candidate must record nothing before confirmation",
               &problems)

        clock.advance(1)
        let confirmedAt = clock.value.addingTimeInterval(-0.1)
        let presence = gate.observe(rawIdleSeconds: 0.1,
                                    at: clock.value,
                                    displayAwake: true,
                                    screenLocked: false)
        if case .active(let since) = presence {
            tracker.confirmPresence(at: since)
            expectClose(since.timeIntervalSince(confirmedAt), 0,
                        "the return is the genuine idle reset", &problems)
        } else {
            problems.append("genuine post-wake input should confirm the candidate")
        }
        clock.advance(60)
        tracker.flush()

        expect(usage.sessions.count == 1,
               "confirmation starts exactly one app-usage UUID", &problems)
        expectClose(usage.sessions.first?.start.timeIntervalSince(confirmedAt) ?? -1, 0,
                    "usage starts at confirmed presence", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 60.1,
                    "only post-confirmation usage is recorded", &problems)
        return problems
    }

    /// A real input reset can already be several seconds old by the next tick.
    /// `.active` is categorical proof of return, so its age must not be sent to
    /// the engine as if it were still merely quiet.
    private static func testAgedWakeResetEndsAbsence() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine)
        store.attach(tracker: tracker, usage: usage)
        var gate = PresenceGate()

        engine.transition(on: .launch)
        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        gate.confirm(at: clock.value)
        clock.advance(60)
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        gate.noteMachineWake()

        clock.advance(20)
        let wakeReset = gate.observe(rawIdleSeconds: 20,
                                     at: clock.value,
                                     displayAwake: true,
                                     screenLocked: false)
        engine.transition(on: .idleObserved(
            seconds: store.applyPresenceObservation(wakeReset)))
        expectClose(engine.totalPausedDuration, 0,
                    "the machine reset alone must leave the absence open", &problems)

        clock.advance(10)
        let humanReset = gate.observe(rawIdleSeconds: 10,
                                      at: clock.value,
                                      displayAwake: true,
                                      screenLocked: false)
        if case .active(let since) = humanReset {
            expectClose(since.timeIntervalSince(clock.value), -10,
                        "the confirmed return retains its honest input date", &problems)
        } else {
            problems.append("the aged downward reset should be confirmed active")
        }
        engine.transition(on: .idleObserved(
            seconds: store.applyPresenceObservation(humanReset)))
        expectClose(engine.totalPausedDuration, 30,
                    "confirmed active must resolve the full engine absence", &problems)
        expect(tracker.currentBundleID == "com.example.editor",
               "the same confirmation must activate the waiting tracker", &problems)
        tracker.flush()
        expectClose(usage.sessions.first?.start.timeIntervalSince(clock.value) ?? -1, -10,
                    "the tracker retains the gate's aged input date", &problems)
        return problems
    }

    /// App notifications can arrive between wake and the confirming HID reset.
    /// They update which app is waiting, but the notification itself is not
    /// permission to record; ordinary stopped activation remains immediate.
    private static func testWaitingActivationUpdatesCandidate() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })

        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        clock.advance(10)
        tracker.appActivated(bundleID: "com.example.browser", name: "Browser")
        clock.advance(30)
        tracker.flush()
        expect(tracker.currentBundleID == nil && tracker.isObserving,
               "activation while waiting must remain non-recording", &problems)
        expect(usage.sessions.isEmpty,
               "a waiting activation must not create an app-usage record", &problems)

        let confirmedAt = clock.value
        tracker.confirmPresence(at: confirmedAt)
        expect(tracker.currentBundleID == "com.example.browser",
               "confirmation starts the updated candidate app", &problems)
        clock.advance(60)
        tracker.flush()
        expect(usage.sessions.count == 1
                   && usage.sessions.first?.bundleID == "com.example.browser"
                   && usage.sessions.first?.appName == "Browser",
               "only the updated candidate is recorded after confirmation", &problems)
        expectClose(usage.sessions.first?.start.timeIntervalSince(confirmedAt) ?? -1, 0,
                    "the updated candidate starts at confirmation", &problems)

        let ordinaryDirectory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: ordinaryDirectory) }
        let ordinary = AppUsageTracker(
            archive: AppUsageArchive(directory: ordinaryDirectory, now: { clock.value }),
            ownBundleID: FocusConstants.bundleIdentifier,
            idle: .disabled,
            now: { clock.value })
        ordinary.appActivated(bundleID: "com.example.terminal", name: "Terminal")
        expect(ordinary.currentBundleID == "com.example.terminal",
               "ordinary stopped activation must still begin immediately", &problems)
        return problems
    }

    /// A workspace activation can be generated by the machine while a display
    /// wakes. Until presence is confirmed it may update only the pending app;
    /// otherwise an idle engine starts work, a paused one resumes, and the auto
    /// detector evaluates evidence nobody produced.
    private static func testWakeActivationDefersEngineAndAutomation() -> [String] {
        var problems: [String] = []

        func makeContext() -> (Clock, SessionEngine, SessionStore, AppUsageTracker) {
            let clock = Clock(base)
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let engine = SessionEngine(
                store: persistence,
                archive: SessionArchive(directory: directory, now: { clock.value }),
                ownBundleID: "com.example.self", schedulesDwell: false,
                now: { clock.value })
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine)
            store.attach(tracker: tracker, usage: usage)
            return (clock, engine, store, tracker)
        }

        do {
            let (clock, engine, store, tracker) = makeContext()
            var automationRuns = 0
            store.onDeferredAutomationReady = { automationRuns += 1 }
            store.noteMachineWake()
            tracker.prepareToResume(bundleID: "com.apple.dt.Xcode", name: "Xcode")

            let firstDelivered = store.handleApplicationActivation(
                bundleID: "com.apple.dt.Xcode", name: "Xcode")
            let latestDelivered = store.handleApplicationActivation(
                bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")
            store.prepareTrackingResume(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            expect(!firstDelivered && !latestDelivered,
                   "wake-suppressed activations must report themselves deferred", &problems)
            expect(engine.state == .idle && engine.currentAppBundleID == nil,
                   "a machine activation must not start an idle engine", &problems)
            expect(tracker.currentBundleID == nil && automationRuns == 0,
                   "neither usage nor automation may start before presence", &problems)

            store.confirmPresence(at: clock.value)
            expect(engine.state == .running
                       && engine.currentAppBundleID == "com.apple.dt.Xcode",
                   "confirmation delivers the latest prepared frontmost activation", &problems)
            expect(tracker.currentBundleID == "com.apple.dt.Xcode",
                   "the tracker confirms the same latest prepared app", &problems)
            expect(automationRuns == 1,
                   "deferred automation runs exactly once after confirmation", &problems)
            store.confirmPresence(at: clock.value)
            expect(automationRuns == 1,
                   "repeated confirmation cannot replay deferred automation", &problems)
        }

        do {
            let (clock, engine, store, tracker) = makeContext()
            engine.start(workType: .deepWork, intent: "Manual")
            engine.transition(on: .manualPause)
            store.noteMachineWake()
            tracker.prepareToResume(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            let delivered = store.handleApplicationActivation(
                bundleID: "com.apple.dt.Xcode", name: "Xcode")
            expect(!delivered && engine.state == .paused(reason: .manual),
                   "a wake activation must not resume a deliberate pause", &problems)
            store.confirmPresence(at: clock.value)
            expect(engine.state == .running,
                   "the deferred work activation resumes only after presence", &problems)
        }

        do {
            let (clock, engine, store, tracker) = makeContext()
            engine.restore(from: PersistedState(
                state: .running, name: "Automatic", sessionStart: clock.value,
                totalPaused: 0, pauseStart: nil, away: nil, lastApp: "—",
                lastAppBundleID: nil, decisionStarted: nil, savedAt: clock.value,
                threadID: UUID(), isAuto: true))
            var automationRuns = 0
            store.onDeferredAutomationReady = { automationRuns += 1 }
            store.noteMachineWake()
            tracker.prepareToResume(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            _ = store.handleApplicationActivation(bundleID: "com.apple.dt.Xcode",
                                                  name: "Xcode")
            expect(engine.currentAppBundleID == nil && engine.activeIsAuto,
                   "a running automatic session receives no machine activation", &problems)
            expect(automationRuns == 0,
                   "the automatic detector remains gated while presence is unknown", &problems)
            store.confirmPresence(at: clock.value)
            expect(engine.currentAppBundleID == "com.apple.dt.Xcode" && engine.activeIsAuto,
                   "confirmation delivers the activation without changing auto ownership",
                   &problems)
            expect(automationRuns == 1,
                   "the automatic path evaluates once after genuine presence", &problems)
        }

        return problems
    }

    /// Wake preparation can legitimately find no ordinary frontmost app. A
    /// later workspace activation is still machine evidence, not permission for
    /// a stopped tracker to begin before the shared presence gate confirms it.
    private static func testUnpreparedWakeActivationRemainsGated() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let engine = makeEngine(clock)
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)

        store.noteMachineWake()
        let delivered = store.handleApplicationActivation(
            bundleID: "com.example.editor", name: "Editor")
        clock.advance(60)
        tracker.flush()

        expect(!delivered && tracker.currentBundleID == nil,
               "an unprepared wake activation must remain a waiting candidate", &problems)
        expect(usage.sessions.isEmpty,
               "an unprepared wake activation records nothing before presence", &problems)

        let confirmedAt = clock.value
        store.confirmPresence(at: confirmedAt)
        clock.advance(60)
        tracker.flush()
        expectClose(usage.sessions.first?.start.timeIntervalSince(confirmedAt) ?? -1, 0,
                    "usage begins at confirmed presence rather than machine activation", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 60,
                    "only post-confirmation usage is retained", &problems)
        return problems
    }

    /// Initial frontmost-app seeding is permitted only when the display can
    /// actually be in front of a person. An unlocked but sleeping display is as
    /// absent as a locked one and must wait for later presence evidence.
    private static func testLaunchUsageSeedRequiresVisiblePresence() -> [String] {
        var problems: [String] = []
        let cases: [(locked: Bool, asleep: Bool, expected: Bool, label: String)] = [
            (false, false, true, "unlocked and awake"),
            (true, false, false, "locked and awake"),
            (false, true, false, "unlocked and asleep"),
            (true, true, false, "locked and asleep")
        ]
        for item in cases {
            let actual = AppCoordinator.permitsInitialUsageSeed(
                screenLocked: item.locked, displayAsleep: item.asleep)
            expect(actual == item.expected,
                   "launch seed policy for \(item.label) expected \(item.expected), got \(actual)",
                   &problems)
        }
        return problems
    }

    /// The callback is a lifecycle boundary, not an early mutation notice. A
    /// same-app confirmation must publish active, and suspend must publish
    /// stopped only after its checkpoint has settled.
    private static func testUsageTrackerLifecycleCallbacks() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        var states: [(bundleID: String?, observing: Bool)] = []
        tracker.onDidTransition = {
            states.append((tracker.currentBundleID, tracker.isObserving))
        }

        tracker.prepareToResume(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        tracker.confirmPresence(at: clock.value)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(10 * 60)
        tracker.suspend()

        expect(states.count == 3,
               "waiting, confirmed active and suspended each publish once; got \(states.count)",
               &problems)
        if states.count == 3 {
            expect(states[0].bundleID == nil && states[0].observing,
                   "the waiting callback sees the final waiting state", &problems)
            expect(states[1].bundleID == "com.apple.dt.Xcode" && states[1].observing,
                   "same-app confirmation callback sees the final active state", &problems)
            expect(states[2].bundleID == nil && !states[2].observing,
                   "suspend callback sees the final stopped state", &problems)
        }
        expect(usage.sessions.count == 1,
               "suspend still commits the completed usage stretch", &problems)

        weak var releasedUsage: AppUsageArchive?
        weak var releasedTracker: AppUsageTracker?
        do {
            let lifecycleClock = Clock(base)
            let lifecycleDirectory = scratchDirectory()
            let lifecycleUsage = AppUsageArchive(directory: lifecycleDirectory,
                                                 now: { lifecycleClock.value })
            let lifecycleTracker = AppUsageTracker(
                archive: lifecycleUsage, ownBundleID: "com.example.self",
                idle: .disabled, now: { lifecycleClock.value })
            let lifecycleStore = SessionStore(engine: makeEngine(lifecycleClock))
            lifecycleStore.attach(tracker: lifecycleTracker, usage: lifecycleUsage)
            releasedUsage = lifecycleUsage
            releasedTracker = lifecycleTracker
        }
        expect(releasedUsage == nil && releasedTracker == nil,
               "store attachment must not retain a usage archive/tracker cycle", &problems)
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

        let appended = AppUsageSession(bundleID: "com.example.browser", appName: "Browser",
                                       start: base.addingTimeInterval(180),
                                       end: base.addingTimeInterval(240))
        expect(archive.record(appended), "a real segment is recorded", &problems)
        expect(archive.revision == 4 && notifications == 4,
               "recording a segment must revise and notify once", &problems)
        let rejected = AppUsageSession(bundleID: "com.example.short", appName: "Short",
                                       start: base.addingTimeInterval(300),
                                       end: base.addingTimeInterval(304))
        expect(!archive.record(rejected), "a sub-floor segment is rejected", &problems)
        expect(archive.revision == 4 && notifications == 4,
               "rejecting a segment must not revise or notify", &problems)

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

    /// A manual clock correction is not evidence that already-recorded work did
    /// not happen. Ordinary flushes and closes retain the last durable boundary;
    /// an explicit idle observation may still correct it backwards.
    private static func testUsageClockRegressionSafety() -> [String] {
        var problems: [String] = []

        do {
            let clock = Clock(base)
            let directory = scratchDirectory()
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            clock.advance(10 * 60)
            tracker.flush()
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "the initial checkpoint is durable", &problems)

            clock.value = base.addingTimeInterval(5 * 60)
            tracker.flush()
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "a non-idle flush cannot move before its durable end", &problems)
            clock.value = base.addingTimeInterval(4 * 60)
            tracker.suspend()
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "a non-idle finalisation cannot shorten durable usage", &problems)
            expect(!tracker.isObserving,
                   "a successful clamped finalisation still stops tracking", &problems)
        }

        do {
            let clock = Clock(base)
            let directory = scratchDirectory()
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(100)
            tracker.observeIdle(seconds: 400)
            expectClose(usage.sessions.first?.seconds ?? -1, 5 * 60,
                        "explicit idle evidence may roll a checkpoint backwards", &problems)
            expect(tracker.currentBundleID == nil && tracker.isObserving,
                   "idle correction settles in waiting-for-presence", &problems)
        }

        return problems
    }

    /// Atomic persistence is the commit point. A failed write leaves cache,
    /// revision, callbacks and the tracker's durable boundary untouched so the
    /// exact same stretch can be retried after storage becomes writable.
    private static func testUsageWriteFailureRollsBack() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let root = scratchDirectory()
        try? FileManager.default.createDirectory(at: root,
                                                 withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("blocked-storage")
        try? Data("not a directory".utf8).write(to: blocked)
        let usage = AppUsageArchive(directory: blocked, now: { clock.value })
        var callbacks = 0
        usage.onDidChange = { callbacks += 1 }
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(10 * 60)
        tracker.flush()

        expect(usage.sessions.isEmpty,
               "a failed write rolls back the in-memory checkpoint", &problems)
        expect(usage.revision == 0 && callbacks == 0,
               "failed persistence publishes neither revision nor callback", &problems)
        expectClose(tracker.unpersistedSeconds(), 10 * 60,
                    "the failed checkpoint remains wholly retryable", &problems)

        try? FileManager.default.removeItem(at: blocked)
        try? FileManager.default.createDirectory(at: blocked,
                                                 withIntermediateDirectories: true)
        tracker.flush()
        expect(usage.sessions.count == 1 && usage.revision == 1 && callbacks == 1,
               "the repaired filesystem accepts and publishes one retry", &problems)
        expectClose(tracker.unpersistedSeconds(), 0,
                    "only the successful retry advances the durable boundary", &problems)
        let reloaded = AppUsageArchive(directory: blocked, now: { clock.value })
        expectClose(reloaded.sessions.first?.seconds ?? -1, 10 * 60,
                    "the successful retry exists on disk", &problems)

        clock.advance(60)
        let savedDirectory = root.appendingPathComponent("saved-storage")
        try? FileManager.default.moveItem(at: blocked, to: savedDirectory)
        try? Data("blocked again".utf8).write(to: blocked)
        tracker.suspend()
        expect(tracker.currentBundleID == nil && tracker.isObserving,
               "a failed terminal checkpoint freezes closed while remaining retryable", &problems)
        expectClose(tracker.unpersistedSeconds(), 60,
                    "a failed terminal checkpoint exposes only its frozen tail", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                    "failed finalisation rolls the cache back to its durable record", &problems)
        expect(usage.revision == 1 && callbacks == 1,
               "failed finalisation remains unpublished", &problems)

        try? FileManager.default.removeItem(at: blocked)
        try? FileManager.default.moveItem(at: savedDirectory, to: blocked)
        tracker.suspend()
        expect(!tracker.isObserving && usage.revision == 2 && callbacks == 2,
               "repair lets the identical finalisation persist and stop", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 11 * 60,
                    "the retried close retains the whole active stretch", &problems)
        return problems
    }

    /// A failed terminal checkpoint is an immutable event, not permission to
    /// keep accruing until storage recovers. Its unsaved tail stays visible,
    /// while a confirmed return waits behind that exact close as a new UUID.
    private static func testFailedTerminalCheckpointRetainsOriginalBoundary() -> [String] {
        var problems: [String] = []

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            let originalID = usage.sessions.first?.id

            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 11 * 60,
                        "the failed close tail remains visible without accruing", &problems)

            clock.advance(20 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()

            expect(usage.sessions.first?.id == originalID,
                   "a delayed retry must retain the original usage UUID", &problems)
            expectClose(usage.sessions.first?.seconds ?? -1, 11 * 60,
                        "a delayed retry must retain the original suspend boundary", &problems)
            expect(usage.sessions.first?.endReason == .systemLock,
                   "the delayed retry must retain the original terminal reason", &problems)
        }

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            let originalID = usage.sessions.first?.id

            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            clock.advance(4 * 60)
            let confirmedReturn = base.addingTimeInterval(15 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: confirmedReturn)

            clock.advance(20 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()
            tracker.flush()

            let oldSession = usage.sessions.first { $0.id == originalID }
            let returnedSession = usage.sessions.first { $0.id != originalID }
            expectClose(oldSession?.seconds ?? -1, 11 * 60,
                        "a queued return must not extend the failed close", &problems)
            expect(oldSession?.endReason == .systemLock,
                   "a queued return must not replace the failed close reason", &problems)
            expect(returnedSession?.bundleID == "com.example.browser",
                   "the queued return must retain its candidate app", &problems)
            expectClose(returnedSession?.start.timeIntervalSince(base) ?? -1, 15 * 60,
                        "the new UUID must begin at the confirmed return", &problems)
        }

        return problems
    }

    /// Once presence confirms a queued app, its UUID and start are facts. A
    /// later app switch or suspension may close that interval, but cannot
    /// replace, rebase or discard it while an earlier close is still unwritable.
    private static func testConfirmedPendingUsageSurvivesLaterLifecycleEvents() -> [String] {
        var problems: [String] = []

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            clock.advance(4 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: base.addingTimeInterval(15 * 60))
            clock.advance(5 * 60)
            let confirmedBrowserID = tracker.unpersistedSession()?.id
            tracker.appActivated(bundleID: "com.example.xcode", name: "Xcode")

            expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 16 * 60,
                        "a later activation must retain confirmed Browser usage", &problems)

            clock.advance(5 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()
            tracker.flush()

            let editor = usage.sessions.first { $0.bundleID == "com.example.editor" }
            let browser = usage.sessions.first { $0.bundleID == "com.example.browser" }
            let xcode = usage.sessions.first { $0.bundleID == "com.example.xcode" }
            expectClose(editor?.seconds ?? -1, 11 * 60,
                        "the earlier failed close remains frozen through a later switch", &problems)
            expect(editor?.endReason == .systemLock,
                   "the earlier failed close retains its terminal reason after a later switch",
                   &problems)
            expectClose(browser?.start.timeIntervalSince(base) ?? -1, 15 * 60,
                        "Browser retains the confirmed start before a later switch", &problems)
            expectClose(browser?.seconds ?? -1, 5 * 60,
                        "Browser closes at the intervening activation", &problems)
            expect(browser?.id == confirmedBrowserID,
                   "Browser retains the UUID created by confirmed presence", &problems)
            expect(browser?.endReason == .appSwitch,
                   "the intervening activation closes Browser as an app switch", &problems)
            expectClose(xcode?.start.timeIntervalSince(base) ?? -1, 20 * 60,
                        "Xcode starts at its own activation without rebasing Browser", &problems)
            expect(Set(usage.sessions.map(\.id)).count == 3,
                   "each preserved interval must retain a distinct UUID", &problems)
        }

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            clock.advance(4 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: base.addingTimeInterval(15 * 60))
            clock.advance(5 * 60)
            let confirmedBrowserID = tracker.unpersistedSession()?.id
            tracker.suspend()

            expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 16 * 60,
                        "suspension must retain confirmed Browser usage", &problems)

            clock.advance(5 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()

            let editor = usage.sessions.first { $0.bundleID == "com.example.editor" }
            let browser = usage.sessions.first { $0.bundleID == "com.example.browser" }
            expectClose(editor?.seconds ?? -1, 11 * 60,
                        "terminal queuing must not move the earlier failed close", &problems)
            expectClose(browser?.start.timeIntervalSince(base) ?? -1, 15 * 60,
                        "terminal queuing retains Browser's confirmed start", &problems)
            expectClose(browser?.seconds ?? -1, 5 * 60,
                        "suspension closes the confirmed Browser interval", &problems)
            expect(browser?.id == confirmedBrowserID,
                   "suspension retains the confirmed Browser UUID", &problems)
            expect(browser?.endReason == .systemLock,
                   "suspension retains Browser's terminal reason", &problems)
            expect(Set(usage.sessions.map(\.id)).count == 2,
                   "terminal queuing preserves both stable UUIDs", &problems)
            expect(!tracker.isObserving,
                   "recovery after queued suspension settles stopped", &problems)
        }

        return problems
    }

    /// Scalar and interval consumers must see the same disjoint unsaved facts:
    /// Editor's one-minute tail, Browser's five-minute close and Xcode's live
    /// five minutes, without filling the four-minute absence between them.
    private static func testQueuedUsageIntervalsFeedFocusedActiveTotals() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let root = scratchDirectory()
        let directory = root.appendingPathComponent("usage")
        let savedDirectory = root.appendingPathComponent("saved-usage")
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Reconcile queued usage")

        tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
        clock.advance(10 * 60)
        tracker.flush()
        clock.advance(60)
        try? FileManager.default.moveItem(at: directory, to: savedDirectory)
        try? Data("blocked".utf8).write(to: directory)
        tracker.suspend()

        clock.advance(4 * 60)
        tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
        tracker.confirmPresence(at: base.addingTimeInterval(15 * 60))
        clock.advance(5 * 60)
        tracker.appActivated(bundleID: "com.example.xcode", name: "Xcode")
        clock.advance(5 * 60)

        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)

        expectClose(store.trackedToday, 21 * 60,
                    "scalar tracked time includes every disjoint queued interval", &problems)
        expectClose(store.goal.achieved, 21 * 60,
                    "focused-active time includes every disjoint queued interval", &problems)

        let rewardUsage = AppUsageSnapshot(archive: usage, tracker: tracker).sessions
        let rewardGoal = DailyGoal(archive: engine.archive,
                                   goal: engine.store.dailyGoal,
                                   usage: rewardUsage,
                                   usageAccurateFrom: usage.metadata.accurateFrom,
                                   running: engine.runningSpan,
                                   runningWork: engine.elapsedToday(),
                                   now: { clock.value })
        expectClose(rewardGoal.achievedToday(), 21 * 60,
                    "reward focused-active time includes every disjoint queued interval",
                    &problems)
        return problems
    }

    /// Persistence state, not the size of an additive tail, drives the existing
    /// minute cadence. A short terminal close and an idle correction behind the
    /// durable checkpoint are both immutable pending writes that must retry.
    private static func testPendingUsageRetriesWithoutTailThreshold() -> [String] {
        var problems: [String] = []

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(30)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            expectClose(tracker.unpersistedSeconds(), 30,
                        "the failed terminal close has only a sub-minute tail", &problems)
            expect(tracker.openSeconds(exceeds: 60),
                   "a sub-minute pending close must request the persistence cadence", &problems)

            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            if tracker.openSeconds(exceeds: 60) { tracker.flush() }
            expectClose(usage.sessions.first?.seconds ?? -1, 10.5 * 60,
                        "the cadence retries and persists the short frozen close", &problems)
        }

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(2 * 60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.observeIdle(seconds: 7 * 60)

            expectClose(tracker.unpersistedSeconds(), 0,
                        "a backward correction has no additive tail", &problems)
            expect(tracker.openSeconds(exceeds: 60),
                   "a backward correction must still request the persistence cadence", &problems)

            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            if tracker.openSeconds(exceeds: 60) { tracker.flush() }
            expectClose(usage.sessions.first?.seconds ?? -1, 5 * 60,
                        "the cadence retries and persists the backward correction", &problems)
            expect(usage.sessions.first?.endReason == .idle,
                   "the retried correction retains its idle reason", &problems)
        }

        return problems
    }

    /// Pending usage is the current truth for its stable UUID. It replaces a
    /// durable checkpoint in memory—possibly with an earlier end—and supplies
    /// queued UUIDs to the live, dashboard, period, goal and reward paths while
    /// the on-disk archive remains untouched.
    private static func testAuthoritativePendingUsageOverlay() -> [String] {
        var problems: [String] = []

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let engine = makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Correct checkpoint")

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            let stableID = usage.sessions.first?.id
            clock.advance(2 * 60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.observeIdle(seconds: 7 * 60)

            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.setDashboardVisible(true)

            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "the durable archive remains untouched while correction is pending",
                        &problems)
            expectClose(store.trackedToday, 5 * 60,
                        "the live tracked total replaces the durable checkpoint", &problems)
            expectClose(store.goal.achieved, 5 * 60,
                        "the live goal uses the corrected hands-on interval", &problems)
            expectClose(store.trackedForSelectedDay, 5 * 60,
                        "the dashboard total uses the corrected interval", &problems)
            expectClose(store.rankedApps.first?.total ?? -1, 5 * 60,
                        "the dashboard app ranking uses the corrected interval", &problems)
            expect(store.timelineSegments.count == 1
                       && store.timelineSegments.first?.id == stableID,
                   "the dashboard keeps one stable corrected UUID", &problems)

            let rewardUsage = AppUsageSnapshot(archive: usage, tracker: tracker).sessions
            expect(rewardUsage.count == 1 && rewardUsage.first?.id == stableID,
                   "the reward path replaces rather than duplicates the pending UUID", &problems)
            expectClose(rewardUsage.first?.seconds ?? -1, 5 * 60,
                        "the reward path sees the backward correction", &problems)
        }

        do {
            let clock = Clock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let engine = makeEngine(clock)

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()
            clock.advance(4 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: clock.value)
            clock.advance(5 * 60)
            tracker.appActivated(bundleID: "com.example.xcode", name: "Xcode")
            clock.advance(5 * 60)

            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.setDashboardVisible(true)

            expectClose(store.trackedForSelectedDay, 21 * 60,
                        "the Day dashboard includes every queued confirmed interval", &problems)
            expectClose(store.rankedApps.reduce(0) { $0 + $1.total }, 21 * 60,
                        "the Day app rows reconcile with the queued total", &problems)
            expect(Set(store.timelineSegments.map(\.id)).count == 3,
                   "the Day timeline contains the three authoritative UUIDs", &problems)

            store.period = .week
            expectClose(store.periodSummary.tracked, 21 * 60,
                        "the Week total includes every queued confirmed interval", &problems)
            expectClose(store.periodDays.reduce(0) { $0 + $1.tracked }, 21 * 60,
                        "the Week bars reconcile with their queued total", &problems)

            store.period = .month
            expectClose(store.periodSummary.tracked, 21 * 60,
                        "the Month total includes every queued confirmed interval", &problems)
            expectClose(store.periodDays.reduce(0) { $0 + $1.tracked }, 21 * 60,
                        "the Month bars reconcile with their queued total", &problems)
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "period views do not rewrite the durable checkpoint", &problems)
        }

        return problems
    }

    /// Migration and corrupt-file handling are preservation operations. If the
    /// destination cannot be created, the original bytes stay in place and no
    /// later mutation is allowed to overwrite them in that process.
    private static func testUsagePreservationFailureFailsClosed() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let manager = FileManager.default

        do {
            let directory = scratchDirectory()
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("app-usage.json")
            let legacy = [AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                          start: base, end: base.addingTimeInterval(600))]
            let original = (try? JSONEncoder().encode(legacy)) ?? Data()
            try? original.write(to: file)
            let backup = directory.appendingPathComponent(
                "app-usage-v1-backup-\(Int(clock.value.timeIntervalSince1970)).json")
            try? manager.createDirectory(at: backup, withIntermediateDirectories: true)

            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let mutation = usage.record(AppUsageSession(
                bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code",
                start: base.addingTimeInterval(700), end: base.addingTimeInterval(800)))
            expect(usage.sessions == legacy,
                   "failed backup still exposes the safely decoded legacy history", &problems)
            expect(usage.isReadOnly && !mutation,
                   "failed legacy preservation makes mutations fail closed", &problems)
            expect((try? Data(contentsOf: file)) == original,
                   "failed legacy backup leaves the source bytes untouched", &problems)
            expect(usage.revision == 0 && usage.legacyBackupURL == nil,
                   "failed migration publishes no revision or backup", &problems)
        }

        do {
            let directory = scratchDirectory()
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("app-usage.json")
            let original = Data("not valid usage json".utf8)
            try? original.write(to: file)
            let aside = directory.appendingPathComponent(
                "app-usage-corrupt-\(Int(clock.value.timeIntervalSince1970)).json")
            try? manager.createDirectory(at: aside, withIntermediateDirectories: true)

            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let mutation = usage.record(AppUsageSession(
                bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                start: base, end: base.addingTimeInterval(600)))
            expect(usage.isReadOnly && !mutation,
                   "failed corrupt-file preservation makes mutations fail closed", &problems)
            expect((try? Data(contentsOf: file)) == original,
                   "failed corrupt move preserves the unreadable source bytes", &problems)
            expect(usage.sessions.isEmpty && usage.revision == 0,
                   "unreadable evidence is not invented or published", &problems)
        }
        return problems
    }

    /// A safely decodable future envelope is useful for display, but this build
    /// cannot know how to preserve its semantics. It therefore rejects writes
    /// and leaves even unknown fields byte-for-byte intact.
    private static func testFutureUsageSchemaIsReadOnly() -> [String] {
        struct FutureEnvelope: Codable {
            let metadata: AppUsageMetadata
            let sessions: [AppUsageSession]
            let futureField: String
        }

        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("app-usage.json")
        let existing = AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                       start: base, end: base.addingTimeInterval(600))
        let original = (try? JSONEncoder().encode(FutureEnvelope(
            metadata: AppUsageMetadata(schemaVersion: 99, accurateFrom: base),
            sessions: [existing], futureField: "must survive"))) ?? Data()
        try? original.write(to: file)

        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        var callbacks = 0
        usage.onDidChange = { callbacks += 1 }
        let mutation = usage.record(AppUsageSession(
            bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code",
            start: base.addingTimeInterval(700), end: base.addingTimeInterval(800)))

        expect(usage.sessions == [existing] && usage.metadata.schemaVersion == 99,
               "a safely decoded future envelope remains available for display", &problems)
        expect(usage.isReadOnly && !mutation,
               "an unsupported schema rejects mutation", &problems)
        expect(usage.revision == 0 && callbacks == 0,
               "a rejected future-schema write publishes nothing", &problems)
        expect((try? Data(contentsOf: file)) == original,
               "future schema bytes and unknown fields remain identical", &problems)
        return problems
    }

    /// Integrity qualification needs a yes/no answer, not an allocated copy of
    /// the whole filtered archive. System processes remain excluded and both
    /// the selected interval and accuracy cutoff are respected.
    private static func testIntegrityUsageQuery() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let interval = DateInterval(start: base.addingTimeInterval(-4 * 3_600),
                                    end: base.addingTimeInterval(2 * 3_600))

        usage.record(AppUsageSession(bundleID: "com.apple.loginwindow", appName: "Login Window",
                                     start: base.addingTimeInterval(-3 * 3_600),
                                     end: base.addingTimeInterval(-2 * 3_600)))
        usage.record(AppUsageSession(bundleID: "com.example.after", appName: "After",
                                     start: base.addingTimeInterval(600),
                                     end: base.addingTimeInterval(1_200)))
        expect(!usage.containsUsage(in: interval, before: base),
               "system usage and ordinary usage after the cutoff do not qualify", &problems)

        usage.record(AppUsageSession(bundleID: "com.example.before", appName: "Before",
                                     start: base.addingTimeInterval(-1_200),
                                     end: base.addingTimeInterval(-600)))
        expect(usage.containsUsage(in: interval, before: base),
               "ordinary usage inside the interval before the cutoff qualifies", &problems)
        let later = DateInterval(start: base.addingTimeInterval(3_600),
                                 end: base.addingTimeInterval(7_200))
        expect(!usage.containsUsage(in: later, before: base.addingTimeInterval(7_200)),
               "usage outside the selected interval does not qualify", &problems)
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

    /// A period bar is one tracked-time fact. Focus composition belongs to the
    /// separate Work type donut and must not determine the bar's height.
    private static func testPeriodChartUsesTrackedTime() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let sessions = SessionArchive(directory: directory, now: { clock.value })

        usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                     start: day.addingTimeInterval(9 * 3_600),
                                     end: day.addingTimeInterval(11 * 3_600)))
        sessions.append(SessionRecord(name: "Focused edit", workType: .deepWork,
                                      start: day.addingTimeInterval(9 * 3_600),
                                      end: day.addingTimeInterval(9.75 * 3_600),
                                      workSeconds: 45 * 60))

        let rollup = PeriodStats(sessions: sessions, usage: usage,
                                 calendar: calendar, now: { clock.value })
            .rollup(for: .day, containing: day)
        guard !rollup.days.isEmpty else {
            return ["the day rollup must contain one chart day"]
        }

        let points = PeriodChartData.tracked(rollup.days)
        expect(points.count == 1, "one selected day produces one period bar", &problems)
        expectClose(points.first?.seconds ?? -1, 2 * 3_600,
                    "the period chart point is exactly two tracked hours", &problems)
        expectClose(rollup.summary.averagePerActiveDay, 2 * 3_600,
                    "the tracked average is exactly two hours", &problems)
        return problems
    }

    /// Correcting an open checkpoint keeps the archive count unchanged. The
    /// cache must therefore key on revision, or it serves the old duration.
    private static func testDashboardDaySliceInvalidatesOnRevision() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = Calendar.current.startOfDay(for: base)
        let identity = UUID()
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let sessions = SessionArchive(directory: directory, now: { clock.value })
        let original = AppUsageSession(id: identity, bundleID: "com.example.editor",
                                       appName: "Editor", start: day.addingTimeInterval(9 * 3_600),
                                       end: day.addingTimeInterval(10 * 3_600),
                                       endReason: .stillOpen)
        usage.checkpoint(original)
        let stats = DashboardStats(sessions: sessions, usage: usage,
                                   now: { clock.value })
        expectClose(stats.trackedTotal(for: day), 3_600,
                    "the initial day slice is one hour", &problems)

        let corrected = AppUsageSession(id: identity, bundleID: original.bundleID,
                                        appName: original.appName, start: original.start,
                                        end: day.addingTimeInterval(10.5 * 3_600),
                                        endReason: .stillOpen)
        usage.checkpoint(corrected)
        expect(usage.sessions.count == 1,
               "the corrected checkpoint keeps the archive count at one", &problems)
        expectClose(stats.trackedTotal(for: day), 1.5 * 3_600,
                    "the revised day slice is rebuilt to ninety minutes", &problems)
        return problems
    }

    /// Archive callbacks update the dashboard immediately only while it is on
    /// screen. Hidden mutations are coalesced until the next appearance.
    private static func testDashboardArchiveVisibility() -> [String] {
        var problems: [String] = []
        let clock = Clock(anchoredNow())
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let sessions = SessionArchive(directory: directory, now: { clock.value })
        let engine = SessionEngine(store: persistence, archive: sessions,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine)
        store.attach(tracker: tracker, usage: usage)
        let day = Calendar.current.startOfDay(for: clock.value)
        let identity = UUID()

        func checkpoint(minutes: Double) {
            usage.checkpoint(AppUsageSession(id: identity, bundleID: "com.example.editor",
                                             appName: "Editor",
                                             start: day.addingTimeInterval(9 * 3_600),
                                             end: day.addingTimeInterval(9 * 3_600 + minutes * 60),
                                             endReason: .stillOpen))
        }

        checkpoint(minutes: 10)
        expectClose(store.trackedForSelectedDay, 0,
                    "a hidden dashboard does not refresh immediately", &problems)
        store.refresh()
        expectClose(store.trackedForSelectedDay, 0,
                    "an ordinary hidden refresh does not consume the full dashboard", &problems)
        expectClose(store.glanceApps.first?.total ?? -1, 10 * 60,
                    "the hidden-dashboard refresh still updates today's popover glance", &problems)
        store.setDashboardVisible(true)
        expectClose(store.trackedForSelectedDay, 10 * 60,
                    "appearing consumes the pending archive refresh", &problems)

        checkpoint(minutes: 20)
        expectClose(store.trackedForSelectedDay, 20 * 60,
                    "a visible dashboard refreshes a same-count correction immediately", &problems)

        store.setDashboardVisible(false)
        checkpoint(minutes: 30)
        expectClose(store.trackedForSelectedDay, 20 * 60,
                    "a hidden dashboard keeps its last rendered value", &problems)
        store.setDashboardVisible(true)
        expectClose(store.trackedForSelectedDay, 30 * 60,
                    "the next appearance refreshes hidden archive changes", &problems)
        return problems
    }

    /// A normal refresh flushes the open stretch. Its synchronous archive
    /// callback must join that transaction rather than re-entering the full
    /// selected-day/period rebuild and publishing every figure twice.
    private static func testDashboardRefreshCoalescesCheckpointCallback() -> [String] {
        var problems: [String] = []
        let clock = Clock(anchoredNow())
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence,
                                   archive: SessionArchive(directory: directory,
                                                           now: { clock.value }),
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine)
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
        clock.advance(10 * 60)

        var fullTrackedPublications = 0
        let observation = store.$trackedForSelectedDay.dropFirst().sink { _ in
            fullTrackedPublications += 1
        }
        store.refresh()

        expect(usage.sessions.count == 1, "refresh flushes one stable checkpoint", &problems)
        expectClose(store.trackedForSelectedDay, 10 * 60,
                    "the one full rebuild sees the flushed checkpoint", &problems)
        expect(fullTrackedPublications == 1,
               "one refresh transaction publishes the full tracked figure once, got "
               + "\(fullTrackedPublications)", &problems)
        withExtendedLifetime(observation) {}
        return problems
    }

    /// Preserved usage before the authoritative recording epoch remains
    /// visible, but the selected day carries the approved qualification.
    private static func testSelectedDayIntegrityNote() -> [String] {
        var problems: [String] = []
        let clock = Clock(anchoredNow())
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence,
                                   archive: SessionArchive(directory: directory,
                                                           now: { clock.value }),
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        guard let yesterday = calendar.date(byAdding: .day, value: -1,
                                            to: calendar.startOfDay(for: clock.value)) else {
            return ["could not make the pre-accuracy day"]
        }
        usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                     start: yesterday.addingTimeInterval(10 * 3_600),
                                     end: yesterday.addingTimeInterval(10.5 * 3_600)))
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine)
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.selectDay(offset: 1)

        let expected = "App usage from before \(Tokens.longDate(clock.value)) was preserved "
            + "and may include unattended time."
        expect(store.selectedDayIntegrityNote == expected,
               "the selected pre-accuracy day shows the approved warning", &problems)
        store.selectDay(offset: 2)
        expect(store.selectedDayIntegrityNote == nil,
               "a pre-accuracy day without usage has no warning", &problems)
        store.setDashboardVisible(false)
        guard let twoDaysAgo = calendar.date(byAdding: .day, value: -2,
                                             to: calendar.startOfDay(for: clock.value)) else {
            return problems + ["could not make the second pre-accuracy day"]
        }
        usage.record(AppUsageSession(bundleID: "com.example.browser", appName: "Browser",
                                     start: twoDaysAgo.addingTimeInterval(11 * 3_600),
                                     end: twoDaysAgo.addingTimeInterval(11.25 * 3_600)))
        store.refresh()
        expect(store.selectedDayIntegrityNote == nil,
               "the cached warning stays frozen while the dashboard is hidden", &problems)
        store.setDashboardVisible(true)
        expect(store.selectedDayIntegrityNote == expected,
               "dashboard appearance rebuilds the cached warning", &problems)
        store.selectDay(offset: 0)
        expect(store.selectedDayIntegrityNote == nil,
               "an authoritative selected day has no warning", &problems)
        return problems
    }

    /// Period qualification is about every bar and log row in view, not merely
    /// the anchor day. A post-epoch anchor must still warn when its selected
    /// week or month reaches back into preserved legacy usage.
    private static func testPeriodIntegrityNoteCoversCompleteRange() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let anchor = periodAnchor()
        guard let week = calendar.dateInterval(of: .weekOfYear, for: anchor),
              let month = calendar.dateInterval(of: .month, for: anchor) else {
            return ["could not construct period integrity bounds"]
        }
        let legacyWeekStart = week.start.addingTimeInterval(2 * 3_600)
        let legacyMonthStart = month.start.addingTimeInterval(3 * 3_600)
        let accurateFrom = max(legacyWeekStart, legacyMonthStart).addingTimeInterval(3_600)
        guard accurateFrom < anchor else {
            return ["the anchored period has no pre-epoch interval to exercise"]
        }

        let clock = Clock(accurateFrom)
        let directory = scratchDirectory()
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        usage.record(AppUsageSession(bundleID: "com.example.week", appName: "Week Legacy",
                                     start: legacyWeekStart,
                                     end: legacyWeekStart.addingTimeInterval(600)))
        usage.record(AppUsageSession(bundleID: "com.example.month", appName: "Month Legacy",
                                     start: legacyMonthStart,
                                     end: legacyMonthStart.addingTimeInterval(600)))
        clock.value = anchor

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence,
                                   archive: SessionArchive(directory: directory,
                                                           now: { clock.value }),
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      isEnabled: false, idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        expect(store.selectedDayIntegrityNote == nil,
               "the post-epoch anchor day itself has no legacy warning", &problems)

        let expected = "App usage from before \(Tokens.longDate(accurateFrom)) was preserved "
            + "and may include unattended time."
        store.period = .week
        expect(store.selectedDayIntegrityNote == expected,
               "Week warns when any selected day contains legacy usage", &problems)
        store.period = .month
        expect(store.selectedDayIntegrityNote == expected,
               "Month warns when any selected day contains legacy usage", &problems)
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
        let usageAccurateFrom = calendar.date(byAdding: .day, value: -15, to: current) ?? current

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
                                  usage: handsOn, usageAccurateFrom: usageAccurateFrom,
                                  now: { clock.value }).progress()
        expectClose(underGoal.achieved, 3_600, "under-goal achieved", &problems)
        expectClose(underGoal.share, 0.5, "under-goal share", &problems)
        expect(!underGoal.isMet, "1h against a 2h goal should not be met", &problems)
        expect(underGoal.typicalByNow == nil, "two active days is below the minimum", &problems)
        expect(underGoal.aheadBy == nil, "aheadBy must be nil when typicalByNow is nil", &problems)

        // An archived session with no hands-on time behind it fills nothing —
        // the rule that stops a wall-clock session from claiming a goal.
        let unattended = DailyGoal(archive: archive, goal: 2 * 3_600,
                                   usageAccurateFrom: usageAccurateFrom,
                                   now: { clock.value }).progress()
        expectClose(unattended.achieved, 0,
                    "a session nobody was present for fills no goal", &problems)

        let overGoal = DailyGoal(archive: archive, goal: 1_800,
                                 usage: handsOn, usageAccurateFrom: usageAccurateFrom,
                                 now: { clock.value }).progress()
        expectClose(overGoal.share, 2.0, "over-goal share is uncapped", &problems)
        expect(overGoal.isMet, "1h against a 30m goal should be met", &problems)

        try? FileManager.default.removeItem(at: dir)

        // Five active days with a clean median, plus two inactive days inside
        // the same window that must not drag the median down.
        let dir2 = scratchDirectory()
        let archive2 = SessionArchive(directory: dir2, now: { clock.value })
        var historyUsage2: [AppUsageSession] = []
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
            historyUsage2.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                                  start: start,
                                                  end: start.addingTimeInterval(minutesByNow * 60)))
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
                              usage: handsOn2 + historyUsage2,
                              usageAccurateFrom: usageAccurateFrom,
                              now: { clock.value }).progress()
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

    /// Historical pace must describe the same proved work as today's goal:
    /// session time intersected with hands-on usage, not a session's full span.
    /// Before the reconciliation, this fixture reported a raw two-hour median
    /// instead of the one authoritative focused-active hour.
    private static func testHistoricalPaceUsesFocusedActiveTime() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, now: { clock.value })
        let calendar = Calendar.current
        let current = calendar.startOfDay(for: base).addingTimeInterval(10 * 3_600)
        clock.value = current
        var usage: [AppUsageSession] = []

        func addDay(offset: Int, startingAt startHour: Double, usageStartsAt usageHour: Double) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else { return }
            let start = calendar.startOfDay(for: day).addingTimeInterval(startHour * 3_600)
            archive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval((10 - startHour) * 3_600),
                                         workSeconds: (10 - startHour) * 3_600))
            usage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: calendar.startOfDay(for: day)
                                             .addingTimeInterval(usageHour * 3_600),
                                         end: calendar.startOfDay(for: day)
                                             .addingTimeInterval(10 * 3_600)))
        }

        // The day before migration and the migration day have both enough
        // activity to influence a raw median, but neither has a uniform
        // checkpoint guarantee and must be excluded.
        addDay(offset: 5, startingAt: 5, usageStartsAt: 5)
        addDay(offset: 4, startingAt: 5, usageStartsAt: 5)
        // `accurateFrom` lies in offset 4, so offsets 3 through 1 are the
        // first eligible complete days. Each has two session hours but only
        // one hour of usage inside the same cutoff.
        addDay(offset: 2, startingAt: 8, usageStartsAt: 9)
        addDay(offset: 1, startingAt: 8, usageStartsAt: 9)
        let migrationDay = calendar.date(byAdding: .day, value: -4, to: current) ?? current
        let accurateFrom = calendar.startOfDay(for: migrationDay).addingTimeInterval(14 * 3_600)
        func typical() -> TimeInterval? {
            DailyGoal(archive: archive, goal: 4 * 3_600, usage: usage,
                      usageAccurateFrom: accurateFrom, now: { clock.value }).typical()
        }

        expect(typical() == nil,
               "pre-epoch and migration-day records cannot satisfy the three-day minimum",
               &problems)

        addDay(offset: 3, startingAt: 8, usageStartsAt: 9)
        let result = typical()
        expectClose(result ?? 0, 3_600,
                    "two session hours with one usage hour contribute one historical hour",
                    &problems)

        try? FileManager.default.removeItem(at: directory)
        return problems
    }

    /// An active day contributes a zero when all of its focused work is later
    /// than today's clock time. Filtering it out would turn [30m, 30m, 0m]
    /// into a two-day history and suppress the valid 30-minute median.
    private static func testHistoricalPaceKeepsZeroCutoffSamples() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            return calendar.date(from: components) ?? base
        }
        let current = date(2024, 1, 10, 10)
        let clock = Clock(current)
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        var usage: [AppUsageSession] = []

        func add(_ day: Date, hour: Int, minutes: Int) {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            let duration = TimeInterval(minutes * 60)
            archive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval(duration),
                                         workSeconds: duration))
            usage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start, end: start.addingTimeInterval(duration)))
        }

        // The first complete authoritative day is 7 January. Its 11am work is
        // active for the day but contributes 0 by the 10am comparison cutoff.
        add(date(2024, 1, 7), hour: 11, minutes: 30)
        add(date(2024, 1, 8), hour: 9, minutes: 30)
        add(date(2024, 1, 9), hour: 9, minutes: 30)
        let accurateFrom = date(2024, 1, 6, 14)
        let pace = DailyGoal(archive: archive, goal: 4 * 3_600, usage: usage,
                             usageAccurateFrom: accurateFrom, calendar: calendar,
                             now: { clock.value }).typical()
        expectClose(pace ?? -1, 30 * 60,
                    "three active days with [30m, 30m, 0m] by the cutoff have a 30m median",
                    &problems)

        let zeroDirectory = scratchDirectory()
        let zeroArchive = SessionArchive(directory: zeroDirectory, calendar: calendar,
                                         now: { clock.value })
        var zeroUsage: [AppUsageSession] = []
        for day in [date(2024, 1, 7), date(2024, 1, 8), date(2024, 1, 9)] {
            let start = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day) ?? day
            zeroArchive.append(SessionRecord(name: "S", workType: .deepWork,
                                             start: start, end: start.addingTimeInterval(30 * 60),
                                             workSeconds: 30 * 60))
            zeroUsage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                              start: start, end: start.addingTimeInterval(30 * 60)))
        }
        let zeroPace = DailyGoal(archive: zeroArchive, goal: 4 * 3_600, usage: zeroUsage,
                                 usageAccurateFrom: accurateFrom, calendar: calendar,
                                 now: { clock.value }).typical()
        expect(zeroPace != nil, "three active zero-cutoff samples remain a real median", &problems)
        expectClose(zeroPace ?? -1, 0, "a valid all-zero cutoff median is reported", &problems)

        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: zeroDirectory)
        return problems
    }

    /// Historical days must use the same local hour/minute/second as now, not
    /// elapsed seconds since midnight. This pins spring-forward's missing time
    /// to the next valid time and prevents a late cutoff spilling into tomorrow.
    private static func testHistoricalPaceDSTCutoffs() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components) ?? base
        }
        func add(_ archive: SessionArchive, _ usage: inout [AppUsageSession],
                 day: Date, hour: Int, minutes: Int) {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            let duration = TimeInterval(minutes * 60)
            archive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval(duration),
                                         workSeconds: duration))
            usage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start, end: start.addingTimeInterval(duration)))
        }

        // 02:30 does not exist on 10 March 2024. The historical cutoff is the
        // next valid local time (03:00), so the 03:00-03:30 work is excluded.
        let springCurrent = date(2024, 3, 12, 2, 30)
        let springClock = Clock(springCurrent)
        let springDirectory = scratchDirectory()
        let springArchive = SessionArchive(directory: springDirectory, calendar: calendar,
                                           now: { springClock.value })
        var springUsage: [AppUsageSession] = []
        add(springArchive, &springUsage, day: date(2024, 3, 9, 0), hour: 1, minutes: 10)
        add(springArchive, &springUsage, day: date(2024, 3, 10, 0), hour: 1, minutes: 30)
        add(springArchive, &springUsage, day: date(2024, 3, 10, 0), hour: 3, minutes: 30)
        add(springArchive, &springUsage, day: date(2024, 3, 11, 0), hour: 1, minutes: 50)
        let accurateFrom = date(2024, 3, 8, 14)
        let springPace = DailyGoal(archive: springArchive, goal: 4 * 3_600,
                                   usage: springUsage, usageAccurateFrom: accurateFrom,
                                   calendar: calendar, now: { springClock.value }).typical()
        expectClose(springPace ?? -1, 30 * 60,
                    "spring-forward uses the next valid 03:00 cutoff, not elapsed 03:30",
                    &problems)

        // A 23:30 cutoff on the 23-hour spring-forward day must end at 23:30,
        // never at 00:30 on 11 March where this distinct 50-minute record sits.
        let lateCurrent = date(2024, 3, 13, 23, 30)
        let lateClock = Clock(lateCurrent)
        let lateDirectory = scratchDirectory()
        let lateArchive = SessionArchive(directory: lateDirectory, calendar: calendar,
                                         now: { lateClock.value })
        var lateUsage: [AppUsageSession] = []
        add(lateArchive, &lateUsage, day: date(2024, 3, 10, 0), hour: 12, minutes: 30)
        add(lateArchive, &lateUsage, day: date(2024, 3, 11, 0), hour: 0, minutes: 50)
        add(lateArchive, &lateUsage, day: date(2024, 3, 12, 0), hour: 12, minutes: 40)
        let latePace = DailyGoal(archive: lateArchive, goal: 4 * 3_600,
                                 usage: lateUsage, usageAccurateFrom: accurateFrom,
                                 calendar: calendar, now: { lateClock.value }).typical()
        expectClose(latePace ?? -1, 40 * 60,
                    "a spring-forward day cutoff never spills into the next local day",
                    &problems)

        // 01:30 occurs twice on 3 November. The first occurrence is the
        // controller-selected cutoff, so work in the second occurrence remains
        // after the comparison point.
        let fallCurrent = date(2024, 11, 5, 1, 30)
        let fallClock = Clock(fallCurrent)
        let fallDirectory = scratchDirectory()
        let fallArchive = SessionArchive(directory: fallDirectory, calendar: calendar,
                                         now: { fallClock.value })
        var fallUsage: [AppUsageSession] = []
        add(fallArchive, &fallUsage, day: date(2024, 11, 2, 0), hour: 0, minutes: 10)
        let fallDay = date(2024, 11, 3, 0)
        var repeated = DateComponents()
        repeated.hour = 1
        let secondOneAM = calendar.nextDate(
            after: calendar.startOfDay(for: fallDay).addingTimeInterval(-1),
            matching: repeated, matchingPolicy: .nextTime,
            repeatedTimePolicy: .last, direction: .forward) ?? fallDay
        fallArchive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: secondOneAM,
                                         end: secondOneAM.addingTimeInterval(30 * 60),
                                         workSeconds: 30 * 60))
        fallUsage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: secondOneAM,
                                         end: secondOneAM.addingTimeInterval(30 * 60)))
        add(fallArchive, &fallUsage, day: date(2024, 11, 4, 0), hour: 0, minutes: 50)
        let fallPace = DailyGoal(archive: fallArchive, goal: 4 * 3_600,
                                 usage: fallUsage,
                                 usageAccurateFrom: date(2024, 11, 1, 14),
                                 calendar: calendar, now: { fallClock.value }).typical()
        expectClose(fallPace ?? -1, 10 * 60,
                    "fall-back uses the first 01:30 occurrence as its cutoff",
                    &problems)

        try? FileManager.default.removeItem(at: springDirectory)
        try? FileManager.default.removeItem(at: lateDirectory)
        try? FileManager.default.removeItem(at: fallDirectory)
        return problems
    }

    /// The open tail is real hands-on evidence before the next checkpoint. It
    /// must advance both the goal and tracked scalar each tick, while the latter
    /// counts only the tail intersecting the current local day.
    private static func testLiveUsageFeedsGoalAndClipsMidnight() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: anchoredNow())

        do {
            let clock = Clock(dayStart.addingTimeInterval(10 * 3_600))
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory,
                                                               now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            engine.start(workType: .deepWork, intent: "Live work")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            clock.advance(90)
            store.updateTimeDrivenFigures()

            expect(usage.sessions.isEmpty,
                   "the between-checkpoint test retains a wholly live tail", &problems)
            expectClose(tracker.unpersistedSession()?.seconds ?? -1, 90,
                        "the tracker exposes the exact unpersisted live session", &problems)
            expectClose(store.goal.achieved, 90,
                        "live hands-on time advances focused-active goal progress", &problems)
            expectClose(store.trackedToday, 90,
                        "live tracked time advances between checkpoints", &problems)
        }

        do {
            let start = dayStart.addingTimeInterval(23 * 3_600 + 59 * 60)
            let clock = Clock(start)
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory,
                                                               now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            engine.start(workType: .deepWork, intent: "Midnight work")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            clock.advance(2 * 60)
            store.updateTimeDrivenFigures()

            expectClose(tracker.unpersistedSession()?.seconds ?? -1, 2 * 60,
                        "the exposed live session keeps its full cross-midnight interval", &problems)
            expectClose(tracker.unpersistedSeconds(on: clock.value, calendar: calendar), 60,
                        "the tracker clips the live scalar to the new local day", &problems)
            expectClose(store.trackedToday, 60,
                        "today's tracked scalar excludes yesterday's live minute", &problems)
            expectClose(store.goal.achieved, 60,
                        "today's goal intersects only the post-midnight live minute", &problems)
        }
        return problems
    }

    /// The historical median is deliberately cached, but the existing ticker
    /// must advance that cache at local minute boundaries even when no archive,
    /// state or window event triggers a full refresh.
    private static func testHistoricalPaceRefreshesOnMinuteBoundary() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchoredNow())
        let current = today.addingTimeInterval(10 * 3_600)
        let clock = Clock(calendar.date(byAdding: .day, value: -20, to: current) ?? base)
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        clock.value = current

        for offset in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return problems + ["could not make historical pace day \(offset)"]
            }
            let start = day.addingTimeInterval(9 * 3_600)
            let end = day.addingTimeInterval(10 * 3_600 + 10 * 60)
            archive.append(SessionRecord(name: "Pace", workType: .deepWork,
                                         start: start, end: end,
                                         workSeconds: end.timeIntervalSince(start)))
            usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                         start: start, end: end))
        }

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      isEnabled: false, idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        expectClose(store.goal.typicalByNow ?? -1, 60 * 60,
                    "the initial 10:00 pace median", &problems)

        clock.advance(60)
        store.updateTimeDrivenFigures()
        expectClose(store.goal.typicalByNow ?? -1, 61 * 60,
                    "the existing ticker path refreshes pace at 10:01", &problems)
        clock.advance(30)
        store.updateTimeDrivenFigures()
        expectClose(store.goal.typicalByNow ?? -1, 61 * 60,
                    "the expensive median remains cached inside the same minute", &problems)
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
        let directory = scratchDirectory()
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
        let directory = scratchDirectory()
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
        let directory = scratchDirectory()
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

    /// Historical focus remains a raw session statistic, but every goal claim
    /// must use the same declared-session ∩ authoritative-hands-on measure as
    /// today. Five unattended session hours cannot meet a four-hour goal when
    /// only one hour intersects app usage.
    private static func testHistoricalGoalStatusUsesFocusedActiveTime() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.value)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let accurateFrom = calendar.date(byAdding: .day, value: -1, to: yesterday) else {
            return ["could not make authoritative historical days"]
        }
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, calendar: calendar,
                                     now: { clock.value })
        archive.append(SessionRecord(name: "Unattended build", workType: .deepWork,
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(14 * 3_600),
                                     workSeconds: 5 * 3_600))
        let usage = AppUsageArchive(directory: directory, calendar: calendar,
                                    now: { accurateFrom })
        usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(10 * 3_600)))

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        persistence.dailyGoal = 4 * 3_600
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self",
                                   schedulesDwell: false, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.selectDay(offset: 1)

        expectClose(store.focusedForSelectedDay, 5 * 3_600,
                    "the historical Focused statistic retains raw session work", &problems)
        expectClose(store.selectedDayGoal.achieved, 3_600,
                    "the historical goal ring uses focused-active time", &problems)
        expect(!store.selectedDayGoal.isMet,
               "one hands-on hour cannot meet a four-hour historical goal", &problems)
        expect(!store.selectedDaySummary.contains("goal met"),
               "the historical title must not claim the raw session met the goal", &problems)
        let daySummary = SummaryText.plain(store.summarySentences)
        expect(daySummary.contains("3h short of the 4h goal"),
               "historical shortfall copy uses focused-active achievement: \(daySummary)",
               &problems)

        store.period = .week
        let periodSummary = SummaryText.plain(store.summarySentences)
        expect(periodSummary.contains("without meeting the 4h goal on any day"),
               "period goal-day status uses focused-active achievement: \(periodSummary)",
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
        var revealCount = 0
        let model = SettingsModel(store: store, isTrackingEnabled: true,
                                  onChange: { changes += 1 },
                                  onTrackingChanged: { tracking.append($0) },
                                  revealDataFolder: { revealCount += 1 })

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
        model.revealDataFolder()
        expect(revealCount == 1, "Reveal data folder invokes its read-only action", &problems)
        expect(changes == 10 && tracking == [false],
               "revealing data changes no setting and sends no preference callback", &problems)
        return problems
    }

    // MARK: - 83

    /// Navigation defaults are user-facing preferences and therefore first-class
    /// persisted settings; corrupted values should never crash the app.
    private static func testMainNavigationAndInterfacePreferences() -> [String] {
        var problems: [String] = []
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()

        var preferenceChanges = 0
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                    onChange: { preferenceChanges += 1 },
                                    onTrackingChanged: { _ in })

        expect(settings.defaultAppTab == .focus, "Focus is the default tab", &problems)
        expect(settings.interfaceDensity == .comfortable, "Comfortable is the default density", &problems)
        expect(settings.appearancePreference == .system, "System is the default appearance preference", &problems)
        expect(settings.showsTimelineLabels == true, "Timeline labels are visible by default", &problems)

        expect(AppTab.focus.moved(by: -1) == .settings, "left wrap works", &problems)
        expect(AppTab.settings.moved(by: 1) == .focus, "right wrap works", &problems)

        settings.defaultAppTab = .today
        expect(preferenceChanges == 1, "default tab notifies exactly once", &problems)
        settings.interfaceDensity = .compact
        expect(preferenceChanges == 2, "density notifies exactly once", &problems)
        settings.appearancePreference = .dark
        expect(preferenceChanges == 3, "appearance preference notifies exactly once", &problems)
        settings.showsTimelineLabels = false
        expect(preferenceChanges == 4, "timeline labels preference notifies exactly once", &problems)

        let reloadedSettings = SettingsModel(store: store, isTrackingEnabled: true,
                                            onChange: { },
                                            onTrackingChanged: { _ in })
        expect(reloadedSettings.defaultAppTab == .today, "default tab persists", &problems)
        expect(reloadedSettings.interfaceDensity == .compact, "density persists", &problems)
        expect(reloadedSettings.appearancePreference == .dark, "appearance preference persists", &problems)
        expect(reloadedSettings.showsTimelineLabels == false, "timeline labels preference persists", &problems)

        store.defaultAppTabRawValue = "invalid-tab"
        store.interfaceDensityRawValue = "invalid-density"
        store.appearanceRawValue = "invalid-appearance"
        let fallbackSettings = SettingsModel(store: store, isTrackingEnabled: true,
                                           onChange: { },
                                           onTrackingChanged: { _ in })
        expect(fallbackSettings.defaultAppTab == .focus, "invalid tab falls back to Focus", &problems)
        expect(fallbackSettings.interfaceDensity == .comfortable,
               "invalid density falls back to Comfortable", &problems)
        expect(fallbackSettings.appearancePreference == .system,
               "invalid appearance falls back to System", &problems)

        defaults.removeObject(forKey: "fc.showsTimelineLabels")
        defaults.set(NSNumber(value: 0), forKey: "fc.showsTimelineLabels")
        let malformedBooleanSettings = SettingsModel(store: store, isTrackingEnabled: true,
                                                     onChange: { },
                                                     onTrackingChanged: { _ in })
        expect(malformedBooleanSettings.showsTimelineLabels,
               "a non-Boolean timeline-label value falls back to visible", &problems)
        return problems
    }

    /// An explicit appearance may override macOS, but returning to System must
    /// remove that override so a live system appearance change reaches the app.
    private static func testSystemAppearanceClearsApplicationOverride() -> [String] {
        var problems: [String] = []
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }

        let model = SettingsModel(
            store: store,
            isTrackingEnabled: true,
            onChange: {},
            onTrackingChanged: { _ in },
            onAppearanceChanged: { preference in preference.apply(to: NSApp) })

        model.appearancePreference = .dark
        expect(NSApp.appearance?.name == .darkAqua,
               "Dark sets an explicit application appearance", &problems)

        model.appearancePreference = .system
        expect(NSApp.appearance == nil,
               "System clears the override so macOS appearance is inherited", &problems)
        return problems
    }

    /// The Settings information architecture is searchable because its real
    /// controls carry metadata, and every mutable row resolves to one concrete
    /// SettingsModel property rather than a placeholder preference.
    /// The launch preference must reach the window, and a sheet-backed tab must
    /// present its sheet on construction — otherwise restoring a surface shows
    /// the story with no sign of what was asked for.
    private static func testWindowOpensOnPreferredStory() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            for scope in StoryScope.allCases {
                let window = MainWindowModel(selectedTab: .story, storyScope: scope)
                expect(window.storyScope == scope,
                       "a window built for \(scope.title) opens on \(scope.title)", &problems)
                expect(window.sheet == nil,
                       "the story itself presents no sheet at \(scope.title)", &problems)
            }

            let settings = MainWindowModel(selectedTab: .settings)
            expect(settings.sheet == .settings,
                   "a window built on Settings is already presenting Settings", &problems)
            let awards = MainWindowModel(selectedTab: .awards)
            expect(awards.sheet == .awards,
                   "a window built on Awards is already presenting Awards", &problems)
            settings.closeSheet()
            expect(settings.sheet == nil, "closing the sheet returns the story", &problems)
        }
        return problems
    }

    private static func testSettingsGroupsContainOnlyBackedControls() -> [String] {
        var problems: [String] = []
        let expectedTitles = [
            "General", "Focus sessions", "Away and breaks", "Automatic and rewards",
            "Tracking and apps", "Appearance", "Data and privacy", "Advanced"
        ]
        expect(SettingsSection.allCases.map(\.title) == expectedTitles,
               "all eight Settings groups retain their approved order and titles", &problems)
        expect(SettingsSection.allCases.allSatisfy {
            !$0.symbol.isEmpty && !$0.controlLabels.isEmpty
        }, "every Settings group exposes a symbol and searchable control labels", &problems)
        expect(SettingsSection.matching("goal").map(\.title) == ["Focus sessions"],
               "searching goal returns Focus sessions", &problems)
        expect(SettingsSection.matching("privacy").map(\.title) == ["Data and privacy"],
               "searching privacy returns Data and privacy", &problems)

        let expectedControls: Set<SettingsControlKey> = [
            .opensOn, .dailyGoal, .breakThreshold, .longAwayCap, .fullPromptAfter,
            .reminders, .automaticSessions, .automaticGap, .rewards, .sessionsPerApp,
            .usageRecording, .appearance, .density, .timelineLabels
        ]
        let listedControls = SettingsSection.allCases.flatMap(\.mutableControlKeys)
        expect(Set(listedControls) == expectedControls,
               "Settings lists exactly the fourteen backed mutable controls", &problems)
        expect(listedControls.count == expectedControls.count,
               "no backed mutable control appears in more than one group", &problems)
        expect(Set(listedControls.map(\.modelKeyPath)).count == expectedControls.count,
               "every mutable control maps to a distinct SettingsModel property", &problems)

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.defaultAppTab = .review
        settings.interfaceDensity = .compact
        settings.appearancePreference = .dark
        settings.showsTimelineLabels = false
        let reloaded = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        expect(reloaded.defaultAppTab == .review,
               "Settings default tab survives reload", &problems)
        expect(reloaded.interfaceDensity == .compact
               && reloaded.interfaceLayout.rowHeight == InterfaceDensity.compact.layout.rowHeight,
               "Settings density survives reload and changes layout metrics", &problems)
        expect(reloaded.appearancePreference == .dark
               && reloaded.preferredColorScheme == .dark,
               "Settings appearance survives reload and resolves the shell colour scheme", &problems)
        expect(!reloaded.showsTimelineLabels,
               "Settings timeline-label choice survives reload", &problems)

        let backupDirectory = scratchDirectory()
        try? FileManager.default.createDirectory(at: backupDirectory,
                                                 withIntermediateDirectories: true)
        let olderBackup = backupDirectory
            .appendingPathComponent("app-usage-v1-backup-1700000000.json")
        let newerBackup = backupDirectory
            .appendingPathComponent("app-usage-v1-backup-1800000000.json")
        try? Data("older".utf8).write(to: olderBackup)
        try? Data("newer".utf8).write(to: newerBackup)
        try? Data("unrelated".utf8).write(
            to: backupDirectory.appendingPathComponent("sessions.json"))
        expect(SettingsDiagnostics.latestLegacyBackup(in: backupDirectory)?
                   .resolvingSymlinksInPath() == newerBackup.resolvingSymlinksInPath(),
               "Data diagnostics rediscover the newest preserved legacy backup after relaunch",
               &problems)
        return problems
    }

    private static func testSettingsDiagnosticLayout() -> [String] {
        var problems: [String] = []
        expect(SettingsReadOnlyRowLayout.trailingValue.usesTrailingValue,
               "scalar diagnostics retain the compact trailing-value layout", &problems)
        expect(!SettingsReadOnlyRowLayout.trailingValue.usesFullWidthValue,
               "scalar diagnostics do not claim the full row", &problems)
        expect(SettingsReadOnlyRowLayout.statusBlock.usesFullWidthValue,
               "Recovery uses a wrapping full-width status layout", &problems)
        expect(!SettingsReadOnlyRowLayout.statusBlock.usesTrailingValue,
               "Recovery never compresses into the trailing scalar column", &problems)
        return problems
    }

    private static func testSettingsPrivacyDisclosure() -> [String] {
        var problems: [String] = []
        let disclosure = SettingsPrivacyDisclosure.current
        expect(!disclosure.appUsageMonitoringCapturesTextInOtherApps,
               "app-usage monitoring never claims to capture text in other apps", &problems)
        expect(disclosure.locallyStoredFocusInputs == [.sessionName, .intent],
               "session names and intent entered in FocusContinuity are disclosed as local data",
               &problems)
        expect(disclosure.storageDetail.contains(
            "App-usage monitoring does not capture text in other apps"),
            "privacy copy states the real app-monitoring boundary", &problems)
        expect(disclosure.storageDetail.contains(
            "Session names and intent entered into FocusContinuity are stored locally"),
            "privacy copy states that FocusContinuity-entered text is stored locally", &problems)
        expect(!disclosure.storageDetail.contains("anything you type"),
               "privacy copy makes no blanket claim about typed text", &problems)
        return problems
    }

    private static func testSharedPanelDensityEnvironment() -> [String] {
        var problems: [String] = []
        let sizes: (comfortable: CGSize, compact: CGSize) = MainActor.assumeIsolated {
            let comfortablePanel = SurfacePanel(showsHeader: false) {
                Text("Ordinary panel content")
            }
            .environment(\.focusInterfaceDensity, InterfaceDensity.comfortable)
            .frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            let comfortableRenderer = ImageRenderer(content: comfortablePanel)
            comfortableRenderer.scale = 1

            let compactPanel = SurfacePanel(showsHeader: false) {
                Text("Ordinary panel content")
            }
            .environment(\.focusInterfaceDensity, InterfaceDensity.compact)
            .frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            let compactRenderer = ImageRenderer(content: compactPanel)
            compactRenderer.scale = 1

            return (comfortableRenderer.nsImage?.size ?? .zero,
                    compactRenderer.nsImage?.size ?? .zero)
        }
        expect(sizes.comfortable.width > 0 && sizes.compact.width > 0,
               "both shared panel density probes render", &problems)
        expect(sizes.compact.height < sizes.comfortable.height,
               "compact density reduces an actual shared SurfacePanel from "
               + "\(sizes.comfortable.height)pt to \(sizes.compact.height)pt", &problems)
        return problems
    }

    private static func testSettingsProductionBreakpoint() -> [String] {
        var problems: [String] = []
        expect(!SettingsLayout.usesSidebar(at: 980),
               "the 980pt production minimum selects the narrow group menu", &problems)
        expect(SettingsLayout.usesSidebar(at: 1_160),
               "the 1160pt comfortable production width selects the sidebar", &problems)
        return problems
    }

    private static func testSettingsAccuracyEpochYear() -> [String] {
        var problems: [String] = []
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let label = SettingsDiagnostics.accuracyEpochLabel(epoch)
        expect(label.contains("2023"),
               "accuracy epoch includes its year, got \(label)", &problems)
        return problems
    }

    private static func testCompactFocusSnapshotStructure() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []

            let light = Snapshotter.narrowFocusSnapshot(scheme: .light)
            let lightRenderer = ImageRenderer(content: light)
            lightRenderer.scale = 1

            let dark = Snapshotter.narrowFocusSnapshot(scheme: .dark)
            let darkRenderer = ImageRenderer(content: dark)
            darkRenderer.scale = 1

            let blankRenderer = ImageRenderer(
                content: Color.white.frame(width: 1_160, height: 780))
            blankRenderer.scale = 1

            expect(snapshotHasTitleStatusBand(lightRenderer.nsImage),
                   "compact light snapshot root contains title and status evidence", &problems)
            expect(snapshotHasTitleStatusBand(darkRenderer.nsImage),
                   "compact dark snapshot root contains title and status evidence", &problems)
            expect(snapshotHasAppMarkAndTabs(lightRenderer.nsImage),
                   "narrow Focus snapshot keeps the app mark and tab labels together",
                   &problems)
            expect(snapshotHasAppMarkAndTabs(darkRenderer.nsImage),
                   "narrow dark Focus snapshot keeps the app mark and tab labels together",
                   &problems)
            expect(!snapshotHasTitleStatusBand(blankRenderer.nsImage),
                   "the structural probe rejects a root with no title/status band", &problems)
            return problems
        }
    }

    /// Task 11 — the gallery and PNG harness share one explicit product-surface
    /// matrix. This catches a return to fixture-centric output, a missing
    /// Settings group, an appearance omission or a dropped responsive shell.
    private static func testSnapshotMatrixCoversEveryMaterialSurface() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let required: [SnapshotScenario] = [
                .focusFirstRun, .focusRunning, .focusPaused, .focusAwaitingDecision,
                .todayHistory, .todayHistoryExpanded, .todayPast,
                .reviewWeek, .reviewMonth,
                .reviewSelectedFirstDay, .reviewSelectedLastDay, .reviewHistorySelection,
                .insightsEnough, .insightsEmpty,
                .awardsEarned, .awardsEmpty,
                .storyDay, .storyWeek, .storyMonth,
                .settingsGeneral, .settingsFocus, .settingsAway, .settingsAutomatic,
                .settingsTracking, .settingsAppearance, .settingsData, .settingsAdvanced,
                .awayQuick, .awayFull, .rewardEarned
            ]

            expect(SnapshotScenario.allCases == required,
                   "snapshot scenarios must equal the approved global surface order",
                   &problems)

            let settingsScenarios = SnapshotScenario.allCases.compactMap(\.settingsSection)
            expect(settingsScenarios == SettingsSection.allCases,
                   "snapshot Settings scenarios must equal every persisted Settings group",
                   &problems)

            let matrix = Set(Snapshotter.matrix)
            let appearances = SnapshotAppearance.allCases
            for scenario in required {
                for appearance in appearances {
                    expect(matrix.contains(where: {
                        $0.scenario == scenario && $0.appearance == appearance
                    }), "\(scenario.rawValue) must render in \(appearance.rawValue)",
                    &problems)
                }
            }

            // Every global tab must own at least one rendered surface, or a
            // whole product area could regress unseen.
            for tab in AppTab.allCases {
                expect(required.contains { $0.tab == tab },
                       "\(tab.rawValue) must have a snapshot scenario", &problems)
            }

            // The selected-day detail is reachable two ways, and both edges of
            // the chart are where clipping and annotation collisions hide.
            let selectionScenarios: [SnapshotScenario] = [
                .reviewSelectedFirstDay, .reviewSelectedLastDay, .reviewHistorySelection
            ]
            for scenario in selectionScenarios {
                expect(required.contains(scenario),
                       "\(scenario.rawValue) must stay in the visual matrix", &problems)
                expect(scenario.tab == .review,
                       "\(scenario.rawValue) must render inside Review", &problems)
            }

            let compactScenarios: Set<SnapshotScenario> = [
                .awayQuick, .awayFull, .rewardEarned
            ]
            let shellScenarios = required.filter { !compactScenarios.contains($0) }
            for scenario in shellScenarios {
                for appearance in appearances {
                    for presentation in [SnapshotPresentation.minimum,
                                         SnapshotPresentation.comfortable] {
                        expect(matrix.contains(SnapshotRender(
                            scenario: scenario,
                            appearance: appearance,
                            presentation: presentation)),
                        "\(scenario.rawValue) must retain the \(presentation.rawValue) shell",
                        &problems)
                    }
                }
            }

            let focusScenarios = Array(required.prefix(4))
            for scenario in focusScenarios {
                for appearance in appearances {
                    expect(matrix.contains(SnapshotRender(
                        scenario: scenario,
                        appearance: appearance,
                        presentation: .popover)),
                    "\(scenario.rawValue) must retain the compact popover",
                    &problems)
                }
            }

            for scenario in compactScenarios {
                for appearance in appearances {
                    expect(matrix.contains(SnapshotRender(
                        scenario: scenario,
                        appearance: appearance,
                        presentation: .compact)),
                    "\(scenario.rawValue) must retain its compact production surface",
                    &problems)
                }
            }

            return problems
        }
    }

    /// Gallery cards stay alive together. Constructing a second root must not
    /// rewrite the first root's computed SettingsModel preferences through a
    /// shared UserDefaults domain, before or during a simultaneous render.
    private static func testSimultaneousSnapshotsKeepIsolatedPreferences() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let minimum = Snapshotter.view(for: SnapshotRender(
                scenario: .settingsAppearance,
                appearance: .light,
                presentation: .minimum))
            let comfortable = Snapshotter.view(for: SnapshotRender(
                scenario: .settingsAppearance,
                appearance: .dark,
                presentation: .comfortable))

            expect(minimum.settings?.appearancePreference == .light,
                   "the first live Gallery card retains its light preference",
                   &problems)
            expect(minimum.settings?.interfaceDensity == .compact,
                   "the first live Gallery card retains Compact density",
                   &problems)
            expect(comfortable.settings?.appearancePreference == .dark,
                   "the second live Gallery card retains its dark preference",
                   &problems)
            expect(comfortable.settings?.interfaceDensity == .comfortable,
                   "the second live Gallery card retains Comfortable density",
                   &problems)

            let renderer = ImageRenderer(content: HStack(spacing: 0) {
                minimum
                comfortable
            })
            renderer.scale = 1
            expect(renderer.nsImage != nil,
                   "the independently configured Gallery cards render simultaneously",
                   &problems)
            expect(minimum.settings?.appearancePreference == .light
                   && minimum.settings?.interfaceDensity == .compact,
                   "simultaneous rendering cannot overwrite the first card's settings",
                   &problems)
            expect(comfortable.settings?.appearancePreference == .dark
                   && comfortable.settings?.interfaceDensity == .comfortable,
                   "simultaneous rendering cannot overwrite the second card's settings",
                   &problems)
            return problems
        }
    }

    /// The official Away cases must exercise the hosted production wrappers,
    /// not an answer grid restyled inside Snapshotter. The quick pointer and
    /// full-screen click-catcher/Later row are observable raster structure.
    private static func testAwaySnapshotsRetainProductionPromptChrome() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let quickRenderer = ImageRenderer(content: Snapshotter.view(for: SnapshotRender(
                scenario: .awayQuick,
                appearance: .light,
                presentation: .compact)))
            quickRenderer.scale = 1
            let fullRenderer = ImageRenderer(content: Snapshotter.view(for: SnapshotRender(
                scenario: .awayFull,
                appearance: .light,
                presentation: .compact)))
            fullRenderer.scale = 1

            guard let quick = snapshotBitmap(quickRenderer.nsImage),
                  let full = snapshotBitmap(fullRenderer.nsImage) else {
                return ["Away production roots did not render"]
            }

            expect(quick.pixelsWide == 300 && (218...224).contains(quick.pixelsHigh),
                   "quick Away includes its 9pt pointer above the 300pt card; got "
                   + "\(quick.pixelsWide)x\(quick.pixelsHigh)", &problems)
            expect(snapshotOpaqueColumns(quick, row: 0) <= 24,
                   "quick Away begins with the narrow production pointer",
                   &problems)

            expect(full.pixelsWide == 760 && full.pixelsHigh == 620,
                   "full Away uses its safe full-prompt host; got "
                   + "\(full.pixelsWide)x\(full.pixelsHigh)", &problems)
            expect((0.10...0.30).contains(snapshotAlpha(full, x: 4, y: 4)),
                   "full Away retains the dimmed outside click-catcher",
                   &problems)
            expect(snapshotContrast(full, x: 570..<620, y: 425..<455) > 0.05,
                   "full Away retains visible trailing Later/Escape chrome",
                   &problems)
            return problems
        }
    }

    @MainActor private static func snapshotBitmap(_ image: NSImage?) -> NSBitmapImageRep? {
        guard let image, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    @MainActor private static func snapshotAlpha(
        _ bitmap: NSBitmapImageRep,
        x: Int,
        y: Int
    ) -> Double {
        guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh,
              let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            return 0
        }
        return Double(colour.alphaComponent)
    }

    @MainActor private static func snapshotOpaqueColumns(
        _ bitmap: NSBitmapImageRep,
        row: Int
    ) -> Int {
        (0..<bitmap.pixelsWide).reduce(into: 0) { count, column in
            if snapshotAlpha(bitmap, x: column, y: row) > 0.05 { count += 1 }
        }
    }

    @MainActor private static func snapshotContrast(
        _ bitmap: NSBitmapImageRep,
        x: Range<Int>,
        y: Range<Int>
    ) -> Double {
        var low = 1.0
        var high = 0.0
        for row in y where row >= 0 && row < bitmap.pixelsHigh {
            for column in x where column >= 0 && column < bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: column, y: row)?
                    .usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * Double(colour.redComponent)
                    + 0.7152 * Double(colour.greenComponent)
                    + 0.0722 * Double(colour.blueComponent)
                low = min(low, luminance)
                high = max(high, luminance)
            }
        }
        return high - low
    }

    @MainActor private static func snapshotHasTitleStatusBand(_ image: NSImage?) -> Bool {
        guard let image, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide >= 720, bitmap.pixelsHigh >= 120 else { return false }

        func contrast(x: Range<Int>, y: Range<Int>) -> Double {
            var low = 1.0
            var high = 0.0
            for row in stride(from: y.lowerBound, to: y.upperBound, by: 2) {
                for column in stride(from: x.lowerBound, to: x.upperBound, by: 2) {
                    guard let colour = bitmap.colorAt(x: column, y: row)?
                        .usingColorSpace(.sRGB) else { continue }
                    let luminance = 0.2126 * Double(colour.redComponent)
                        + 0.7152 * Double(colour.greenComponent)
                        + 0.0722 * Double(colour.blueComponent)
                    low = min(low, luminance)
                    high = max(high, luminance)
                }
            }
            return high - low
        }

        // NSBitmapImageRep's row zero is the rendered top. These disjoint
        // regions cover the left title/app mark and right live-status text;
        // the tab rail is centred lower down and cannot satisfy either probe.
        let bandHeight = min(60, bitmap.pixelsHigh)
        let sideWidth = min(360, bitmap.pixelsWide / 2)
        let titleContrast = contrast(x: 10..<sideWidth, y: 0..<bandHeight)
        let statusContrast = contrast(
            x: (bitmap.pixelsWide - sideWidth)..<(bitmap.pixelsWide - 10),
            y: 0..<bandHeight)
        return titleContrast > 0.2 && statusContrast > 0.08
    }

    @MainActor private static func snapshotHasAppMarkAndTabs(_ image: NSImage?) -> Bool {
        guard let image, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide == 980, bitmap.pixelsHigh >= 680 else { return false }

        func contrast(x: Range<Int>, y: Range<Int>) -> Double {
            var low = 1.0
            var high = 0.0
            for row in stride(from: y.lowerBound, to: y.upperBound, by: 2) {
                for column in stride(from: x.lowerBound, to: x.upperBound, by: 2) {
                    guard let colour = bitmap.colorAt(x: column, y: row)?
                        .usingColorSpace(.sRGB) else { continue }
                    let luminance = 0.2126 * Double(colour.redComponent)
                        + 0.7152 * Double(colour.greenComponent)
                        + 0.0722 * Double(colour.blueComponent)
                    low = min(low, luminance)
                    high = max(high, luminance)
                }
            }
            return high - low
        }

        // The app mark occupies the reserved leading inset; the tab labels are
        // centred in the same 60pt chrome band at the production minimum.
        return contrast(x: 68..<112, y: 0..<60) > 0.08
            && contrast(x: 300..<700, y: 0..<60) > 0.08
    }

    /// The visual foundation keeps Compact practical rather than cramped and
    /// resolves semantic signals independently of the current system appearance.
    private static func testWarmPrecisionDesignTokensAndDensity() -> [String] {
        var problems: [String] = []
        expect(InterfaceDensity.compact.layout.rowHeight >= 28,
               "compact targets remain practical", &problems)
        expect(InterfaceDensity.compact.layout.rowHeight < InterfaceDensity.comfortable.layout.rowHeight,
               "compact density is observably denser", &problems)
        expect(Tokens.Colour.resolved(.focus, dark: false).hex == 0x007AFF,
               "light focus token is Apple's system blue", &problems)
        expect(Tokens.Colour.resolved(.focus, dark: true).hex == 0x0A84FF,
               "dark focus token is the dark system blue", &problems)
        expect(Tokens.Colour.resolved(.attention, dark: true).hex == 0xFF9F0A,
               "dark attention token remains semantic amber", &problems)
        let lightOnFocus = Tokens.Colour.resolved(.onFocus, dark: false).hex
        let darkOnFocus = Tokens.Colour.resolved(.onFocus, dark: true).hex
        expect(lightOnFocus == 0x0F1115 && darkOnFocus == 0x0F1115,
               "on-focus foreground remains near-black in both appearances", &problems)
        let lightContrast = contrastRatio(lightOnFocus, 0x007AFF)
        expect(lightContrast >= 4.5,
               "on-focus foreground has at least 4.5:1 contrast on light focus; got "
               + String(format: "%.2f:1", lightContrast), &problems)
        return problems
    }

    /// Deep links and commands share one navigation model. A wrong branch here
    /// would leave the selected tab and the requested day disagreeing.
    private static func testMainWindowRoutesAndCommands() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let navigation = MainWindowModel()
            let calendar = Calendar.current
            let yesterday = base.addingTimeInterval(-24 * 3_600)

            navigation.open(tab: .review)
            expect(navigation.selectedTab == .review,
                   "review route selects Review", &problems)
            navigation.openToday(date: yesterday)
            expect(navigation.selectedTab == .today && navigation.requestedDate == yesterday,
                   "day links route into Today", &problems)
            navigation.openSettings()
            expect(navigation.selectedTab == .settings,
                   "command-comma routes to Settings", &problems)

            // Selecting a day in Review is inspection, not navigation: only the
            // explicit action may move the user to another tab.
            let reviewNavigation = MainWindowModel(selectedTab: .review)
            reviewNavigation.selectReviewDay(yesterday, calendar: calendar)
            expect(reviewNavigation.selectedTab == .review,
                   "selecting a Review day keeps Review selected", &problems)
            expect(calendar.isDate(reviewNavigation.reviewSelectedDate ?? base,
                                   inSameDayAs: yesterday),
                   "Review stores the literal selected local day", &problems)
            expect(reviewNavigation.requestedDate == nil,
                   "Review selection does not change Today scope", &problems)
            reviewNavigation.openSelectedReviewDayInToday()
            expect(reviewNavigation.selectedTab == .today
                       && calendar.isDate(reviewNavigation.requestedDate ?? base,
                                          inSameDayAs: yesterday),
                   "only the explicit Review action opens the selected day in Today", &problems)
            reviewNavigation.clearReviewDay()
            expect(reviewNavigation.reviewSelectedDate == nil,
                   "closing the Review detail clears its selected day", &problems)
            return problems
        }
    }

    /// The unified chrome is a pure layout contract: contextual title/status
    /// share the tab row, native traffic lights have reserved space, and the
    /// rail does not rely on AppKit's conspicuous focus outline.
    private static func testUnifiedWindowChrome() -> [String] {
        var problems: [String] = []
        let context = MainWindowChrome.context(
            tab: .today,
            state: .running,
            threadElapsed: 21 * 60,
            todayTotal: 2 * 3_600
        )

        expect(context.title == "Today", "chrome exposes the selected tab title", &problems)
        expect(context.subtitle == "FocusContinuity",
               "chrome keeps the app name beside the tabs", &problems)
        expect(context.status == "Focus active · 21m",
               "chrome keeps the literal live status beside the tabs", &problems)
        expect(MainWindowChrome.trafficLightClearance >= 68,
               "chrome reserves room for native traffic lights", &problems)
        expect(MainWindowChrome.usesNativeFocusRing == false,
               "tab rail does not draw the native blue focus outline", &problems)
        return problems
    }

    private static func testNativeChromePresentation() -> [String] {
        var problems: [String] = []
        expect(!TabRailPresentation.usesOuterSurface,
               "global tabs do not sit inside a second enclosing rail", &problems)
        expect(!TabRailPresentation.unselectedUsesBorder,
               "unselected tabs remain quiet individual controls", &problems)
        expect(TabRailPresentation.showsLabelsInIconFallback,
               "icon fallback keeps literal tab labels enabled", &problems)
        expect(MainWindowChrome.appMarkFallbackSymbol == "target"
                   && MainWindowChrome.appMarkSize == 24,
               "window chrome has a compact deterministic app-mark fallback", &problems)
        expect(MainWindowChrome.appMarkPresentation(hasBundledIcon: true) == .bundledIcon
                   && MainWindowChrome.appMarkPresentation(hasBundledIcon: false) == .targetFallback,
               "window chrome exposes bundled-icon and target-fallback branches", &problems)
        expect(MainWindowChrome.trafficLightClearance >= 68,
               "adding the app mark preserves traffic-light clearance", &problems)
        return problems
    }

    /// Accessibility must expose the same literal navigation and tracked-time
    /// evidence as the visible UI. This exercises the production label builders
    /// and the exact Escape action wired to Today rather than inspecting source.
    private static func testAccessibleNavigationAndChartSummaries() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []

            let tabLabels = AppTab.allCases.map {
                $0.accessibilityLabel(isSelected: $0 == .review)
            }
            expect(tabLabels.contains("Review, selected, Command 4"),
                   "the selected tab label announces selection and its command", &problems)
            expect(tabLabels.contains("Focus, not selected, Command 1"),
                   "unselected tab labels announce their state", &problems)
            expect(Set(AppTab.allCases.map(\.commandNumber)) == Set(1...7),
                   "Command 1 through Command 7 map uniquely to the seven tabs", &problems)
            expect(AppTab.review.moved(by: -1) == .story
                       && AppTab.review.moved(by: 1) == .insights,
                   "left and right move from the focused Review tab", &problems)

            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_AU")
            guard let sydney = TimeZone(identifier: "Australia/Sydney") else {
                return problems + ["could not construct the Sydney time zone"]
            }
            calendar.timeZone = sydney
            guard let saturday = calendar.date(from: DateComponents(
                year: 2026, month: 8, day: 29, hour: 12)) else {
                return problems + ["could not construct the chart-summary fixture date"]
            }
            let point = PeriodChartPoint(date: saturday, seconds: 5 * 3_600 + 10 * 60)
            expect(point.accessibilitySummary(calendar: calendar)
                       == "Saturday 29 August, 5 hours 10 minutes tracked",
                   "period points expose a literal date and tracked duration; got "
                       + "'\(point.accessibilitySummary(calendar: calendar))'", &problems)

            expect(AccessibilityMetrics.minimumTargetSize >= 28,
                   "compact controls retain a practical 28pt target", &problems)
            expect(InterfaceDensity.compact.layout.rowHeight
                       >= AccessibilityMetrics.minimumTargetSize,
                   "compact rows remain at least as tall as the minimum target", &problems)

            let clock = Clock(base)
            let store = SessionStore(engine: makeEngine(clock), now: { clock.value })
            store.dayOffset = 1
            store.selectedSegment = TimelineSegment(
                id: UUID(), bundleID: "com.example.editor", appName: "Editor",
                start: base.addingTimeInterval(-3_600), end: base, colorIndex: 0)
            let selectedDay = store.selectedDay
            TodayView.handleEscape(in: store)
            expect(store.selectedSegment == nil && store.todayInspector == nil,
                   "Escape clears the Today inspector selection", &problems)
            expect(calendar.isDate(store.selectedDay, inSameDayAs: selectedDay),
                   "Escape preserves the selected calendar day", &problems)
            return problems
        }
    }

    private static func testHistoryDateControlsMeetTarget() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let start = base
            let end = base.addingTimeInterval(24 * 3_600)
            let range = start...end
            let selected = start.addingTimeInterval(12 * 3_600)

            @MainActor func probe(_ label: String, initial: Date) -> (
                frame: NSRect, accessibility: NSRect, label: String?, valueChanged: Bool,
                minimum: Date?, maximum: Date?
            )? {
                let date = MutableDate(initial)
                let binding = Binding<Date>(get: { date.value }, set: { date.value = $0 })
                let hosting = NSHostingView(rootView: HistoryDateControl(
                    label: label, selection: binding, range: range))
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                let window = NSWindow(contentRect: hosting.frame,
                                      styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                guard let picker = embeddedDatePicker(in: hosting) else { return nil }
                let frame = picker.frame
                let accessibility = picker.accessibilityFrame()
                let accessibilityLabel = picker.accessibilityLabel()
                let minimum = picker.minDate
                let maximum = picker.maxDate
                picker.dateValue = selected
                picker.sendAction(picker.action, to: picker.target)
                let changed = Calendar.current.isDate(date.value, inSameDayAs: selected)
                window.contentView = nil
                return (frame, accessibility, accessibilityLabel, changed, minimum, maximum)
            }

            guard let from = probe("From", initial: start),
                  let to = probe("To", initial: end) else {
                return ["could not locate both embedded native History date controls"]
            }
            expect(from.frame.height >= 28 && to.frame.height >= 28,
                   "embedded NSDatePicker frames are at least 28pt; got "
                       + "\(from.frame.height)pt and \(to.frame.height)pt", &problems)
            expect(from.accessibility.height >= 28 && to.accessibility.height >= 28,
                   "embedded NSDatePicker accessibility frames are at least 28pt; got "
                       + "\(from.accessibility.height)pt and \(to.accessibility.height)pt",
                   &problems)
            expect(from.label == "From date" && to.label == "To date",
                   "embedded native targets retain explicit From/To accessibility labels",
                   &problems)
            expect(from.valueChanged && to.valueChanged,
                   "native date actions write through both production Bindings", &problems)
            expect(from.minimum == start && from.maximum == end
                       && to.minimum == start && to.maximum == end,
                   "native controls preserve the exact History date range", &problems)
            return problems
        }
    }

    @MainActor private static func embeddedDatePicker(in view: NSView) -> NSDatePicker? {
        if let picker = view as? NSDatePicker { return picker }
        for child in view.subviews {
            if let picker = embeddedDatePicker(in: child) { return picker }
        }
        return nil
    }

    private static func testPeriodAppRowsExposeDailyAccessibility() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_AU")
            guard let sydney = TimeZone(identifier: "Australia/Sydney") else {
                return ["could not construct the Sydney time zone"]
            }
            calendar.timeZone = sydney
            guard let firstDay = calendar.date(from: DateComponents(
                year: 2023, month: 11, day: 14, hour: 12)),
                  let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay) else {
                return ["could not construct the period app-row fixture dates"]
            }
            func entry(_ day: Date, seconds: TimeInterval) -> LogEntry {
                LogEntry(session: AppSession(
                    bundleID: "com.example.editor", appName: "Editor",
                    start: day, end: day.addingTimeInterval(seconds),
                    attended: seconds, visits: 1),
                         day: calendar.startOfDay(for: day))
            }
            let group = LogAppGroup(
                bundleID: "com.example.editor", appName: "Editor",
                total: 90 * 60, visits: 2,
                sessions: [entry(firstDay, seconds: 60 * 60),
                           entry(secondDay, seconds: 30 * 60)],
                share: 0.75)

            let collapsed = PeriodAppRowButton(
                group: group, rank: 0, expanded: false, onToggle: {})
            let renderer = ImageRenderer(content: collapsed.frame(width: 520).fixedSize(
                horizontal: false, vertical: true))
            renderer.scale = 1
            let size = renderer.nsImage?.size ?? .zero
            expect(size.width > 0 && size.height >= 28,
                   "the real expand/collapse Button is at least 28pt; got \(size)", &problems)
            expect(collapsed.accessibilityLabelText
                       == "Editor, 1 hour 30 min, 2 sessions, 75 percent of tracked time",
                   "the app-row action states its literal measure", &problems)
            expect(collapsed.accessibilityValueText == "Collapsed",
                   "the closed app row announces Collapsed", &problems)
            let expanded = PeriodAppRowButton(
                group: group, rank: 0, expanded: true, onToggle: {})
            expect(expanded.accessibilityValueText == "Expanded",
                   "the open app row announces Expanded", &problems)

            let summaries = DailyStrip.accessibilitySummaries(
                [(day: firstDay, seconds: 60 * 60),
                 (day: secondDay, seconds: 30 * 60)],
                calendar: calendar)
            expect(summaries == [
                "Tuesday 14 November, 1 hour tracked",
                "Wednesday 15 November, 30 minutes tracked"
            ], "every expanded day retains its literal tracked summary; got \(summaries)",
               &problems)

            let clock = Clock(base)
            let store = SessionStore(engine: makeEngine(clock), now: { clock.value })
            store.toggleExpanded(group.bundleID)
            expect(store.expandedApps.contains(group.bundleID),
                   "the keyboard action expands the requested app", &problems)
            store.toggleExpanded(group.bundleID)
            expect(!store.expandedApps.contains(group.bundleID),
                   "the same action collapses the requested app", &problems)
            return problems
        }
    }

    /// Today owns one canonical calendar day independently of global tab
    /// navigation. Its inspector is presentation over the existing selection
    /// APIs: clearing that transient evidence must never move the selected day.
    private static func testTodaySurfaceScopeAndInspector() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(base)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: clock.value)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                return ["could not build a past-day Today fixture"]
            }

            let archive = makeArchive(clock)
            archive.append(SessionRecord(name: "Parser", workType: .deepWork,
                                         start: yesterday.addingTimeInterval(9 * 3_600),
                                         end: yesterday.addingTimeInterval(10.5 * 3_600),
                                         workSeconds: 90 * 60))
            archive.append(SessionRecord(name: "Review", workType: .meetings,
                                         start: yesterday.addingTimeInterval(14 * 3_600),
                                         end: yesterday.addingTimeInterval(14 * 3_600 + 55 * 60),
                                         workSeconds: 55 * 60))

            let usage = AppUsageArchive(directory: scratchDirectory(), now: { clock.value })
            usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                         start: yesterday.addingTimeInterval(9 * 3_600),
                                         end: yesterday.addingTimeInterval(10.5 * 3_600)))
            usage.record(AppUsageSession(bundleID: "com.example.browser", appName: "Browser",
                                         start: yesterday.addingTimeInterval(14 * 3_600),
                                         end: yesterday.addingTimeInterval(14 * 3_600 + 55 * 60)))

            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.setDashboardVisible(true)
            store.selectDay(offset: 1)

            let navigation = MainWindowModel(selectedTab: .today)
            navigation.select(.review)
            navigation.select(.today)
            expect(store.dayOffset == 1,
                   "global tab changes preserve the historical day", &problems)

            let presentation = TodayPresentation(
                day: store.selectedDay,
                focused: store.focusedForSelectedDay,
                sessions: store.sessionsForSelectedDay,
                dayOffset: store.dayOffset)
            expect(presentation.title == "Yesterday",
                   "the past-day title remains day-scoped", &problems)
            expect(presentation.subtitle == "Tuesday 14 November · 2h 25m focused · 2 sessions",
                   "the subtitle uses canonical focused and session figures; got "
                    + "'\(presentation.subtitle)'", &problems)
            expect(presentation.showsTodayReset,
                   "history exposes an explicit Today reset", &problems)

            guard let first = store.timelineSegments.first,
                  let layout = store.timelineLayout,
                  let fraction = layout.fraction(for: first.start.addingTimeInterval(1)) else {
                return problems + ["past-day timeline did not provide a selectable segment"]
            }
            store.selectTimeline(at: fraction)
            let appInspector = store.todayInspector
            expect(appInspector?.kind == .app,
                   "timeline selection opens an app inspector", &problems)
            expect(appInspector?.title == first.appName
                       && appInspector?.tracked == first.seconds,
                   "the app inspector uses the selected canonical segment", &problems)

            if case .session(let session)? = store.daySessions.first(where: {
                if case .session = $0 { return true }
                return false
            }) {
                store.selectTodaySession(session)
                expect(store.todayInspector?.kind == .session,
                       "session selection opens a session inspector", &problems)
                expect(store.selectedSegment == nil,
                       "session inspection replaces the prior app inspection", &problems)
                store.selectTodayTimeline(at: fraction)
                expect(store.todayInspector?.kind == .app,
                       "ribbon selection replaces the session inspector with app evidence",
                       &problems)
                expect(store.selectedSession == nil && store.selectedSegment != nil,
                       "ribbon selection leaves exactly one app backing selection", &problems)
                let backingSelections = [store.selectedSession != nil,
                                         store.selectedSegment != nil].filter { $0 }.count
                expect(backingSelections == 1,
                       "Today retains exactly one backing inspector selection", &problems)
                expect(store.dayOffset == 1,
                       "session-to-ribbon inspection preserves the historical day", &problems)
            } else {
                problems.append("past-day fixture did not provide a selectable session")
            }

            store.clearTodaySelection()
            expect(store.todayInspector == nil && store.selectedSegment == nil,
                   "Escape-style clearing empties timeline inspector data", &problems)
            expect(store.dayOffset == 1,
                   "clearing inspector selection preserves the historical day", &problems)

            store.goToToday()
            expect(store.dayOffset == 0,
                   "the explicit Today action resets the day", &problems)
            expect(!TodayPresentation(day: store.selectedDay,
                                      focused: store.todayTotal,
                                      sessions: store.sessionsToday,
                                      dayOffset: store.dayOffset).showsTodayReset,
                   "the reset action is hidden on the real current day", &problems)
            return problems
        }
    }

    /// Review compares the authoritative tracked series rather than focus
    /// composition. History joins those usage days to archive evidence once,
    /// orders them newest first, and combines every requested filter.
    /// An award may only state what the local record proves. An unearned one
    /// shows real progress rather than an exhortation, and a run of goal days
    /// is broken by a calendar gap, not merely by a lower figure.
    private static func testAwardsAreEvidenceBacked() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func offset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: day) ?? day
        }

        // Seven consecutive days at goal, then a gap, then two more.
        var credit: [Date: TimeInterval] = [:]
        for index in 0..<7 { credit[offset(index)] = 4 * 3_600 }
        credit[offset(8)] = 4 * 3_600
        credit[offset(9)] = 4 * 3_600
        // A day below the goal must not extend a run.
        credit[offset(7)] = 30 * 60

        var facts = AwardFacts(goal: 4 * 3_600,
                               goalCreditByDay: credit,
                               longestStretch: (95 * 60, offset(2)),
                               activeDays: 22,
                               totalFocused: 62 * 3_600 + 40 * 60,
                               currentStreak: 12,
                               bestStreak: 14)

        let run = Awards.longestGoalRun(facts, calendar: calendar)
        expect(run.length == 7, "the longest run is the seven consecutive days, got \(run.length)",
               &problems)
        expect(run.start.map { calendar.isDate($0, inSameDayAs: offset(0)) } == true
                   && run.end.map { calendar.isDate($0, inSameDayAs: offset(6)) } == true,
               "the run reports the literal days that bound it", &problems)

        let awards = Awards.all(from: facts, calendar: calendar)
        expect(awards.count == 4, "four awards are offered", &problems)
        expect(Set(awards.map(\.id)).count == 4, "each award has its own identity", &problems)

        guard let goalRun = awards.first(where: { $0.id == "goal-run" }),
              let stretch = awards.first(where: { $0.id == "longest-stretch" }),
              let active = awards.first(where: { $0.id == "active-days" }),
              let hours = awards.first(where: { $0.id == "focused-hours" }) else {
            return problems + ["every award must be present"]
        }
        expect(goalRun.isEarned, "seven days at goal earns the run award", &problems)
        expect(stretch.isEarned && stretch.detail.contains("1h 35m"),
               "the longest stretch states its own duration, got “\(stretch.detail)”", &problems)
        expect(!active.isEarned && active.detail == "22 so far",
               "an unearned award states real progress, got “\(active.detail)”", &problems)
        expect(!hours.isEarned && hours.detail.contains("62h 40m"),
               "progress toward hours is the exact recorded total, got “\(hours.detail)”", &problems)
        expect(awards.allSatisfy { !$0.method.isEmpty },
               "every award can explain what it measured", &problems)

        // No goal set: the goal award is withheld rather than judged.
        facts.goal = 0
        let withoutGoal = Awards.all(from: facts, calendar: calendar)
        expect(withoutGoal.first(where: { $0.id == "goal-run" })?.isEarned == false,
               "no goal means no goal award", &problems)
        expect(Awards.longestGoalRun(facts, calendar: calendar) == Awards.GoalRun.none,
               "a run cannot be judged without a goal", &problems)

        // An empty record earns nothing and still explains itself.
        let empty = Awards.all(from: AwardFacts(), calendar: calendar)
        expect(empty.allSatisfy { !$0.isEarned },
               "an empty record earns nothing", &problems)
        expect(empty.first(where: { $0.id == "longest-stretch" })?.detail
                   == "No focus session recorded yet",
               "an absent stretch says so plainly", &problems)
        return problems
    }

    /// An Insight card states its conclusion first and keeps its method behind
    /// a literal disclosure. Settings keeps the sidebar only while it fits.
    private static func testInsightAndSettingsPresentation() -> [String] {
        var problems: [String] = []
        let insight = Insight(id: "pace",
                              headline: "10m behind your usual pace",
                              detail: "1h 15m focused-active today",
                              symbolName: "gauge")
        let presentation = InsightPresentation(title: "Pace", insight: insight)
        expect(presentation.disclosureLabel == "How this is calculated",
               "Insights keep methodology behind a literal disclosure", &problems)
        expect(presentation.title == "Pace" && presentation.headline == insight.headline,
               "the card leads with the finding it was given", &problems)
        expect(presentation.provenance == insight.detail,
               "provenance is the insight's own evidence, never invented", &problems)

        expect(SettingsLayout.usesSidebar(at: 1_080),
               "Settings uses the native-like sidebar at the comfortable threshold", &problems)
        expect(!SettingsLayout.usesSidebar(at: 1_079),
               "Settings switches before its sidebar becomes cramped", &problems)
        expect(!SettingsLayout.usesSidebar(at: 980),
               "the production minimum uses the compact group menu", &problems)
        expect(SettingsLayout.detailMeasure == 720,
               "Settings controls retain a readable measure", &problems)
        return problems
    }

    /// Today reads in one order: what day, what qualifies it, the ribbon, the
    /// thing selected in it, supporting groups, then the recap. Focus refuses to
    /// become a report at any state. The recap's narrative shows canonical
    /// summary sentences without leaking their emphasis markers.
    private static func testDayAndFocusHierarchy() -> [String] {
        var problems: [String] = []

        expect(DaySurfaceOrder.visible(hasQualification: true, hasSelection: true) == [
            .header, .qualification, .recap, .timeline, .selectedDetail, .supportingGroups
        ], "Today qualifies before the recap, then answers the day before its chronology", &problems)

        let closed = DayRecapDisclosurePresentation(isExpanded: false)
        expect(closed.chevronSystemName == "chevron.right"
                   && closed.accessibilityLabel == "Show more about this day"
                   && closed.accessibilityValue == "Collapsed",
               "the recap disclosure exposes one full-row collapsed action", &problems)
        let open = DayRecapDisclosurePresentation(isExpanded: true)
        expect(open.chevronSystemName == "chevron.down"
                   && open.accessibilityLabel == "Hide more about this day"
                   && open.accessibilityValue == "Expanded",
               "the recap disclosure exposes one full-row expanded action", &problems)
        expect(DaySurfaceOrder.visible(hasQualification: false, hasSelection: false) == [
            .header, .recap, .timeline, .supportingGroups
        ], "an unqualified day with no selection shows neither placeholder", &problems)
        expect(DaySurfaceOrder.visible(hasQualification: false, hasSelection: true) == [
            .header, .recap, .timeline, .selectedDetail, .supportingGroups
        ], "inspection stays directly beneath the ribbon it came from", &problems)

        expect(FocusSurfaceLayout.operationalMeasure == 760,
               "Focus keeps a deliberate operational measure", &problems)
        for state in [SessionState.idle, .running, .paused(reason: .manual),
                      .awaitingUserDecision(away: 600, lastApp: "Editor")] {
            expect(!FocusSurfaceLayout.permitsSupportingReport(state: state),
                   "Focus does not become a dashboard in \(state)", &problems)
        }

        let narrative = DayRecapNarrative(sentences: ["Tracked **5h 10m**",
                                                      "Second verified fact"])
        expect(narrative.lead == "Tracked 5h 10m" && narrative.details == ["Second verified fact"],
               "Today recap exposes one summary fact before its supporting disclosure",
               &problems)
        expect(!(narrative.lead ?? "").contains("**"),
               "Today recap never renders SummaryText emphasis markers literally", &problems)
        expect(narrative.details.allSatisfy { !$0.contains("**") },
               "disclosed sentences drop their emphasis markers too", &problems)

        let empty = DayRecapNarrative(sentences: [])
        expect(empty.lead == nil && empty.details.isEmpty,
               "a day with no summary sentences renders no narrative", &problems)

        // The value type is only useful if the store actually publishes
        // sentences for a day with evidence.
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.setDashboardVisible(true)
            store.refresh()
            let live = DayRecapNarrative(sentences: store.summarySentences)
            expect(live.lead != nil,
                   "a day with recorded evidence publishes a recap narrative", &problems)
            expect(!(live.lead ?? "**").contains("**"),
                   "the published narrative is plain text", &problems)
        }
        return problems
    }

    /// Review is a sequence, not a pile: the period answer precedes its trend,
    /// and a selected day is explained directly beneath the trend that produced
    /// it. Only the named action may leave the tab.
    private static func testReviewContentHierarchy() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let yesterday = base.addingTimeInterval(-24 * 3_600)

            expect(ReviewContentOrder.visible(selectedDay: nil) == [
                .periodNavigation, .summary, .trend, .breakdowns, .evidenceLists
            ], "Review omits selected detail until a day is chosen", &problems)
            expect(Array(ReviewContentOrder.visible(selectedDay: yesterday).prefix(4)) == [
                .periodNavigation, .summary, .trend, .selectedDetail
            ], "Review explains the selected day directly after its trend", &problems)
            expect(ReviewContentOrder.visible(selectedDay: yesterday).count
                       == ReviewContentOrder.allCases.count,
                   "a selected day adds its detail without dropping other evidence", &problems)

            // Only the explicit action changes tabs. Selecting, clearing, and an
            // action with nothing selected all leave the user in Review.
            let navigation = MainWindowModel(selectedTab: .review)
            navigation.selectReviewDay(yesterday, calendar: calendar)
            expect(navigation.selectedTab == .review,
                   "selecting a day does not leave Review", &problems)
            navigation.clearReviewDay()
            expect(navigation.selectedTab == .review,
                   "closing the detail does not leave Review", &problems)
            navigation.openSelectedReviewDayInToday()
            expect(navigation.selectedTab == .review && navigation.requestedDate == nil,
                   "the Today action does nothing while no day is selected", &problems)
            navigation.selectReviewDay(yesterday, calendar: calendar)
            navigation.openSelectedReviewDayInToday()
            expect(navigation.selectedTab == .today,
                   "the named action is the one route out of Review", &problems)
            return problems
        }
    }

    /// The History range is one compact summary control, and the table states
    /// its measures once in a header rather than on every row.
    private static func testHistoryRangeAndTableAnatomy() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        guard let startDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)),
              let endDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30)),
              let earlier = calendar.date(from: DateComponents(year: 2025, month: 12, day: 28))
        else {
            return ["could not build History range fixture dates"]
        }

        // Endpoints arrive reversed; the summary sorts them for display without
        // rewriting the stored filter.
        let range = HistoryRangePresentation(start: endDate, end: startDate, calendar: calendar)
        expect(range.label == "12 Aug – 30 Aug 2026",
               "History range label sorts displayed endpoints, got “\(range.label)”", &problems)
        expect(range.accessibilityLabel.contains("from Wednesday 12 August 2026"),
               "History range exposes its literal first endpoint, got “\(range.accessibilityLabel)”",
               &problems)
        expect(range.accessibilityLabel.contains("to Sunday 30 August 2026"),
               "History range exposes its literal last endpoint, got “\(range.accessibilityLabel)”",
               &problems)

        let crossYear = HistoryRangePresentation(start: earlier, end: endDate, calendar: calendar)
        expect(crossYear.label == "28 Dec 2025 – 30 Aug 2026",
               "a range spanning two years names both, got “\(crossYear.label)”", &problems)

        let oneDay = HistoryRangePresentation(start: endDate, end: endDate, calendar: calendar)
        expect(oneDay.label == "30 Aug 2026",
               "a single-day range reads as one date, got “\(oneDay.label)”", &problems)

        expect(HistoryTableLayout.trackedWidth >= 76 && HistoryTableLayout.focusedWidth >= 76
                   && HistoryTableLayout.sessionWidth >= 60,
               "History numeric columns remain scanable", &problems)
        return problems
    }

    /// A History row is a disclosure, not a route. Its open affordance must
    /// point down and its detail must share the row's visual surface instead of
    /// appearing as an unrelated card beneath it.
    private static func testHistoryDisclosurePresentation() -> [String] {
        var problems: [String] = []
        let closed = HistoryDayDisclosurePresentation(isExpanded: false)
        expect(closed.chevronSystemName == "chevron.right" && !closed.usesJoinedSurface,
               "a closed History day remains a compact disclosure row", &problems)

        let open = HistoryDayDisclosurePresentation(isExpanded: true)
        expect(open.chevronSystemName == "chevron.down" && open.usesJoinedSurface,
               "an open History day points down and joins its detail to the row", &problems)
        return problems
    }

    /// A bar drawn at the plot edge is a bar the user cannot read. The domain
    /// reserves one whole calendar day on each side — calendar arithmetic, not
    /// 86,400 seconds, so a daylight-saving day is padded correctly too.
    private static func testPeriodChartLayout() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        guard let first = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)),
              let last = calendar.date(byAdding: .day, value: 6, to: first),
              let expectedLower = calendar.date(byAdding: .day, value: -1, to: first),
              let expectedUpper = calendar.date(byAdding: .day, value: 1, to: last) else {
            return ["could not build chart domain fixture dates"]
        }
        let domain = PeriodChartLayout.domain(for: [
            PeriodChartPoint(date: first, seconds: 60),
            PeriodChartPoint(date: last, seconds: 3_600)
        ], calendar: calendar)
        expect(domain.lowerBound <= expectedLower,
               "chart reserves a full leading bar width", &problems)
        expect(domain.upperBound >= expectedUpper,
               "chart reserves a full trailing bar width", &problems)
        // A daily bar fills the cell from its day to the next, so the bound must
        // clear the final bar's own cell before the padding exists at all.
        if let clearOfFinalBar = calendar.date(byAdding: .day, value: 2, to: last) {
            expect(domain.upperBound >= clearOfFinalBar,
                   "the final bar is followed by an empty bar-width, not the frame",
                   &problems)
        }

        // A 23-hour day still gets exactly one calendar day of padding, which a
        // fixed 86,400-second offset cannot produce.
        var sydney = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: "Australia/Sydney") { sydney.timeZone = zone }
        if let dstDay = sydney.date(from: DateComponents(year: 2026, month: 10, day: 4)),
           let dstLower = sydney.date(byAdding: .day, value: -1, to: dstDay),
           let dstUpper = sydney.date(byAdding: .day, value: 1, to: dstDay) {
            let dstDomain = PeriodChartLayout.domain(
                for: [PeriodChartPoint(date: dstDay, seconds: 600)], calendar: sydney)
            expect(dstDomain.lowerBound == dstLower,
                   "leading padding is one calendar day across a daylight-saving change",
                   &problems)
            expect(sydney.dateComponents([.day], from: dstDay, to: dstDomain.upperBound).day == 2,
                   "trailing padding clears the final bar's own day across a change",
                   &problems)
            expect(dstUpper.timeIntervalSince(dstDay) != 86_400,
                   "the daylight-saving fixture actually exercises a short day", &problems)
        } else {
            problems.append("could not build a daylight-saving fixture")
        }

        let empty = PeriodChartLayout.domain(for: [], calendar: calendar)
        expect(empty.lowerBound <= empty.upperBound,
               "an empty period still yields a valid domain", &problems)

        // The vertical scale starts at zero and rounds up to a readable step, so
        // the tallest bar and the average rule both stay inside the plot.
        expectClose(PeriodChartLayout.yMaximumMinutes(
            for: [PeriodChartPoint(date: first, seconds: 47 * 60)], average: 0), 60,
                    "a short day rounds up to a quarter-hour scale", &problems)
        expectClose(PeriodChartLayout.yMaximumMinutes(
            for: [PeriodChartPoint(date: first, seconds: 3 * 3_600)], average: 0), 180,
                    "a three-hour day keeps an exact half-hour scale", &problems)
        expectClose(PeriodChartLayout.yMaximumMinutes(
            for: [PeriodChartPoint(date: first, seconds: 60)], average: 5 * 3_600), 300,
                    "the average is inside the scale even when it exceeds every bar", &problems)
        expectClose(PeriodChartLayout.yMaximumMinutes(for: [], average: 0), 15,
                    "an empty chart still has a positive scale", &problems)
        return problems
    }

    /// The inline Review detail is a projection of values Review has already
    /// published. It must never recompute time, never reach past the selected
    /// local day, and never survive a period or filter that no longer contains
    /// its date.
    private static func testReviewSelectedDayDetail() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(periodAnchor())
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: clock.value)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  let longAgo = calendar.date(byAdding: .day, value: -400, to: today),
                  let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday),
                  let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) else {
                return ["could not build Review detail fixture dates"]
            }

            // Early-morning offsets so every fixture moment stays in the past
            // whatever hour the suite runs at.
            let archive = makeArchive(clock)
            archive.append(SessionRecord(
                name: "Parser", workType: .deepWork,
                start: today.addingTimeInterval(3_600),
                end: today.addingTimeInterval(3_600 + 25 * 60),
                workSeconds: 25 * 60))
            archive.append(SessionRecord(
                name: "Lunch", workType: .breakTime,
                start: today.addingTimeInterval(2 * 3_600),
                end: today.addingTimeInterval(2 * 3_600 + 30 * 60),
                workSeconds: 30 * 60))
            archive.append(SessionRecord(
                name: "Stand-up", workType: .meetings,
                start: yesterday.addingTimeInterval(3_600),
                end: yesterday.addingTimeInterval(3_600 + 15 * 60),
                workSeconds: 15 * 60))
            archive.append(SessionRecord(
                name: "Night hand-off", workType: .deepWork,
                start: yesterday.addingTimeInterval(23 * 3_600 + 50 * 60),
                end: today.addingTimeInterval(10 * 60),
                workSeconds: 20 * 60))

            let usage = AppUsageArchive(directory: scratchDirectory(), now: { clock.value })
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: today.addingTimeInterval(3_600),
                end: today.addingTimeInterval(3_600 + 45 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.browser", appName: "Browser",
                start: today.addingTimeInterval(2 * 3_600 + 30 * 60),
                end: today.addingTimeInterval(2 * 3_600 + 50 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: yesterday.addingTimeInterval(3_600),
                end: yesterday.addingTimeInterval(3_600 + 30 * 60)))

            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()

            guard let detail = store.reviewDayDetail(for: today, calendar: calendar) else {
                return problems + ["selected Review day should derive a detail"]
            }
            expect(calendar.isDate(detail.day.date, inSameDayAs: today),
                   "detail keeps the literal day", &problems)
            expectClose(detail.day.tracked, 65 * 60,
                        "detail uses canonical History tracked time", &problems)
            expectClose(detail.day.focused, 35 * 60,
                        "detail uses canonical History focused time", &problems)
            expect(detail.appEntries.allSatisfy { calendar.isDate($0.day, inSameDayAs: today) },
                   "detail log contains only the selected local day", &problems)
            expect(detail.appEntries.contains { $0.session.bundleID == "com.example.browser" },
                   "detail log keeps the selected day's own app evidence", &problems)
            expect(detail.focusEntries.allSatisfy { $0.start < endOfToday && $0.end > today },
                   "detail focus rows intersect the selected local day", &problems)
            expect(detail.focusEntries.count == 2
                       && detail.focusEntries.allSatisfy { $0.workType.countsAsFocus },
                   "detail focus rows exclude rest records", &problems)
            expect(detail.periodDay.map { calendar.isDate($0.date, inSameDayAs: today) } ?? false,
                   "detail carries the matching period bar", &problems)

            guard let yesterdayDetail = store.reviewDayDetail(for: yesterday, calendar: calendar),
                  let beforeMidnight = yesterdayDetail.focusEntries.first(where: {
                      $0.name == "Night hand-off"
                  }),
                  let afterMidnight = detail.focusEntries.first(where: {
                      $0.name == "Night hand-off"
                  }) else {
                return problems + ["cross-midnight focus should appear in both selected days"]
            }
            expect(beforeMidnight.start == yesterday.addingTimeInterval(23 * 3_600 + 50 * 60)
                       && beforeMidnight.end == endOfYesterday,
                   "previous-day detail clips a crossing focus range at midnight", &problems)
            expectClose(beforeMidnight.seconds, 10 * 60,
                        "previous-day detail clips a crossing focus duration", &problems)
            expect(afterMidnight.start == today
                       && afterMidnight.end == today.addingTimeInterval(10 * 60),
                   "next-day detail begins a crossing focus range at midnight", &problems)
            expectClose(afterMidnight.seconds, 10 * 60,
                        "next-day detail clips a crossing focus duration", &problems)

            expect(store.reviewDayIsAvailable(today, section: .week, calendar: calendar),
                   "a day inside the selected period stays available", &problems)
            expect(!store.reviewDayIsAvailable(longAgo, section: .week, calendar: calendar),
                   "a day outside the selected period is unavailable", &problems)
            expect(store.reviewDayDetail(for: longAgo, calendar: calendar) == nil,
                   "a day with no canonical History row derives no detail", &problems)

            expect(store.reviewDayIsAvailable(yesterday, section: .history, calendar: calendar),
                   "History availability starts from the unfiltered rows", &problems)
            store.setHistoryQuery("browser")
            expect(!store.reviewDayIsAvailable(yesterday, section: .history, calendar: calendar),
                   "a filtered-out day stops being available in History", &problems)
            expect(store.reviewDayIsAvailable(today, section: .history, calendar: calendar),
                   "the matching day remains available under an active filter", &problems)
            store.clearHistoryFilters()
            return problems
        }
    }

    private static func testReviewHistoryFiltersAndDayRouting() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(periodAnchor())
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: clock.value)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) else {
                return ["could not build Review fixture dates"]
            }

            let archive = makeArchive(clock)
            archive.append(SessionRecord(
                name: "Plan", workType: .admin,
                start: twoDaysAgo.addingTimeInterval(30 * 60),
                end: twoDaysAgo.addingTimeInterval(38 * 60),
                workSeconds: 8 * 60))
            archive.append(SessionRecord(
                name: "Stand-up", workType: .meetings,
                start: yesterday.addingTimeInterval(60 * 60),
                end: yesterday.addingTimeInterval(75 * 60),
                workSeconds: 15 * 60))
            archive.append(SessionRecord(
                name: "Parser", workType: .deepWork,
                start: today.addingTimeInterval(2 * 3_600),
                end: today.addingTimeInterval(2 * 3_600 + 25 * 60),
                workSeconds: 25 * 60))

            let usage = AppUsageArchive(directory: scratchDirectory(), now: { clock.value })
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: twoDaysAgo.addingTimeInterval(30 * 60),
                end: twoDaysAgo.addingTimeInterval(40 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.browser", appName: "Browser",
                start: yesterday.addingTimeInterval(60 * 60),
                end: yesterday.addingTimeInterval(80 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: today.addingTimeInterval(2 * 3_600),
                end: today.addingTimeInterval(2 * 3_600 + 45 * 60)))

            let week = PeriodStats(sessions: archive, usage: usage,
                                   calendar: calendar, now: { clock.value })
                .rollup(for: .week, containing: today)
            let month = PeriodStats(sessions: archive, usage: usage,
                                    calendar: calendar, now: { clock.value })
                .rollup(for: .month, containing: today)
            let expectedTracked: [Date: TimeInterval] = [
                twoDaysAgo: 10 * 60,
                yesterday: 20 * 60,
                today: 45 * 60
            ]
            for point in PeriodChartData.tracked(week.days) {
                expectClose(point.seconds, expectedTracked[point.date] ?? 0,
                            "Week bar for \(point.date)", &problems)
            }
            for point in PeriodChartData.tracked(month.days) {
                expectClose(point.seconds, expectedTracked[point.date] ?? 0,
                            "Month bar for \(point.date)", &problems)
            }
            expectClose(week.summary.averagePerActiveDay, 25 * 60,
                        "Week average from the three tracked bars", &problems)
            expectClose(month.summary.averagePerActiveDay, 25 * 60,
                        "Month average from the three tracked bars", &problems)

            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()

            expect(store.historyDays.map(\.date) == [today, yesterday, twoDaysAgo],
                   "History is reverse chronological across usage and archive evidence",
                   &problems)
            if store.historyDays.count == 3 {
                expectClose(store.historyDays[0].tracked, 45 * 60,
                            "today History tracked", &problems)
                expectClose(store.historyDays[0].focused, 25 * 60,
                            "today History focused", &problems)
                expect(store.historyDays[0].sessions == 1,
                       "today History counts one thread", &problems)
            }
            expectClose(store.reviewLongestFocusSeconds, 25 * 60,
                        "Review longest focus stretch", &problems)
            expect(store.reviewLongestFocusName == "Parser",
                   "Review names the longest focus stretch", &problems)

            let query = HistoryFilter(query: "browser")
                .apply(to: store.historyDays)
            expect(query.map(\.date) == [yesterday],
                   "query matches the day's app evidence", &problems)

            let intersection = HistoryFilter(
                query: "browser",
                appBundleID: "com.example.browser",
                workType: .meetings
            ).apply(to: store.historyDays)
            expect(intersection.map(\.date) == [yesterday],
                   "query, app and work-type filters intersect", &problems)

            let impossibleIntersection = HistoryFilter(
                query: "browser",
                appBundleID: "com.example.browser",
                workType: .deepWork
            ).apply(to: store.historyDays)
            expect(impossibleIntersection.isEmpty,
                   "a day must satisfy every active History filter", &problems)

            guard let routedDate = PeriodChartData.tracked(week.days)
                .first(where: { $0.date == yesterday })?.date else {
                return problems + ["Week chart did not contain yesterday's literal date"]
            }
            let navigation = MainWindowModel(selectedTab: .review)
            let selectReviewDay = ReviewDayRoute.select(store: store,
                                                        navigation: navigation)
            selectReviewDay(routedDate)
            expect(navigation.selectedTab == .review,
                   "a selected Review bar keeps the user in Review", &problems)
            expect(calendar.isDate(navigation.reviewSelectedDate ?? base,
                                   inSameDayAs: yesterday),
                   "a selected Review bar selects its literal date in Review", &problems)
            expect(navigation.requestedDate == nil,
                   "selecting a bar does not request a Today day", &problems)
            expect(calendar.isDate(store.selectedDay, inSameDayAs: today),
                   "the Review selection leaves Today's own selected day alone", &problems)
            return problems
        }
    }

    /// Insights may describe only facts already established by canonical Core
    /// helpers. Missing inputs stay absent rather than becoming zero-valued
    /// prose, and secondary range navigation is earned by two evidenced ranges.
    private static func testInsightSurfaceRequiresEvidence() -> [String] {
        var problems: [String] = []
        let emptyGoal = GoalProgress(goal: 4 * 3_600, achieved: 0, typical: nil)
        let emptyQuality = FocusQuality(byWorkType: [], insideSessionShare: 0,
                                        switchesPerSession: 0, sessionCount: 0)
        let empty = InsightSurface.make(
            range: .week,
            goal: emptyGoal,
            rhythm: [],
            rhythmPeak: nil,
            quality: emptyQuality,
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)

        expect(!empty.hasEvidence,
               "first-run Insights has no statements", &problems)
        expect([empty.pace, empty.rhythm, empty.quality, empty.continuity]
                .compactMap { $0 }.isEmpty,
               "missing evidence remains absent rather than rendering zero", &problems)
        expect(InsightSurface.insufficientEvidenceCopy
                   == "Keep using FocusContinuity; patterns appear once there is enough comparable history.",
               "first-run copy explains how evidence becomes available", &problems)

        let zeroHour = RhythmHour(hour: base, seconds: 0, colorIndex: 6)
        let zeroRhythm = InsightSurface.make(
            range: .week,
            goal: emptyGoal,
            rhythm: [zeroHour],
            rhythmPeak: "9am",
            quality: emptyQuality,
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)
        expect(zeroRhythm.rhythm == nil && !zeroRhythm.hasEvidence,
               "Rhythm requires at least one non-zero canonical hour", &problems)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = calendar.startOfDay(for: base)
        let current = today.addingTimeInterval(10 * 3_600)
        let clock = Clock(current)
        let archive = SessionArchive(directory: scratchDirectory(), calendar: calendar,
                                     now: { clock.value })
        var usage: [AppUsageSession] = []
        for offset in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return problems + ["could not build authoritative Insights pace history"]
            }
            let start = day.addingTimeInterval(9 * 3_600)
            let seconds = TimeInterval((15 + offset * 15) * 60)
            archive.append(SessionRecord(name: "Focus", workType: .deepWork,
                                         start: start,
                                         end: start.addingTimeInterval(seconds),
                                         workSeconds: seconds))
            usage.append(AppUsageSession(bundleID: "org.example.editor", appName: "Editor",
                                         start: start,
                                         end: start.addingTimeInterval(seconds)))
        }
        let todayStart = today.addingTimeInterval(9 * 3_600)
        archive.append(SessionRecord(name: "Focus", workType: .deepWork,
                                     start: todayStart,
                                     end: todayStart.addingTimeInterval(60 * 60),
                                     workSeconds: 60 * 60))
        usage.append(AppUsageSession(bundleID: "org.example.editor", appName: "Editor",
                                     start: todayStart,
                                     end: todayStart.addingTimeInterval(60 * 60)))
        guard let migrationDay = calendar.date(byAdding: .day, value: -4, to: today) else {
            return problems + ["could not build the Insights accuracy epoch"]
        }
        let goal = DailyGoal(
            archive: archive,
            goal: 4 * 3_600,
            usage: usage,
            usageAccurateFrom: migrationDay.addingTimeInterval(12 * 3_600),
            calendar: calendar,
            now: { clock.value }).progress()
        expect(goal.typicalByNow != nil,
               "three authoritative active days establish the DailyGoal median", &problems)

        let pace = InsightSurface.make(
            range: .week,
            goal: goal,
            rhythm: [],
            rhythmPeak: nil,
            quality: emptyQuality,
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)
        expect(pace.pace != nil && pace.hasEvidence,
               "the established personal median permits a Pace statement", &problems)
        expect(pace.rhythm == nil && pace.quality == nil && pace.continuity == nil,
               "Pace does not manufacture the other three groups", &problems)

        let evidenced = InsightSurface.make(
            range: .month,
            goal: emptyGoal,
            rhythm: [RhythmHour(hour: base, seconds: 45 * 60, colorIndex: 0)],
            rhythmPeak: "9am",
            quality: FocusQuality(
                byWorkType: [WorkTypeShare(workType: .deepWork,
                                           seconds: 2 * 3_600, share: 1)],
                insideSessionShare: 0.6,
                switchesPerSession: 2,
                sessionCount: 2),
            streak: 2,
            activeDays: 4,
            totalDays: 31,
            tracked: 5 * 3_600,
            comparableTracked: 4 * 3_600)
        expect(evidenced.rhythm != nil && evidenced.quality != nil
                   && evidenced.continuity != nil,
               "present Rhythm, Focus quality and Continuity facts render", &problems)
        let written = [pace.pace, evidenced.rhythm, evidenced.quality, evidenced.continuity]
            .compactMap { $0 }
            .flatMap { [$0.headline, $0.detail] }
        expect(written.allSatisfy {
            !$0.hasPrefix("0m") && !$0.contains(" 0m")
                && !$0.hasPrefix("0%") && !$0.contains(" 0%")
        },
               "evidenced copy never substitutes a missing value with zero", &problems)

        expect(!InsightSurface.showsRangeSelector(week: pace, month: empty),
               "one evidenced range does not expose a selector", &problems)
        expect(!InsightSurface.showsRangeSelector(week: pace, month: evidenced),
               "global Pace alone does not expose a selector with no Week period fact",
               &problems)
        let evidencedWeek = InsightSurface.make(
            range: .week,
            goal: emptyGoal,
            rhythm: [RhythmHour(hour: base, seconds: 45 * 60, colorIndex: 0)],
            rhythmPeak: "9am",
            quality: emptyQuality,
            streak: 0,
            activeDays: 2,
            totalDays: 7,
            tracked: 2 * 3_600,
            comparableTracked: nil)
        expect(InsightSurface.showsRangeSelector(week: evidencedWeek, month: evidenced),
               "Week and Month selection appears only when both have evidence", &problems)

        let usageArchive = makeUsageArchive(
            clock,
            sessions: usage,
            accurateFrom: migrationDay.addingTimeInterval(12 * 3_600))
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usageArchive,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usageArchive)
        store.refreshInsights()
        expect(store.insightWeekSurface.pace != nil
                   && store.insightMonthSurface.pace != nil,
               "SessionStore composes both ranges from the canonical DailyGoal evidence",
               &problems)
        expect(store.insightSurface(for: .week) == store.insightWeekSurface,
               "the requested evidenced range is the surface selected for presentation",
               &problems)
        store.insightWeekSurface = pace
        store.insightMonthSurface = evidenced
        expect(store.insightSurface(for: .week) == evidenced,
               "a sole Month period fact is not hidden behind Week-only Pace", &problems)

        var boundaryComponents = DateComponents()
        boundaryComponents.calendar = Calendar.current
        boundaryComponents.timeZone = Calendar.current.timeZone
        boundaryComponents.year = 2024
        boundaryComponents.month = 3
        boundaryComponents.day = 31
        boundaryComponents.hour = 12
        guard let monthBoundary = Calendar.current.date(from: boundaryComponents),
              let previousMonthDay = Calendar.current.date(
                byAdding: .month, value: -1, to: monthBoundary),
              let accurateFrom = Calendar.current.date(
                byAdding: .month, value: -3, to: monthBoundary) else {
            return problems + ["could not build unequal-month Insights boundaries"]
        }
        let boundaryClock = Clock(monthBoundary)
        let currentStart = Calendar.current.startOfDay(for: monthBoundary)
            .addingTimeInterval(9 * 3_600)
        let previousStart = Calendar.current.startOfDay(for: previousMonthDay)
            .addingTimeInterval(9 * 3_600)
        let boundaryUsage = makeUsageArchive(
            boundaryClock,
            sessions: [
                AppUsageSession(bundleID: "org.example.current", appName: "Current",
                                start: currentStart,
                                end: currentStart.addingTimeInterval(3_600)),
                AppUsageSession(bundleID: "org.example.previous", appName: "Previous",
                                start: previousStart,
                                end: previousStart.addingTimeInterval(3_600))
            ],
            accurateFrom: accurateFrom)
        let boundaryPersistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        boundaryPersistence.removeAll()
        let boundaryEngine = SessionEngine(
            store: boundaryPersistence,
            archive: makeArchive(boundaryClock),
            ownBundleID: "com.example.self",
            schedulesDwell: false,
            now: { boundaryClock.value })
        let boundaryTracker = AppUsageTracker(
            archive: boundaryUsage,
            ownBundleID: "com.example.self",
            idle: .disabled,
            now: { boundaryClock.value })
        let boundaryStore = SessionStore(engine: boundaryEngine,
                                         now: { boundaryClock.value })
        boundaryStore.attach(tracker: boundaryTracker, usage: boundaryUsage)
        boundaryStore.refreshInsights()
        expect(boundaryStore.insightMonthSurface.continuity?.detail
                   .contains("like-for-like previous period") != true,
               "a month with no corresponding previous-month day has no comparison",
               &problems)
        return problems
    }

    /// Selecting a session and disclosing its stretches are two actions. The
    /// disclosure must never be nested inside the selection button, swallowed by
    /// it, or represented as an undersized pointer-only chevron.
    private static func testTodaySessionRowControlsAreIndependent() -> [String] {
        var problems: [String] = []
        var selections = 0
        var disclosures = 0
        let collapsed = SessionRowInteraction(sessionName: "Write proposal",
                                              isExpanded: false)
        collapsed.perform(.disclosure,
                          onSelect: { selections += 1 },
                          onDisclosure: { disclosures += 1 })
        expect(selections == 0 && disclosures == 1,
               "disclosure fires without selecting the session", &problems)
        collapsed.perform(.selection,
                          onSelect: { selections += 1 },
                          onDisclosure: { disclosures += 1 })
        expect(selections == 1 && disclosures == 1,
               "selection fires without toggling disclosure", &problems)
        expect(SessionRowInteraction.minimumTargetSize >= 28,
               "both sibling controls retain a practical 28 point target", &problems)
        expect(collapsed.disclosureAccessibilityLabel
                   == "Show stretches and breaks for Write proposal"
                   && collapsed.disclosureAccessibilityValue == "Collapsed",
               "collapsed disclosure names its action and state", &problems)
        let expanded = SessionRowInteraction(sessionName: "Write proposal",
                                             isExpanded: true)
        expect(expanded.disclosureAccessibilityLabel
                   == "Hide stretches and breaks for Write proposal"
                   && expanded.disclosureAccessibilityValue == "Expanded",
               "expanded disclosure names its action and state", &problems)
        return problems
    }

    /// A preserved legacy stretch may remain visible in Review, but Insights
    /// cannot call it verified Rhythm or an authoritative active day. A later
    /// complete day remains eligible and supplies the literal expected totals.
    private static func testInsightsExcludePreAccuracyUsage() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchoredNow())
        let clock = Clock(today.addingTimeInterval(12 * 3_600))
        guard let accurateDay = calendar.date(byAdding: .day, value: -2, to: today),
              let legacyDay = calendar.date(byAdding: .day, value: -3, to: today) else {
            return ["could not build mixed-accuracy Insights dates"]
        }
        let legacyStart = legacyDay.addingTimeInterval(9 * 3_600)
        let authoritativeStart = today.addingTimeInterval(9 * 3_600)
        let usage = makeUsageArchive(
            clock,
            sessions: [
                AppUsageSession(bundleID: "org.example.legacy", appName: "Legacy",
                                start: legacyStart,
                                end: legacyStart.addingTimeInterval(60 * 60)),
                AppUsageSession(bundleID: "org.example.current", appName: "Current",
                                start: authoritativeStart,
                                end: authoritativeStart.addingTimeInterval(30 * 60))
            ],
            accurateFrom: accurateDay.addingTimeInterval(12 * 3_600))
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let archive = makeArchive(clock)
        archive.append(SessionRecord(name: "Legacy deep work", workType: .deepWork,
                                     start: legacyStart,
                                     end: legacyStart.addingTimeInterval(60 * 60),
                                     workSeconds: 60 * 60))
        archive.append(SessionRecord(name: "Current admin", workType: .admin,
                                     start: authoritativeStart,
                                     end: authoritativeStart.addingTimeInterval(30 * 60),
                                     workSeconds: 30 * 60))
        let engine = SessionEngine(
            store: persistence,
            archive: archive,
            ownBundleID: "com.example.self",
            schedulesDwell: false,
            now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.refreshInsights()

        let month = store.insightMonthSurface
        expect(month.rhythm?.detail.hasPrefix("30m at the Mac") == true,
               "verified Rhythm sums only the literal authoritative 30m; got "
                   + "'\(month.rhythm?.detail ?? "nil")'", &problems)
        expect(month.rhythm?.detail.contains("1h 30m") != true,
               "legacy time is absent from verified Rhythm", &problems)
        expect(month.continuity?.headline.hasPrefix("1 of 2 days had tracked time") == true,
               "active-day continuity counts only complete authoritative days; got "
                   + "'\(month.continuity?.headline ?? "nil")'", &problems)
        expect(month.quality?.headline == "Admin was 100% of focused time",
               "Focus quality excludes preserved pre-accuracy session/usage evidence; got "
                   + "'\(month.quality?.headline ?? "nil")'", &problems)
        expect(month.quality?.detail.hasPrefix("1 recorded focus session supplies") == true,
               "Focus quality counts only the authoritative thread session; got "
                   + "'\(month.quality?.detail ?? "nil")'", &problems)
        return problems
    }

    /// Week and Month are range statements. One canonical thread resumed after
    /// local midnight remains one focus session, and an A-to-B app change across
    /// those resumed stretches remains one real transition divided by that one
    /// session — never two daily denominators that dilute the rate to zero.
    private static func testInsightQualityDeduplicatesThreadsAcrossRange() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 8
        components.day = 26
        components.hour = 12
        guard let moment = calendar.date(from: components),
              let firstDay = calendar.date(byAdding: .day, value: -1,
                                           to: calendar.startOfDay(for: moment)),
              let accuracyDay = calendar.date(byAdding: .day, value: -1,
                                              to: firstDay) else {
            return ["could not build cross-day Insights quality fixture"]
        }
        let secondDay = calendar.startOfDay(for: moment)
        let clock = Clock(moment)
        let threadID = UUID()
        let firstStart = firstDay.addingTimeInterval(23.5 * 3_600)
        let secondStart = secondDay.addingTimeInterval(10 * 60)
        let records = [
            SessionRecord(name: "Range thread", workType: .deepWork,
                          start: firstStart,
                          end: firstStart.addingTimeInterval(20 * 60),
                          workSeconds: 20 * 60, threadID: threadID),
            SessionRecord(name: "Range thread", workType: .deepWork,
                          start: secondStart,
                          end: secondStart.addingTimeInterval(30 * 60),
                          workSeconds: 30 * 60, threadID: threadID)
        ]
        let usage = makeUsageArchive(
            clock,
            sessions: [
                AppUsageSession(bundleID: "org.example.alpha", appName: "Alpha",
                                start: firstStart,
                                end: firstStart.addingTimeInterval(20 * 60)),
                AppUsageSession(bundleID: "org.example.beta", appName: "Beta",
                                start: secondStart,
                                end: secondStart.addingTimeInterval(30 * 60))
            ],
            accurateFrom: accuracyDay.addingTimeInterval(12 * 3_600))
        let archive = makeArchive(clock, records: records, calendar: calendar)
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.refreshInsights()

        for (label, surface) in [("Week", store.insightWeekSurface),
                                 ("Month", store.insightMonthSurface)] {
            let detail = surface.quality?.detail ?? "nil"
            expect(detail.hasPrefix("1 recorded focus session supplies"),
                   "\(label) deduplicates the resumed thread; got '\(detail)'", &problems)
            expect(detail.contains("1.0 app switches per recorded focus session"),
                   "\(label) keeps the cross-day A-to-B transition undiluted; got "
                       + "'\(detail)'", &problems)
        }
        return problems
    }

    /// Tracker-originated checkpoints publish archive callbacks while the
    /// tracker is transitioning. Insights must join that final transition frame
    /// just like Review, then retain a pending refresh while hidden.
    private static func testTrackerTransitionsInvalidateInsights() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchoredNow())
        let clock = Clock(today.addingTimeInterval(9 * 3_600))
        guard let accurateFrom = calendar.date(byAdding: .day, value: -3, to: today) else {
            return ["could not build tracker Insights accuracy epoch"]
        }
        let usage = makeUsageArchive(clock, sessions: [], accurateFrom: accurateFrom)
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(
            store: persistence,
            archive: makeArchive(clock),
            ownBundleID: "com.example.self",
            schedulesDwell: false,
            now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setInsightsVisible(true)
        expect(store.insightWeekSurface.rhythm == nil,
               "the visible fixture begins without Rhythm", &problems)

        tracker.appActivated(bundleID: "org.example.editor", name: "Editor")
        clock.advance(10)
        tracker.flush()
        expect(store.insightWeekSurface.rhythm?.detail.hasPrefix("10s at the Mac") == true,
               "a visible tracker checkpoint refreshes Insights on its final frame; got "
                   + "'\(store.insightWeekSurface.rhythm?.detail ?? "nil")'", &problems)

        store.setInsightsVisible(false)
        clock.advance(10)
        tracker.flush()
        expect(store.insightsRefreshPending,
               "a hidden tracker checkpoint leaves Insights pending", &problems)
        store.setInsightsVisible(true)
        expect(store.insightWeekSurface.rhythm?.detail.hasPrefix("20s at the Mac") == true,
               "the next open consumes the hidden tracker checkpoint; got "
                   + "'\(store.insightWeekSurface.rhythm?.detail ?? "nil")'", &problems)
        return problems
    }

    /// A small positive share/rate is evidence. Decimal rounding must not turn
    /// it into a visible assertion of zero.
    private static func testInsightQualityPreservesTinyPositiveEvidence() -> [String] {
        var problems: [String] = []
        let surface = InsightSurface.make(
            range: .week,
            goal: GoalProgress(goal: 4 * 3_600, achieved: 0, typical: nil),
            rhythm: [],
            rhythmPeak: nil,
            quality: FocusQuality(
                byWorkType: [WorkTypeShare(workType: .deepWork,
                                           seconds: 30, share: 0.004)],
                insideSessionShare: 0.004,
                switchesPerSession: 0.04,
                sessionCount: 1),
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)
        let headline = surface.quality?.headline ?? ""
        let detail = surface.quality?.detail ?? ""
        expect(headline == "Deep work was <1% of focused time",
               "tiny positive work-type share uses an honest lower bound; got '\(headline)'",
               &problems)
        expect(detail.contains("<1% of tracked time")
                   && detail.contains("<0.1 app switches"),
               "tiny positive quality details retain both lower bounds; got '\(detail)'",
               &problems)
        expect(detail.hasPrefix("1 recorded focus session supplies"),
               "singular quality evidence uses the singular verb; got '\(detail)'",
               &problems)
        expect(!headline.contains(" 0%") && !detail.contains(" 0%")
                   && !detail.contains("0.0 app switches"),
               "positive quality facts never render as zero", &problems)
        return problems
    }

    /// Row presentation retains the newest 500, while exact period aggregates
    /// remain separately available from all source sessions. A bound must never
    /// silently turn Top Apps into "Top apps among the newest rows".
    private static func testPeriodLogRetainsNewestLimit() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let monthStart = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2023, month: 11, day: 1)),
              let recentDay = calendar.date(byAdding: .day, value: 28, to: monthStart),
              let anchor = calendar.date(byAdding: .hour, value: 12, to: recentDay) else {
            return ["could not build the bounded period fixture"]
        }
        let clock = Clock(anchor)
        var stretches: [AppUsageSession] = []
        for index in 0..<500 {
            let dayOffset = index / 18
            let slot = index % 18
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: monthStart),
                  let start = calendar.date(byAdding: .minute, value: slot * 10, to: day) else {
                return ["could not build old period usage"]
            }
            stretches.append(AppUsageSession(
                bundleID: "org.example.archive", appName: "Archive",
                start: start, end: start.addingTimeInterval(60)))
        }
        for slot in 0..<10 {
            guard let start = calendar.date(byAdding: .minute, value: slot * 10,
                                            to: recentDay) else {
                return ["could not build recent period usage"]
            }
            stretches.append(AppUsageSession(
                bundleID: "org.example.current", appName: "Current",
                start: start, end: start.addingTimeInterval(60)))
        }

        let usage = makeUsageArchive(clock, sessions: stretches, accurateFrom: monthStart)
        let archive = SessionArchive(directory: scratchDirectory(), calendar: calendar,
                                     now: { clock.value })
        let stats = PeriodStats(sessions: archive, usage: usage,
                                calendar: calendar, now: { clock.value })
        let rollup = stats.rollup(for: .month, containing: anchor)
        let separateLog = stats.log(for: .month, containing: anchor)

        expect(rollup.log.count == 500,
               "period rollup retains exactly 500 entries, got \(rollup.log.count)", &problems)
        expect(Array(rollup.log.prefix(10)).allSatisfy {
            $0.session.bundleID == "org.example.current"
        }, "the newest ten sessions survive the cap", &problems)
        expect(separateLog == rollup.log,
               "standalone log and rollup retain the identical set", &problems)
        expect(rollup.totalLogEntries == 510 && rollup.logRowsOmitted == 10,
               "the bounded row model carries its exact full-period count", &problems)
        expectClose(rollup.dayTotals.values.reduce(0, +),
                    rollup.log.reduce(0) { $0 + $1.session.attended },
                   "retained day totals", &problems)
        let groups = rollup.exactAppGroups
        expectClose(groups.first(where: { $0.bundleID == "org.example.current" })?.total ?? -1,
                    10 * 60, "recent app exact total", &problems)
        expectClose(groups.first(where: { $0.bundleID == "org.example.archive" })?.total ?? -1,
                    500 * 60, "old app exact full-period total", &problems)
        expectClose(groups.reduce(0) { $0 + $1.total }, 510 * 60,
                    "exact app groups remain separate from bounded rows", &problems)

        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.reviewAnchor = anchor
        store.refreshReview(period: .month)
        expect(store.reviewLog.count == 500 && store.reviewLogTotalEntries == 510
                   && store.reviewLogRowsOmitted == 10,
               "Review publishes bounded rows beside the exact source count", &problems)
        expect(store.reviewLogRowsQualification
                   == "Showing newest 500 of 510 app-session rows",
               "Review labels the bounded chronological rows", &problems)
        expect(store.reviewAppAggregateQualification
                   == "Exact full period · 510 app sessions",
               "Review labels Top Apps as an exact full-period aggregate", &problems)
        expectClose(store.reviewAppGroups.reduce(0) { $0 + $1.total }, 510 * 60,
                    "Review Top Apps consumes every full-period session", &problems)
        guard let oldDayDetail = store.reviewDayDetail(for: monthStart, calendar: calendar) else {
            return problems + ["oldest dense-period day should open a Review detail"]
        }
        expect(oldDayDetail.appEntries.count == 18,
               "selected-day app detail retains every old-day entry beyond the period log cap",
               &problems)
        expectClose(oldDayDetail.appEntries.reduce(0) { $0 + $1.session.attended }, 18 * 60,
                    "selected-day app detail retains the old day's exact tracked evidence",
                    &problems)
        return problems
    }

    /// A dense period log is intentionally capped at 500 chronological rows,
    /// but selecting a day must still expose every app session that belongs to
    /// that literal day. If detail reads the capped period list, one real app
    /// disappears as soon as the period reaches 501 rows.
    private static func testReviewDetailRetainsUncappedDayEntries() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(anchoredNow())
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: clock.value)
            let start = day.addingTimeInterval(3_600)
            let sessions = (0...500).map { index in
                AppUsageSession(bundleID: "org.example.day.\(index)",
                                appName: "Day app \(index)",
                                start: start,
                                end: start.addingTimeInterval(60))
            }
            let usage = makeUsageArchive(clock, sessions: sessions, accurateFrom: day)
            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: makeArchive(clock),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview(period: .month)

            expect(store.reviewLog.count == 500 && store.reviewLogTotalEntries == 501,
                   "the chronological Review log applies its 500-row display cap", &problems)
            guard let detail = store.reviewDayDetail(for: day, calendar: calendar) else {
                return problems + ["the dense selected day should derive a Review detail"]
            }
            expect(detail.appEntries.count == 501,
                   "selected-day app detail retains all 501 canonical entries", &problems)
            expect(Set(detail.appEntries.map(\.session.bundleID)).count == 501,
                   "selected-day app detail loses no app identity beyond the cap", &problems)
            expectClose(detail.appEntries.reduce(0) { $0 + $1.session.attended }, 501 * 60,
                        "selected-day app detail retains exact tracked evidence", &problems)
            return problems
        }
    }

    /// Tracked time can legitimately be absent while the archive still contains
    /// focus records. Review must keep that evidence visible and label the
    /// missing tracked series rather than replacing the whole period with empty.
    private static func testReviewFocusOnlyPeriodEvidence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(base)
            let calendar = Calendar.current
            guard let bounds = calendar.dateInterval(of: .weekOfYear,
                                                      for: clock.value) else {
                return ["could not build focus-only Review bounds"]
            }
            let archive = makeArchive(clock)
            let focusThread = UUID()
            archive.append(SessionRecord(
                name: "Write proposal", workType: .deepWork,
                start: bounds.start.addingTimeInterval(2 * 3_600),
                end: bounds.start.addingTimeInterval(2 * 3_600 + 45 * 60),
                workSeconds: 45 * 60, threadID: focusThread))
            archive.append(SessionRecord(
                name: "Write proposal", workType: .deepWork,
                start: bounds.start.addingTimeInterval(6 * 3_600),
                end: bounds.start.addingTimeInterval(6 * 3_600 + 15 * 60),
                workSeconds: 15 * 60, threadID: focusThread))
            archive.append(SessionRecord(
                name: "Lunch", workType: .breakTime,
                start: bounds.start.addingTimeInterval(4 * 3_600),
                end: bounds.start.addingTimeInterval(5 * 3_600),
                workSeconds: 60 * 60))
            let usage = makeUsageArchive(clock, sessions: [], accurateFrom: bounds.start)
            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview(period: .week)

            expect(store.reviewSummary.tracked == 0
                       && store.reviewSummary.activeDays == 0,
                   "focus-only fixture has no tracked series", &problems)
            expect(store.reviewHasRelevantEvidence,
                   "focus-only archive evidence defeats Review empty", &problems)
            expect(store.reviewFocusSessions.count == 2,
                   "both focus stretches remain available to Review", &problems)
            expect(store.reviewFocusSessions.allSatisfy {
                $0.name == "Write proposal" && $0.workType == .deepWork
            }, "focus-only stretches keep their name and type", &problems)
            expectClose(store.reviewFocusSessions.reduce(0) { $0 + $1.seconds },
                        60 * 60, "focus-only session duration", &problems)
            expect(store.reviewSummaryLine.contains("No tracked time")
                       && store.reviewSummaryLine.contains("1 focus session"),
                   "focus-only summary counts the shared thread once", &problems)
            return problems
        }
    }

    /// The archive may hold 5,000 records, but Review must not eagerly compose
    /// them all. The row cap prefers newest stretches while full-period totals,
    /// longest focus, work types and thread counts remain uncapped.
    private static func testReviewFocusRowsAreBoundedAndQualified() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(anchoredNow())
            let calendar = Calendar.current
            guard let bounds = calendar.dateInterval(of: .weekOfYear,
                                                      for: clock.value) else {
                return ["could not build dense focus Review bounds"]
            }
            var records: [SessionRecord] = []
            for index in 0..<510 {
                let start = bounds.start.addingTimeInterval(3_600 + Double(index * 60))
                let seconds: TimeInterval = index == 0 ? 120 : 60
                records.append(SessionRecord(
                    name: "Focus \(index)",
                    workType: index == 0 ? .learning : .deepWork,
                    start: start, end: start.addingTimeInterval(seconds),
                    workSeconds: seconds))
            }
            let archive = makeArchive(clock, records: records, calendar: calendar)
            let usage = makeUsageArchive(clock, sessions: [],
                                         accurateFrom: bounds.start)
            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview(period: .week)

            expect(store.reviewFocusSessions.count == 510,
                   "full focus evidence remains available to summaries", &problems)
            expect(store.reviewFocusSessionRows.count == 500,
                   "focus presentation is capped at 500 rows", &problems)
            expect(store.reviewFocusSessionRows.first?.name == "Focus 509"
                       && store.reviewFocusSessionRows.last?.name == "Focus 10",
                   "bounded rows retain the deterministic newest 500", &problems)
            expect(store.reviewFocusRowsOmitted == 10,
                   "the omitted row count is exact", &problems)
            expect(store.reviewFocusRowsQualification
                       == "Showing newest 500 of 510 stretches",
                   "the row cap is stated plainly", &problems)

            expect(store.reviewFocusSessionCount == 510
                       && store.reviewSummaryLine.contains("510 focus sessions"),
                   "session summary remains uncapped", &problems)
            expectClose(store.reviewFocusSessions.reduce(0) { $0 + $1.seconds },
                        511 * 60, "full focused total", &problems)
            expect(store.reviewLongestFocusName == "Focus 0"
                       && store.reviewLongestFocusSeconds == 120,
                   "the omitted oldest row can still be the true longest", &problems)
            expect(store.reviewWorkTypeShares.contains {
                $0.workType == .learning && $0.seconds == 120
            }, "work-type evidence includes an omitted row", &problems)
            return problems
        }
    }

    /// Search copy promises app names. The displayed name can be unrelated to
    /// the bundle ID, so matching only the identifier breaks that promise.
    private static func testHistorySearchesDisplayedAppName() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(base)
            let day = Calendar.current.startOfDay(for: clock.value)
            let usage = makeUsageArchive(clock, sessions: [
                AppUsageSession(bundleID: "org.example.product", appName: "Quill Writer",
                                start: day.addingTimeInterval(600),
                                end: day.addingTimeInterval(1_200))
            ], accurateFrom: day)
            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(
                store: persistence, archive: makeArchive(clock),
                ownBundleID: "com.example.self", schedulesDwell: false,
                now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()
            store.setHistoryQuery("quill writer")

            expect(!"org.example.product".contains("quill"),
                   "fixture name remains independent of its bundle ID", &problems)
            expect(store.filteredHistoryDays.map(\.date) == [day],
                   "History query matches the stable displayed app name", &problems)
            return problems
        }
    }

    /// One malformed decoded record must not allocate hundreds of derived day
    /// rows. Ordinary cross-midnight evidence still clips exactly to both days.
    private static func testHistoryBoundsMalformedSpans() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let firstDay = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2024, month: 1, day: 1)),
              let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay),
              let malformedStart = calendar.date(byAdding: .day, value: -500,
                                                  to: firstDay) else {
            return ["could not build malformed History fixture"]
        }
        let crossingStart = firstDay.addingTimeInterval(23 * 3_600 + 50 * 60)
        let crossingEnd = secondDay.addingTimeInterval(10 * 60)
        let usage = [
            AppUsageSession(bundleID: "org.example.normal", appName: "Normal",
                            start: crossingStart, end: crossingEnd),
            AppUsageSession(bundleID: "org.example.malformed", appName: "Malformed",
                            start: malformedStart, end: secondDay.addingTimeInterval(12 * 3_600))
        ]
        let records = [
            SessionRecord(name: "Normal focus", workType: .deepWork,
                          start: crossingStart, end: crossingEnd,
                          workSeconds: 20 * 60),
            SessionRecord(name: "Malformed focus", workType: .admin,
                          start: malformedStart,
                          end: secondDay.addingTimeInterval(12 * 3_600),
                          workSeconds: 501 * 86_400)
        ]

        let result = HistoryStats.build(sessionRecords: records, usage: usage,
                                        calendar: calendar)
        let days = result.days
        expect(days.map(\.date) == [secondDay, firstDay],
               "malformed distant records add no derived days", &problems)
        if days.count == 2 {
            expectClose(days[0].tracked, 10 * 60,
                        "midnight usage after boundary", &problems)
            expectClose(days[1].tracked, 10 * 60,
                        "midnight usage before boundary", &problems)
            expectClose(days[0].focused, 10 * 60,
                        "midnight focus after boundary", &problems)
            expectClose(days[1].focused, 10 * 60,
                        "midnight focus before boundary", &problems)
        }
        expect(usage.count == 2 && records.count == 2,
               "derived bounding never mutates source records", &problems)
        expect(result.droppedUsageSpans == 1,
               "the omitted span-bound usage record is counted for disclosure", &problems)
        expect(result.droppedFocusSpans == 1 && result.droppedRestSpans == 0,
               "the omitted span-bound focus record is counted for disclosure", &problems)
        return problems
    }

    /// History keeps legacy evidence visible, but it must qualify its recording
    /// guarantee and disclose every record omitted only from the bounded derived
    /// index. Neither notice permits mutation of the preserved source archives.
    private static func testHistoryDisclosesLegacyAndDroppedSpans() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchoredNow())
        let clock = Clock(today.addingTimeInterval(12 * 3_600))
        guard let legacyDay = calendar.date(byAdding: .day, value: -2, to: today),
              let malformedStart = calendar.date(byAdding: .day, value: -500, to: today),
              let accurateFrom = calendar.date(byAdding: .day, value: -1, to: today)?
                .addingTimeInterval(12 * 3_600) else {
            return ["could not build History disclosure dates"]
        }
        let legacyStart = legacyDay.addingTimeInterval(9 * 3_600)
        let malformedEnd = today.addingTimeInterval(10 * 3_600)
        let usageSessions = [
            AppUsageSession(bundleID: "org.example.legacy", appName: "Legacy",
                            start: legacyStart, end: legacyStart.addingTimeInterval(30 * 60)),
            AppUsageSession(bundleID: "org.example.malformed", appName: "Malformed",
                            start: malformedStart, end: malformedEnd)
        ]
        let sessionRecords = [
            SessionRecord(name: "Legacy focus", workType: .learning,
                          start: legacyStart, end: legacyStart.addingTimeInterval(30 * 60),
                          workSeconds: 30 * 60),
            SessionRecord(name: "Malformed focus", workType: .deepWork,
                          start: malformedStart, end: malformedEnd,
                          workSeconds: 500 * 86_400),
            SessionRecord(name: "Malformed break", workType: .breakTime,
                          start: malformedStart.addingTimeInterval(60),
                          end: malformedEnd,
                          workSeconds: 500 * 86_400)
        ]
        let usage = makeUsageArchive(clock, sessions: usageSessions,
                                     accurateFrom: accurateFrom)
        let archive = makeArchive(clock, records: sessionRecords, calendar: calendar)
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.refreshReview()

        expect(store.historyIntegrityNotices.contains {
            $0.contains(Tokens.longDate(accurateFrom))
                && $0.localizedCaseInsensitiveContains("legacy")
        }, "History qualifies preserved pre-accuracy app usage", &problems)
        expect(store.historyIntegrityNotices.contains {
            $0.contains("1 app-usage record") && $0.contains("1 focus record")
                && $0.contains("1 rest record")
                && $0.localizedCaseInsensitiveContains("source records remain preserved")
        }, "History distinguishes focus/rest span omissions and source preservation",
               &problems)
        expect(usage.sessions == usageSessions && archive.records == sessionRecords,
               "History disclosure never rewrites either source archive", &problems)
        return problems
    }

    /// The period's winning focus stretch is its clipped contribution. A large
    /// break and a larger out-of-period tail are never eligible to win.
    private static func testReviewLongestFocusClipsBoundsAndExcludesBreaks() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = Clock(base)
            let calendar = Calendar.current
            guard let bounds = calendar.dateInterval(of: .weekOfYear, for: clock.value) else {
                return ["could not build Review week bounds"]
            }
            let archive = makeArchive(clock)
            archive.append(SessionRecord(
                name: "Starts outside", workType: .deepWork,
                start: bounds.start.addingTimeInterval(-30 * 60),
                end: bounds.start.addingTimeInterval(30 * 60),
                workSeconds: 60 * 60))
            archive.append(SessionRecord(
                name: "Inside", workType: .learning,
                start: bounds.start.addingTimeInterval(2 * 3_600),
                end: bounds.start.addingTimeInterval(2 * 3_600 + 40 * 60),
                workSeconds: 40 * 60))
            archive.append(SessionRecord(
                name: "Long break", workType: .breakTime,
                start: bounds.start.addingTimeInterval(3 * 3_600),
                end: bounds.start.addingTimeInterval(5 * 3_600),
                workSeconds: 2 * 3_600))
            archive.append(SessionRecord(
                name: "Ends outside", workType: .admin,
                start: bounds.end.addingTimeInterval(-20 * 60),
                end: bounds.end.addingTimeInterval(40 * 60),
                workSeconds: 60 * 60))

            let usage = makeUsageArchive(clock, sessions: [], accurateFrom: bounds.start)
            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview(period: .week)

            expectClose(store.reviewLongestFocusSeconds, 40 * 60,
                        "period-clipped longest focus", &problems)
            expect(store.reviewLongestFocusName == "Inside",
                   "the in-period focus stretch wins", &problems)
            expect(store.reviewWorkTypeShares.allSatisfy { $0.workType != .breakTime },
                   "breaks remain excluded from Review work type", &problems)
            return problems
        }
    }

    /// A named rest is evidence only for its clipped record interval. It cannot
    /// inherit the duration of the larger elided inactivity gap around it.
    private static func testTimelineRestEvidenceStaysCanonical() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        let gap = TimelineGap(start: day.addingTimeInterval(9 * 3_600),
                              end: day.addingTimeInterval(12 * 3_600),
                              xStart: 0.4, xEnd: 0.44)
        let tea = SessionRecord(name: "Tea break", workType: .breakTime,
                                start: day.addingTimeInterval(10 * 3_600),
                                end: day.addingTimeInterval(10.5 * 3_600),
                                workSeconds: 30 * 60)
        // Crosses the gap's right boundary: only the fifteen minutes inside the
        // gap are eligible for its presentation.
        let handover = SessionRecord(name: "Handover", workType: .breakTime,
                                     start: day.addingTimeInterval(11.75 * 3_600),
                                     end: day.addingTimeInterval(12.25 * 3_600),
                                     workSeconds: 30 * 60)

        let evidence = TimelineGapEvidence(gap: gap, breaks: [tea, handover])
        expect(evidence.rests.count == 2,
               "two overlapping canonical rests remain two rest slices", &problems)
        if evidence.rests.count == 2 {
            expectClose(evidence.rests[0].start.timeIntervalSince(day), 10 * 3_600,
                        "the inside rest keeps its start", &problems)
            expectClose(evidence.rests[0].end.timeIntervalSince(day), 10.5 * 3_600,
                        "the inside rest keeps its end", &problems)
            expectClose(evidence.rests[0].duration, 30 * 60,
                        "the inside rest keeps its own duration", &problems)
            expectClose(evidence.rests[1].start.timeIntervalSince(day), 11.75 * 3_600,
                        "the boundary-crossing rest keeps its inside start", &problems)
            expectClose(evidence.rests[1].end.timeIntervalSince(day), 12 * 3_600,
                        "the boundary-crossing rest clips at the gap end", &problems)
            expectClose(evidence.rests[1].duration, 15 * 60,
                        "the boundary-crossing rest labels only its clipped duration", &problems)
        }
        expect(evidence.unknown.count == 2,
               "unknown inactivity remains on both sides of the named evidence", &problems)
        expectClose(evidence.unknown.reduce(0) { $0 + $1.duration }, 135 * 60,
                    "surrounding inactivity stays distinct from named rests", &problems)
        return problems
    }

    /// Focus is an operational surface, so every engine state needs one clear
    /// presentation contract. Awaiting a decision is deliberately exceptional:
    /// the honest answers replace ordinary session controls. Continuations are
    /// equally bounded — a compact action panel must not grow into history.
    private static func testFocusSurfaceStateAndContinuationLimit() -> [String] {
        var problems: [String] = []
        let cases: [(SessionState, FocusSurfaceMode, String, FocusPrimaryAction?)] = [
            (.idle, .idle, "Ready to focus", .start),
            (.running, .running, "Focus in progress", .pause),
            (.paused(reason: .manual), .paused, "Ready to continue?", .resume),
            (.paused(reason: .watching), .watching, "Watching quietly", .resume),
            (.awaitingUserDecision(away: 20 * 60, lastApp: "Xcode"),
             .awaitingDecision, "What happened while you were away?", nil)
        ]

        for (state, expectedMode, expectedPrompt, expectedAction) in cases {
            let mode = FocusSurfaceMode(state: state)
            expect(mode == expectedMode,
                   "\(state) maps to \(expectedMode), got \(mode)", &problems)
            expect(mode.primaryPrompt == expectedPrompt,
                   "\(expectedMode) keeps its primary prompt", &problems)
            expect(mode.primaryAction == expectedAction,
                   "\(expectedMode) keeps one appropriate primary action", &problems)
        }
        expect(!FocusSurfaceMode.awaitingDecision.showsOrdinaryControls,
               "awaiting a decision replaces ordinary session controls", &problems)
        expect(FocusSurfaceMode.running.showsOrdinaryControls,
               "running retains its ordinary controls", &problems)

        let now = base
        let threads = (0..<4).map { index in
            ThreadSummary(threadID: UUID(), name: "Thread \(index)", workType: .deepWork,
                          totalWorked: Double(index + 1) * 600, segments: index + 1,
                          firstStart: now.addingTimeInterval(Double(-index) * 900),
                          lastEnd: now.addingTimeInterval(Double(-index) * 300),
                          isRunning: false)
        }
        let quickStarts = (0..<4).map {
            QuickStart(id: "quick-\($0)", name: "Quick \($0)", workType: .admin)
        }
        let threadRows = FocusContinuationSource.rows(
            threads: threads, quickStarts: quickStarts, limit: 9)
        expect(threadRows == threads.prefix(3).map { .thread($0) },
               "threads are preferred and capped at three", &problems)

        let quickRows = FocusContinuationSource.rows(
            threads: [], quickStarts: quickStarts, limit: 9)
        expect(quickRows == quickStarts.prefix(3).map { .quickStart($0) },
               "quick starts fill the empty thread source and stop at three", &problems)
        expect(FocusContinuationSource.rows(
            threads: threads, quickStarts: quickStarts, limit: 0).isEmpty,
               "a zero continuation limit yields no rows", &problems)
        return problems
    }

    /// The composition guard owns everything around the hero as well as the
    /// hero itself. An unresolved away question must have exactly one exit: an
    /// answer from its four-choice grid. Automatic-session correction remains
    /// available in every other live state, including quiet and declared pauses.
    private static func testFocusSurfaceCompositionGuards() -> [String] {
        var problems: [String] = []

        let awaiting = FocusSurfaceComposition(
            state: .awaitingUserDecision(away: 20 * 60, lastApp: "Xcode"),
            hasPendingDecision: false,
            isAutomatic: true)
        expect(awaiting.mode == .awaitingDecision,
               "engine decision state composes as awaiting decision", &problems)
        expect(!awaiting.showsContinuationSection,
               "awaiting decision suppresses every continuation action", &problems)
        expect(!awaiting.showsAutomaticSessionControls,
               "awaiting decision suppresses automatic correction controls", &problems)

        let previewPending = FocusSurfaceComposition(
            state: .running,
            hasPendingDecision: true,
            isAutomatic: true)
        expect(previewPending.mode == .awaitingDecision
                   && !previewPending.showsContinuationSection
                   && !previewPending.showsAutomaticSessionControls,
               "a preview/live pending flag applies the same whole-surface guard", &problems)

        let automaticStates: [SessionState] = [
            .running,
            .paused(reason: .manual),
            .paused(reason: .watching),
            .paused(reason: .away)
        ]
        for state in automaticStates {
            let composition = FocusSurfaceComposition(
                state: state,
                hasPendingDecision: false,
                isAutomatic: true)
            expect(composition.showsContinuationSection,
                   "\(state) keeps safe continuation composition", &problems)
            expect(composition.showsAutomaticSessionControls,
                   "\(state) keeps automatic correction and Undo available", &problems)
        }

        let manual = FocusSurfaceComposition(
            state: .paused(reason: .manual),
            hasPendingDecision: false,
            isAutomatic: false)
        expect(!manual.showsAutomaticSessionControls,
               "manual sessions do not show automatic correction controls", &problems)
        let idle = FocusSurfaceComposition(
            state: .idle,
            hasPendingDecision: false,
            isAutomatic: true)
        expect(!idle.showsAutomaticSessionControls,
               "idle never exposes automatic-session controls", &problems)
        return problems
    }

    /// Presentation hiding is not an action boundary. A global shortcut or any
    /// future caller can still reach the store directly, so an unresolved Away
    /// decision must reject ordinary stop/start/pause mutations at that shared
    /// App seam while leaving the exact pending evidence intact.
    private static func testAwayDecisionRejectsOrdinarySessionMutations() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Pending evidence")
        clock.advance(20 * 60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(20 * 60)
        engine.transition(on: .awayEnded)
        guard case .awaitingUserDecision(let pendingBefore, _) = engine.state else {
            return ["fixture did not reach awaitingUserDecision: \(engine.state)"]
        }
        let recordsBefore = engine.archive.records
        let store = SessionStore(engine: engine, now: { clock.value })

        store.stop()
        store.togglePause()
        store.startQuick(QuickStart(id: "blocked", name: "Blocked", workType: .admin))

        if case .awaitingUserDecision(let pendingAfter, _) = engine.state {
            expectClose(pendingAfter, pendingBefore,
                        "ordinary actions preserve the pending Away interval", &problems)
        } else {
            problems.append("ordinary actions changed unresolved evidence to \(engine.state)")
        }
        expect(engine.archive.records == recordsBefore,
               "rejected ordinary actions archive no partial session", &problems)
        return problems
    }

    /// The hotkey has three literal outcomes. Pending evidence is not a fourth
    /// kind of stop: it routes back to the existing answer surface and leaves
    /// state untouched. Idle and ordinary live states retain zero-friction
    /// start/stop behaviour through the same store boundary.
    private static func testHotKeyRoutesPendingAwayDecision() -> [String] {
        var problems: [String] = []

        let idleClock = Clock(base)
        let idleEngine = makeEngine(idleClock)
        let idleStore = SessionStore(engine: idleEngine, now: { idleClock.value })
        expect(idleStore.performSessionHotKeyAction() == .started,
               "idle hotkey starts through the shared boundary", &problems)
        expect(idleEngine.state == .running,
               "idle hotkey leaves a running session", &problems)
        expect(idleStore.performSessionHotKeyAction() == .stopped,
               "ordinary live hotkey stops through the shared boundary", &problems)
        expect(idleEngine.state == .idle,
               "ordinary live hotkey leaves an idle session", &problems)

        let pendingClock = Clock(base)
        let pendingEngine = makeEngine(pendingClock)
        pendingEngine.start(workType: .learning, intent: "Pending")
        pendingClock.advance(20 * 60)
        pendingEngine.transition(on: .awayBegan(trigger: .systemSleep))
        pendingClock.advance(20 * 60)
        pendingEngine.transition(on: .awayEnded)
        let pendingStore = SessionStore(engine: pendingEngine, now: { pendingClock.value })
        let recordsBefore = pendingEngine.archive.records

        expect(pendingStore.performSessionHotKeyAction() == .showAwayDecision,
               "pending hotkey routes to the existing Away decision", &problems)
        expect(pendingStore.hasUnresolvedAwayDecision,
               "pending hotkey keeps the decision outstanding", &problems)
        expect(pendingEngine.archive.records == recordsBefore,
               "pending hotkey writes no replacement evidence", &problems)
        return problems
    }

    /// The setting is retained only because it controls a real production list:
    /// the selected app's recent grouped sessions in Today. The rows are newest
    /// first and the configured limit is applied after canonical grouping.
    private static func testSessionsPerAppLimitsProductionAppHistory() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: anchoredNow())
        let clock = Clock(day.addingTimeInterval(12 * 3_600))
        let app = "org.example.editor"
        let usageSessions = (0..<5).map { index -> AppUsageSession in
            let start = day.addingTimeInterval(9 * 3_600 + Double(index * 10 * 60))
            return AppUsageSession(bundleID: app, appName: "Editor",
                                   start: start, end: start.addingTimeInterval(60))
        }
        let usage = makeUsageArchive(clock, sessions: usageSessions, accurateFrom: day)
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        persistence.menuSessionCount = 3
        let engine = SessionEngine(
            store: persistence, archive: makeArchive(clock),
            ownBundleID: "com.example.self", schedulesDwell: false,
            now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)

        let visible = store.sessions(for: app)
        expect(visible.count == 3,
               "configured Today app-session list shows three rows, got \(visible.count)",
               &problems)
        expect(visible.map(\.start) == usageSessions.suffix(3).reversed().map(\.start),
               "the configured list retains the newest grouped app sessions", &problems)
        return problems
    }

    /// A focus session is a thread, not every archived stretch. An app switch is
    /// a change between adjacent app identities inside one focus stretch, not the
    /// first app observed and not a same-app checkpoint split.
    private static func testFocusQualityCountsThreadsAndTransitions() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        let clock = Clock(day.addingTimeInterval(12 * 3_600))
        let sharedThread = UUID()
        let secondThread = UUID()
        let records = [
            SessionRecord(name: "One", workType: .deepWork,
                          start: day.addingTimeInterval(9 * 3_600),
                          end: day.addingTimeInterval(9.5 * 3_600),
                          workSeconds: 30 * 60, threadID: sharedThread),
            SessionRecord(name: "One", workType: .deepWork,
                          start: day.addingTimeInterval(10 * 3_600),
                          end: day.addingTimeInterval(10.5 * 3_600),
                          workSeconds: 30 * 60, threadID: sharedThread),
            SessionRecord(name: "Two", workType: .admin,
                          start: day.addingTimeInterval(11 * 3_600),
                          end: day.addingTimeInterval(11.5 * 3_600),
                          workSeconds: 30 * 60, threadID: secondThread)
        ]
        func use(_ bundleID: String, _ startMinute: Int, _ endMinute: Int)
            -> AppUsageSession {
            AppUsageSession(bundleID: bundleID, appName: bundleID,
                            start: day.addingTimeInterval(Double(startMinute * 60)),
                            end: day.addingTimeInterval(Double(endMinute * 60)))
        }
        let usage = makeUsageArchive(clock, sessions: [
            use("app.a", 9 * 60, 9 * 60 + 10),
            use("app.a", 9 * 60 + 10, 9 * 60 + 15),
            use("app.b", 9 * 60 + 15, 9 * 60 + 30),
            use("app.b", 10 * 60, 10 * 60 + 10),
            use("app.b", 10 * 60 + 10, 10 * 60 + 20),
            use("app.c", 10 * 60 + 20, 10 * 60 + 30),
            use("app.c", 11 * 60, 11 * 60 + 15),
            use("app.a", 11 * 60 + 15, 11 * 60 + 30)
        ], accurateFrom: day)
        let archive = makeArchive(clock, records: records, calendar: calendar)
        let quality = DashboardStats(sessions: archive, usage: usage,
                                     calendar: calendar, now: { clock.value })
            .focusQuality(for: day)

        expect(quality.sessionCount == 2,
               "three stretches across two thread IDs count as two sessions; got "
                   + "\(quality.sessionCount)", &problems)
        expectClose(quality.switchesPerSession, 1.5,
                    "three real app transitions over two thread sessions", &problems)
        return problems
    }

    /// Automatic correction is an App-boundary operation: Core knows how to
    /// resume/adopt/discard a session, while only SessionStore can also notify
    /// the coordinator to resume background usage tracking after declared Away.
    private static func testDeclaredAwayAutomaticCorrectionRoutes() -> [String] {
        var problems: [String] = []

        func makeAutomatic(_ pause: PauseReason?, declaredAwayFor: TimeInterval = 0)
            -> (store: SessionStore, engine: SessionEngine,
                archive: SessionArchive, clock: Clock) {
            let clock = Clock(base)
            let archive = SessionArchive(directory: scratchDirectory(), now: { clock.value })
            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            persistence.breakThreshold = FocusConstants.defaultThreshold
            persistence.longAwayCap = FocusConstants.defaultLongAwayCap
            let engine = SessionEngine(
                store: persistence,
                archive: archive,
                ownBundleID: "com.test",
                schedulesDwell: false,
                now: { clock.value })
            engine.start(workType: .deepWork, intent: "Detected coding", isAuto: true)
            clock.advance(12 * 60)
            if let pause {
                switch pause {
                case .away:
                    engine.transition(on: .markedAway)
                    clock.advance(declaredAwayFor)
                case .watching:
                    engine.transition(on: .watchingObserved(
                        seconds: FocusConstants.idlePauseThreshold))
                default:
                    engine.transition(on: .manualPause)
                }
            }
            // Exercise the real persisted automatic ownership that can survive
            // into every paused state without adding a test-only engine setter.
            var snapshot = engine.snapshot()
            snapshot.isAuto = true
            engine.restore(from: snapshot)
            return (SessionStore(engine: engine, now: { clock.value }),
                    engine, archive, clock)
        }

        let adopted = makeAutomatic(.away)
        let adoptedThread = adopted.engine.activeThreadID
        var adoptTrackingResumes = 0
        var adoptResumedBeforeCorrection = false
        adopted.store.onAwayEnded = {
            adoptTrackingResumes += 1
            adoptResumedBeforeCorrection = adopted.engine.state == .running
                && adopted.store.isAutoSession
        }
        adopted.store.intent = "Owned coding"
        adopted.store.applyAutomaticSessionCorrection()
        expect(adoptTrackingResumes == 1 && adoptResumedBeforeCorrection,
               "declared-Away adoption resumes usage tracking exactly once, before correction",
               &problems)
        expect(adopted.engine.state == .running && !adopted.store.isAutoSession,
               "adoption resumes as a user-owned running session", &problems)
        expect(adopted.store.activeIntent == "Owned coding"
                   && adopted.engine.activeThreadID == adoptedThread,
               "same-type adoption retains the session thread and requested intent", &problems)
        expect(adopted.archive.records.isEmpty,
               "adoption does not create an artificial archive seam", &problems)

        let reclassified = makeAutomatic(.away)
        let oldThread = reclassified.engine.activeThreadID
        var reclassifyTrackingResumes = 0
        var reclassifyResumedBeforeCorrection = false
        reclassified.store.onAwayEnded = {
            reclassifyTrackingResumes += 1
            reclassifyResumedBeforeCorrection = reclassified.engine.state == .running
                && reclassified.store.isAutoSession
        }
        reclassified.store.intent = "Admin follow-up"
        reclassified.store.workType = .admin
        reclassified.store.applyAutomaticSessionCorrection()
        expect(reclassifyTrackingResumes == 1 && reclassifyResumedBeforeCorrection,
               "declared-Away reclassification resumes tracking once, before correction",
               &problems)
        expect(reclassified.engine.state == .running
                   && reclassified.engine.activeWorkType == .admin
                   && reclassified.store.activeIntent == "Admin follow-up"
                   && !reclassified.store.isAutoSession,
               "reclassification starts the requested user-owned work", &problems)
        expect(reclassified.engine.activeThreadID != oldThread
                   && reclassified.archive.records.last?.isAuto == true,
               "reclassification closes the detected work and starts a fresh thread", &problems)

        let undone = makeAutomatic(.away)
        var undoEvents: [String] = []
        undone.store.onAwayEnded = { undoEvents.append("tracking resumed") }
        undone.store.onAutoSessionUndone = { undoEvents.append("automatic session undone") }
        undone.store.undoAutomaticSessionCorrection()
        expect(undoEvents == ["automatic session undone", "tracking resumed"],
               "declared-Away Undo discards before resuming tracking exactly once", &problems)
        expect(undone.engine.state == .idle
                   && undone.archive.records.isEmpty,
               "Undo retains discard and detector-suppression semantics", &problems)

        for pause in [Optional<PauseReason>.none, .some(.manual), .some(.watching)] {
            let ordinary = makeAutomatic(pause)
            var trackingResumes = 0
            ordinary.store.onAwayEnded = { trackingResumes += 1 }
            ordinary.store.intent = "Ordinary correction"
            ordinary.store.applyAutomaticSessionCorrection()
            expect(trackingResumes == 0,
                   "\(String(describing: pause)) correction does not fake an away end",
                   &problems)
            expect(ordinary.engine.state == .running && !ordinary.store.isAutoSession,
                   "\(String(describing: pause)) keeps its existing adoption semantics",
                   &problems)
        }

        let undoBoundaries: [(label: String, seconds: TimeInterval)] = [
            ("just below break threshold", FocusConstants.defaultThreshold - 1),
            ("at break threshold", FocusConstants.defaultThreshold),
            ("above break threshold", FocusConstants.defaultThreshold + 1),
            ("beyond long-away cap", FocusConstants.defaultLongAwayCap + 1)
        ]
        for boundary in undoBoundaries {
            let scenario = makeAutomatic(.away, declaredAwayFor: boundary.seconds)
            var events: [String] = []
            scenario.store.onAutoSessionUndone = {
                events.append("automatic session undone")
            }
            scenario.store.onAwayEnded = { events.append("tracking resumed") }
            scenario.store.undoAutomaticSessionCorrection()
            expect(events == ["automatic session undone", "tracking resumed"],
                   "\(boundary.label) Undo emits discard then one tracking resume; got \(events)",
                   &problems)
            expect(scenario.engine.state == .idle && !scenario.store.isAutoSession,
                   "\(boundary.label) Undo ends idle without automatic ownership",
                   &problems)
            expect(scenario.archive.records.isEmpty,
                   "\(boundary.label) Undo retains no detected work or Away record",
                   &problems)
        }
        return problems
    }

    /// A pristine install has no Application Support directory yet. Reveal
    /// creates it before asking Finder, while both creation and Finder refusal
    /// produce deterministic, concrete diagnostics.
    private static func testRevealDataFolderWorkflow() -> [String] {
        var problems: [String] = []
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pristine = root.appendingPathComponent("pristine/data", isDirectory: true)
        var opened: [URL] = []
        var logs: [String] = []

        let revealed = SettingsModel.revealDataFolder(
            at: pristine,
            open: { opened.append($0); return true },
            log: { logs.append($0) })
        expect(revealed, "a pristine data folder is created and revealed", &problems)
        expect(FileManager.default.fileExists(atPath: pristine.path),
               "the pristine data directory now exists", &problems)
        expect(opened == [pristine] && logs.isEmpty,
               "Finder receives the exact directory without a failure log", &problems)

        logs = []
        let refused = SettingsModel.revealDataFolder(
            at: pristine, open: { _ in false }, log: { logs.append($0) })
        expect(!refused, "Finder refusal is returned as failure", &problems)
        expect(logs.count == 1 && logs[0].contains(pristine.path)
               && logs[0].contains("could not reveal data folder"),
               "Finder refusal logs the concrete directory", &problems)

        let blocker = root.appendingPathComponent("not-a-directory")
        try? Data("blocked".utf8).write(to: blocker)
        let impossible = blocker.appendingPathComponent("child", isDirectory: true)
        logs = []
        var attemptedOpen = false
        let created = SettingsModel.revealDataFolder(
            at: impossible,
            open: { _ in attemptedOpen = true; return true },
            log: { logs.append($0) })
        expect(!created && !attemptedOpen,
               "a creation failure never asks Finder to open a missing path", &problems)
        expect(logs.count == 1 && logs[0].contains(impossible.path)
               && logs[0].contains("could not create data folder"),
               "creation failure logs the concrete directory", &problems)
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
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let settings = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let view = PopoverView(store: store, settings: settings,
                                   metricsOverride: metrics, scrolls: false)
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
        let entries = SessionDigest.entries(records: records, running: running, now: at(15.2), day: day)
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

    /// A record crossing midnight belongs to each day only for its overlap. A
    /// named break remains evidence in the digest, but never becomes focus in
    /// the dashboard's session, bracket, count, or work-type figures.
    ///
    /// This catches the old raw-record path: it rendered a 23:30–00:30 record
    /// as a full hour on either day and let break records into focus quality.
    private static func testDayDigestAndFocusAreDayScoped() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(base)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else {
            return ["could not make yesterday"]
        }
        let crossMidnight = SessionRecord(name: "Night shift", workType: .deepWork,
                                          start: yesterday.addingTimeInterval(23.5 * 3_600),
                                          end: day.addingTimeInterval(0.5 * 3_600),
                                          workSeconds: 3_600)
        let dinner = SessionRecord(name: "Dinner", workType: .breakTime,
                                   start: day.addingTimeInterval(9 * 3_600),
                                   end: day.addingTimeInterval(9.5 * 3_600),
                                   workSeconds: 1_800)
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        archive.append(crossMidnight)
        archive.append(dinner)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        usage.record(AppUsageSession(bundleID: "com.night", appName: "Night",
                                     start: day, end: day.addingTimeInterval(0.5 * 3_600)))
        usage.record(AppUsageSession(bundleID: "com.dinner", appName: "Dinner",
                                     start: day.addingTimeInterval(9 * 3_600),
                                     end: day.addingTimeInterval(9.5 * 3_600)))

        let previousDigest = SessionDigest.entries(records: [crossMidnight], running: nil,
                                                   now: day, day: yesterday, calendar: calendar)
        let previousRows = previousDigest.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        expectClose(previousRows.first?.start.timeIntervalSince(yesterday) ?? -1, 23.5 * 3_600,
                    "the previous-day row begins at 23:30", &problems)
        expectClose(previousRows.first?.end.timeIntervalSince(yesterday) ?? -1, 24 * 3_600,
                    "the previous-day row ends at midnight", &problems)
        expectClose(previousRows.first?.worked ?? 0, 1_800,
                    "the previous-day row receives 30m of work credit", &problems)

        let digest = SessionDigest.entries(records: archive.records(on: day),
                                           running: nil, now: day.addingTimeInterval(10 * 3_600),
                                           day: day,
                                           calendar: calendar)
        let focusRows = digest.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        expect(focusRows.count == 1, "only the work record is a session row", &problems)
        expectClose(focusRows.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "the selected-day row begins at midnight", &problems)
        expectClose(focusRows.first?.end.timeIntervalSince(day) ?? -1, 1_800,
                    "the selected-day row ends after its 30m overlap", &problems)
        expectClose(focusRows.first?.worked ?? 0, 1_800,
                    "the selected-day row receives 30m of work credit", &problems)
        expect(digest.contains { entry in
            if case .rest(let rest) = entry { return rest.name == "Dinner" }
            return false
        }, "the named break remains a rest row", &problems)

        let live = RunningThread(threadID: UUID(), name: "Late deploy", workType: .deepWork,
                                 start: yesterday.addingTimeInterval(23.75 * 3_600), worked: 1_800)
        let runningDigest = SessionDigest.entries(records: [], running: live,
                                                  now: day.addingTimeInterval(0.25 * 3_600),
                                                  day: day, calendar: calendar)
        let runningRows = runningDigest.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        expectClose(runningRows.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "a running span is clipped at today's midnight", &problems)
        expectClose(runningRows.first?.end.timeIntervalSince(day) ?? -1, 900,
                    "a running span ends at now inside the selected day", &problems)
        expectClose(runningRows.first?.worked ?? 0, 900,
                    "a running span receives only its 15m day credit", &problems)

        let stats = DashboardStats(sessions: archive, usage: usage,
                                   calendar: calendar, now: { clock.value })
        let focus = stats.focusSessions(for: day)
        expect(focus.count == 1, "break records are not focus sessions, got \(focus.count)", &problems)
        expectClose(focus.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "focus session starts inside the selected day", &problems)
        expectClose(focus.first?.end.timeIntervalSince(day) ?? -1, 1_800,
                    "focus session ends inside the selected day", &problems)
        expectClose(focus.first?.workSeconds ?? 0, 1_800,
                    "focus session has only this day's work credit", &problems)
        let spans = stats.focusSpans(for: day)
        expect(spans.count == 1, "the break does not create a focus bracket", &problems)
        expectClose(spans.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "the focus bracket begins inside the day", &problems)
        expectClose(spans.first?.end.timeIntervalSince(day) ?? -1, 1_800,
                    "the focus bracket ends inside the day", &problems)
        let quality = stats.focusQuality(for: day)
        expect(quality.sessionCount == 1,
               "the break does not increase the focus session count, got \(quality.sessionCount)", &problems)
        expect(quality.byWorkType.allSatisfy { $0.workType != WorkType.breakTime },
               "the break is absent from focus work-type shares", &problems)
        return problems
    }

    /// A running stretch can begin yesterday while the dashboard is showing
    /// today. Its work-type credit must be the overlap since local midnight,
    /// otherwise last night's work inflates today's focus-quality composition.
    private static func testLiveFocusQualityClipsAtMidnight() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        let clock = Clock(day.addingTimeInterval(-30 * 60))
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, calendar: calendar,
                                     now: { clock.value })
        archive.append(SessionRecord(name: "Morning admin", workType: .admin,
                                     start: day, end: day.addingTimeInterval(30 * 60),
                                     workSeconds: 30 * 60))
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self",
                                   schedulesDwell: false, now: { clock.value })
        engine.start(workType: .deepWork, intent: "Overnight deploy")
        clock.advance(60 * 60)

        let usage = AppUsageArchive(directory: directory, calendar: calendar,
                                    now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)

        let deep = store.focusQuality.byWorkType.first { $0.workType == .deepWork }
        let admin = store.focusQuality.byWorkType.first { $0.workType == .admin }
        expectClose(engine.elapsed, 60 * 60,
                    "the underlying running stretch still spans the full hour", &problems)
        expectClose(engine.elapsedToday(), 30 * 60,
                    "only thirty running minutes belong to today", &problems)
        expectClose(deep?.seconds ?? -1, 30 * 60,
                    "today's live Deep Work quality credit is midnight-clipped", &problems)
        expectClose(admin?.seconds ?? -1, 30 * 60,
                    "today's archived Admin quality credit remains thirty minutes", &problems)
        expectClose(deep?.share ?? -1, 0.5,
                    "today's work-type share excludes last night's running portion", &problems)
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
        archive.append(SessionRecord(name: "T overlap", workType: .admin,
                                     start: today.addingTimeInterval(120),
                                     end: today.addingTimeInterval(3_400), workSeconds: 3_280))
        let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                   schedulesDwell: false)
        let store = SessionStore(engine: engine)
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.test", idle: .disabled)
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.refresh()
        expect(store.timelineSegments.map(\.bundleID) == ["com.t"],
               "today's segments on today, got \(store.timelineSegments.map(\.bundleID))", &problems)
        store.stepDay(by: -1)
        expect(store.timelineSegments.map(\.bundleID) == ["com.y"],
               "the dashboard browses yesterday, got \(store.timelineSegments.map(\.bundleID))", &problems)
        expect(store.glanceTimeline.map(\.bundleID) == ["com.t"],
               "the glance band stays on today, got \(store.glanceTimeline.map(\.bundleID))", &problems)
        expect(store.glanceBrackets.count == 1 && store.focusBrackets.count == 1,
               "brackets merge today's overlap for the glance and preserve yesterday's page bracket", &problems)
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
