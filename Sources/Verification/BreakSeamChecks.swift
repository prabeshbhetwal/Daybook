import Foundation

/// Where the break feature meets the rest of the app: the usage tracker, the
/// presence gate, the reminder's delivery, stored values from other builds and
/// the break's own controls. Found by the whole-branch review, after the
/// suites that check the feature piece by piece had passed.
///
/// The checks are in `BreakSeamTrackingChecks` (the tracker and presence),
/// `BreakSeamStoreChecks` (reminders and the sustained end),
/// `BreakSeamRecordChecks` (what a snapshot or a stored record may hold) and
/// `BreakSeamSurfaceChecks` (the controls).
enum BreakSeamChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A break records no app use: a switch, an unlock and input leave the tracker stopped",
         breakRecordsNoAppUse),
        ("A reminder nobody saw is asked again, and so is a Later that ran out of sight",
         unseenReminderIsAskedAgain),
        ("A break that ran out its cap proves nobody is back, and one the person ended does",
         capExpiryProvesNoPresence),
        ("The break-over prompt waits for a person: not behind the wake gate or a lock",
         breakOverWaitsForPresence),
        ("A stored origin from a later build reads as none and keeps the record",
         futureOriginKeepsRecord),
        ("A restored break with an impossible planned end is not a live break",
         impossibleBreakIsNotRestored),
        ("The countdown text survives values no break has",
         countdownIsTotal),
        ("The break length chevron meets the minimum target size",
         lengthChevronMeetsTargetSize),
        ("The length menu's spoken names contain their visible text",
         spokenNamesContainVisibleText),
        ("The +5 min button's spoken name contains its visible text",
         extendNameContainsVisibleText),
        ("An end that input brings and the disk refuses is tried again every five seconds",
         sustainedEndRetriesOnTheGate),
        ("How a break ended is recorded: the cap and a launch past it are not the person's",
         breakEndKnowsWhoEndedIt),
    ]

    /// A real usage tracker on the fixture's store, on the fixture's clock, with
    /// the coordinator's one line for a break beginning: the tracker stops.
    @MainActor
    static func trackerOn(_ f: BreakStoreChecks.Fixture) -> AppUsageTracker {
        let tracker = AppUsageTracker(archive: f.usage, ownBundleID: "com.test",
                                      idle: .disabled, now: { f.clock.value })
        f.store.attach(tracker: tracker, usage: f.usage)
        f.store.onBreakBegan = { tracker.suspend() }
        return tracker
    }
}
