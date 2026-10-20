import Foundation

/// What the break log records of a plan: the rhythm in force on a day, named
/// by preset, and readable by a build from before the rhythms.
enum BreakSnapshotChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The plan's snapshot names the rhythm, and off is off", snapshotNamesRhythm),
        ("A rhythm snapshot reads in both directions", snapshotDecodesBothWays),
    ]

    private static func snapshotNamesRhythm() -> [String] {
        var problems: [String] = []
        expect(BreakPlan.standard.snapshot
               == BreakRhythmSnapshot(workMinutes: 50, breakMinutes: 5, eyes: true, guardMinutes: 90,
                                      override: nil, preset: "steady"), "the standard plan is Steady", &problems)
        let pomodoro = BreakPlan(rhythm: BreakRhythm(.pomodoro), eyes: false, guardLength: nil, override: .week)
        expect(pomodoro.snapshot.longEvery == 4 && pomodoro.snapshot.longMinutes == 15
               && pomodoro.snapshot.override == "week" && pomodoro.snapshot.preset == "pomodoro",
               "Pomodoro records its long break and the override", &problems)
        expect(BreakPlan(rhythm: nil, eyes: true, guardLength: 5_400, override: nil).snapshot.preset == "off",
               "No reminders is off", &problems)
        let flow = BreakPlan(rhythm: BreakRhythm(.flow), eyes: true, guardLength: 5_400, override: nil).snapshot
        expect(flow.workMinutes == nil && flow.breakMinutes == nil && flow.preset == "flow",
               "Flow has no fixed numbers", &problems)
        expect(BreakRhythmSnapshot.off == BreakRhythmSnapshot(eyes: false, preset: "off"), "off is off", &problems)
        expect(BreakRhythmSnapshot.fromTiers(Set(BreakTier.allCases)) == BreakPlan.standard.snapshot
               && BreakRhythmSnapshot.fromTiers([]) == BreakRhythmSnapshot(eyes: false, preset: "off"),
               "the phase-1 switches read through the plan", &problems)
        // An Eyes prompt on a day nothing was noted for says Eyes was on.
        let log = BreakLog(directory: SelfTest.scratchDirectory(), writeOverride: { _ in nil })
        log.noteEyesPrompt(at: SelfTest.base)
        expect(log.days.first?.rhythm == BreakRhythmSnapshot(eyes: true) && log.days.first?.eyesPrompts == 1,
               "an Eyes prompt on an unnoted day records Eyes on", &problems)
        return problems
    }

    private static func snapshotDecodesBothWays() -> [String] {
        var problems: [String] = []
        let old = #"{"workMinutes":50,"breakMinutes":5,"eyes":true,"guardMinutes":90}"#
        let decoded = try? JSONDecoder().decode(BreakRhythmSnapshot.self, from: Data(old.utf8))
        expect(decoded?.workMinutes == 50 && decoded?.guardMinutes == 90 && decoded?.preset == nil
               && decoded?.longEvery == nil && decoded?.longMinutes == nil,
               "a phase-1 snapshot reads, with no preset", &problems)

        struct PhaseOne: Codable, Equatable {
            var workMinutes: Int?
            var breakMinutes: Int?
            var eyes: Bool
            var guardMinutes: Int?
            var override: String?
        }
        let written = try? JSONEncoder().encode(BreakPlan.standard.snapshot)
        let back = written.flatMap { try? JSONDecoder().decode(PhaseOne.self, from: $0) }
        expect(back == PhaseOne(workMinutes: 50, breakMinutes: 5, eyes: true, guardMinutes: 90, override: nil),
               "a phase-1 build reads what this one writes", &problems)
        let full = BreakPlan(rhythm: BreakRhythm(.pomodoro), eyes: true, guardLength: 5_400, override: .today).snapshot
        let again = (try? JSONEncoder().encode(full)).flatMap { try? JSONDecoder().decode(BreakRhythmSnapshot.self, from: $0) }
        expect(again == full, "a snapshot with every field set round-trips", &problems)
        return problems
    }
}
