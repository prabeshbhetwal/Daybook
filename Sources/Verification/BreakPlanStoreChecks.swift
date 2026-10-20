import Foundation

/// What the store does with a prompt that carries its own numbers: the length
/// Start break begins with, and when the log says the reminder fell due. The
/// phase-1 plan makes every prompt carry its tier's numbers, so these hand the
/// store prompts a rhythm would raise.
enum BreakPlanStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Start break begins at the length the reminder offered", startBeginsAtOfferedLength),
        ("A reminder is logged from the work its plan asked for", loggedFromItsOwnThreshold),
    ]

    private static func startBeginsAtOfferedLength() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // One store per break: a break in progress refuses the next.
            @MainActor func planned(_ prompt: BreakPrompt) -> TimeInterval? {
                guard let f = BreakStoreChecks.make() else { return nil }
                defer { f.close() }
                f.store.startBreak(from: prompt)
                return f.store.activeBreak?.plannedLength
            }
            let deep = BreakPrompt(tier: .cognitive, worked: 5_400, appName: nil, offeredBreak: 900)
            expect(planned(deep) == 900, "a main reminder offering 15 minutes begins 15, got "
                   + "\(String(describing: planned(deep)))", &problems)
            let short = BreakPrompt(tier: .cognitive, worked: 600, appName: nil, offeredBreak: 60)
            expect(planned(short) == 60, "and one offering a minute begins a minute, not five", &problems)
            let flow = BreakPrompt(tier: .ultradian, worked: 5_400, appName: nil, offeredBreak: 1_092)
            expect(planned(flow) == 1_092, "the guard begins what it offered", &problems)
            let eyes = BreakPrompt(tier: .micro, worked: 1_200, appName: nil)
            expect(planned(eyes) == BreakLength.standard, "an Eyes glance begins the standard five minutes",
                   &problems)
            return problems
        }
    }

    private static func loggedFromItsOwnThreshold() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            // A guard that waited out Deep work's block: due at 105 minutes, shown at 110.
            let guardPrompt = BreakPrompt(tier: .ultradian, worked: 6_600, appName: nil, dueAfterWork: 6_300)
            f.store.logShown(guardPrompt, at: f.clock.value)
            let entry = f.store.breakLog.prompts.first { $0.id == guardPrompt.id }
            expect(entry.map { $0.shown.timeIntervalSince($0.due) } == 300 && entry?.kind == .stretchGuard,
                   "it fell due five minutes before it was shown, not at the tier's own 90", &problems)

            let long = BreakPrompt(tier: .cognitive, worked: 1_800, appName: nil, isLong: true,
                                   dueAfterWork: 1_500)
            f.store.logShown(long, at: f.clock.value)
            let longEntry = f.store.breakLog.prompts.first { $0.id == long.id }
            expect(longEntry?.kind == .long && longEntry.map { $0.shown.timeIntervalSince($0.due) } == 300,
                   "a long break is logged as one", &problems)
            return problems
        }
    }
}
