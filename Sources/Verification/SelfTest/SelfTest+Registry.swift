import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Every check in run order. A check's position is its number in the
    /// output, and comments cite those numbers, so new checks go at the end.
    static var registeredTests: [(String, () -> [String])] {
        earlierCoreTests + laterCoreTests
            + StoryAccountingChecks.tests + StoryNavigationChecks.tests + UsagePersistenceChecks.tests
            + UnreadableHistoryChecks.tests
            + PreferenceChecks.tests
            + HistoryKeepingChecks.tests
            + PauseAllocationChecks.tests
            + StoryPresentationChecks.tests + StoryCorrectionChecks.tests + StorySettingsChecks.tests
            + StoryInteractionChecks.tests + RecordedActivityChecks.tests + ContinuationChecks.tests
            + DecisionHistoryChecks.tests + DecisionRecoveryChecks.tests + StoryWorkspaceChecks.tests
            + CompactControlsChecks.tests + SessionMetadataChecks.tests + ActivityRuleChecks.tests
            + StoryIntegrationChecks.tests + CategoryChecks.tests + SessionReportChecks.tests
            + SavedActivityChecks.tests + FirstRunChecks.tests + EfficiencyChecks.tests
            + RedundancyChecks.tests + HistoryJournalChecks.tests + HistoryTreeChecks.tests
            + HistorySearchChecks.tests + HistoryPathChecks.tests + AppPresenceChecks.tests + NameCategoryChecks.tests + StoryRailFiguresChecks.tests + UpdatePreferenceChecks.tests + BreakCountingChecks.tests
            + SessionAccessibilityChecks.tests + SettingsAccessibilityChecks.tests
            + DayStoryAccessibilityChecks.tests + RailAccessibilityChecks.tests
            + LongAwayRestoreChecks.tests + PanelRestChecks.tests
            + AutomaticNamingChecks.tests + GlobalShortcutChecks.tests + ClockTextChecks.tests
            + NameMigrationChecks.tests
            + HistoryAppLensChecks.tests
            + JournalRecoveryChecks.tests
            + PercentTextChecks.tests
            + HistoryOverviewChecks.tests
            + HistoryCalendarChecks.tests
            + HistoryNoticeChecks.tests
            + FixtureClockChecks.tests
            + HistoryFloorChecks.tests
            + CalendarChecks.tests
            + HistoryAppLensFigureChecks.tests
            + PeriodCalendarChecks.tests
            + AuditRepairChecks.tests
            + InsightHourChecks.tests
            + EditorAndReportChecks.tests
            + SwitchingAndHourChecks.tests
            + RecoveryRetryChecks.tests
            + HistorySessionIDChecks.tests
            + GoalCreditAndPowerLogChecks.tests
            + HistoryLensFactChecks.tests
            + InterfaceZoomChecks.tests
            + ZoomWindowChecks.tests
            + BlankPreferencesLaunchChecks.tests
            + SettingsAlignmentChecks.tests
            + ComponentEdgeChecks.tests
            + AskChecks.tests
            + AskLookupChecks.tests
            + AskLookupVolumeChecks.tests
            + AskModelChecks.tests
            + HistoryLivePatchChecks.tests
            + AskThreadChecks.tests
            + AskRunningSessionChecks.tests
            + AskRangeZoneChecks.tests
            + AskLookupDetailChecks.tests
            + AskLiveAppTimeChecks.tests
            + AskOverlapChecks.tests
    }

    /// SelfTest's own checks 1 to 107.
    static var earlierCoreTests: [(String, () -> [String])] {
        [
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
            ("Cleanup removes only emptied preference files", testEmptiedPreferenceSweep),
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
            ("A due break is said once: HUD when present, notification when not",
             testBreakReminderUsesOneChannel),
        ]
    }
}
