import Foundation

/// Reminders that follow a plan: a rhythm, Eyes, and the long-stretch guard.
/// Every run starts at minute 0 and ends at the minute under test, so the
/// figures read as "N minutes unbroken".
enum BreakPlanChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Someone who never touched settings gets the same three reminders", standardPlanMatchesTiers),
        ("The guard resets on a credited rest, never on Skip", guardResetsOnCreditedRest),
        ("Eyes stays quiet within 5 minutes of a main break", eyesQuietNearMainBreak),
        ("Pomodoro, Deep work and Custom prompt at their own numbers", presetsPromptAtTheirNumbers),
        ("Flow has no main prompt, and its guard offers a fifth of the stretch", flowPromptsOnlyTheGuard),
        ("A Flow rest counts when it reaches the suggestion", flowRestReachesSuggestion),
        ("The guard follows a long main block rather than racing it", guardFollowsLongBlock),
        ("No reminders turns off the main rhythm only", noRemindersKeepsAddOns),
        ("A repeat waits for the plan's own work length", repeatWaitsForPlanLength),
        ("Changing the rhythm under a Later neither crashes nor silences", rhythmChangeUnderLater),
        ("Custom extremes behave", customExtremes),
    ]

    private static let start = SelfTest.base

    private static func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private static func stretch(_ from: Double, _ to: Double) -> AppUsageSession {
        AppUsageSession(bundleID: "com.a", appName: "Alpha", start: at(from), end: at(to))
    }

    /// A plan on `preset` (nil is "No reminders") with Eyes and a guard of
    /// `guardMinutes` (nil for none).
    private static func plan(_ preset: BreakPreset?, eyes: Bool = true, guardMinutes: Int? = 90,
                             custom: CustomRhythm = CustomRhythm()) -> BreakPlan {
        BreakPlan(rhythm: preset.map { BreakRhythm($0, custom: custom) }, eyes: eyes,
                  guardLength: guardMinutes.map { TimeInterval($0 * 60) }, override: nil)
    }

    /// The answer after `minutes` of work with no break at all.
    private static func eval(_ minutes: Double, _ plan: BreakPlan = .standard, last: BreakNotice? = nil,
                             clock: BreakClock = BreakClock()) -> BreakReminder.Evaluation {
        BreakReminder.evaluate([stretch(0, minutes)], now: at(minutes), last: last, plan: plan, clock: clock)
    }

    private static func standardPlanMatchesTiers() -> [String] {
        var problems: [String] = []
        func due(_ m: Double) -> BreakTier? { eval(m).due }
        func prompt(_ m: Double) -> BreakPrompt? { eval(m).prompt }
        expect(due(19) == nil && due(21) == .micro && due(51) == .cognitive && due(91) == .ultradian,
               "20, 50 and 90 minutes are still the three thresholds", &problems)
        expect(prompt(21)?.title == "Look away for 30 seconds" && prompt(51)?.title == "Take 5 minutes"
               && prompt(91)?.title == "Step away for 15 minutes",
               "the three titles read as before: \(String(describing: [prompt(21)?.title, prompt(51)?.title, prompt(91)?.title]))",
               &problems)
        expect(prompt(51)?.breakLength == 300 && prompt(91)?.breakLength == 900
               && prompt(51)?.kind == .main && prompt(91)?.kind == .stretchGuard && prompt(21)?.kind == .eyes,
               "each prompt carries its length and kind", &problems)
        expect(prompt(51)?.threshold == 3_000 && prompt(91)?.threshold == 5_400 && prompt(21)?.threshold == 1_200,
               "and the work it was due after", &problems)
        expect(eval(10).breakLength == 300, "Start break begins at Steady's five minutes", &problems)
        expect(BreakPlan.standard == BreakPlan(tiers: Set(BreakTier.allCases))
               && BreakPlan.standard.tiers == BreakTier.allCases, "the migration of all three is the standard plan",
               &problems)
        let two = BreakPlan(tiers: [.micro, .ultradian])
        expect(two.tiers == [.micro, .ultradian] && two.rhythm == nil && BreakPlan(tiers: []).tiers.isEmpty,
               "each old switch maps on its own", &problems)
        return problems
    }

    private static func guardResetsOnCreditedRest() -> [String] {
        var problems: [String] = []
        // An hour, a six-minute gap, forty minutes more.
        let rested = [stretch(0, 60), stretch(66, 106)]
        let result = BreakReminder.evaluate(rested, now: at(106), last: nil)
        expect(result.due == .micro,
               "a 6-minute gap is a credited rest, so the guard is not due (old: .ultradian), got "
               + "\(String(describing: result.due))", &problems)
        expect(result.prompt?.tier == .micro && result.prompt?.worked == 40 * 60,
               "Eyes is all that is asked for, after 40 minutes", &problems)

        var skipped = BreakClock()
        skipped.skip(.ultradian, at: at(35))
        skipped.skip(.cognitive, at: at(35))
        expect(eval(95, clock: skipped).due == .ultradian, "Skip does not restart the guard", &problems)
        var credited = BreakClock()
        credited.credit(at: at(60))
        expect(eval(95, clock: credited).due == .micro, "a credited rest restarts it", &problems)
        return problems
    }

    private static func eyesQuietNearMainBreak() -> [String] {
        var problems: [String] = []
        // Quiet means off for this answer: not due, not the next, and no prompt.
        let pomodoro = eval(21, plan(.pomodoro))
        expect(pomodoro.due == nil && pomodoro.prompt == nil && pomodoro.next?.tier == .cognitive
               && pomodoro.next?.seconds == 240,
               "Pomodoro at 21 minutes: the main break is 4 minutes off, so Eyes is not due and the countdown names it",
               &problems)
        expect(eval(41).prompt?.tier == .micro, "Steady at 41 minutes: the main break is 9 off, Eyes shows", &problems)
        let said = BreakNotice(tier: .micro, at: at(46).addingTimeInterval(-1_300))
        let steady = eval(46, last: said)
        expect(steady.prompt == nil && steady.due == nil && steady.next?.tier == .cognitive
               && steady.next?.seconds == 240, "Steady at 46 minutes: 4 off, Eyes is out of the way", &problems)

        let noMain = plan(nil)
        expect(eval(80, noMain).prompt?.tier == .micro && eval(86, noMain).prompt == nil,
               "the guard 4 minutes off quiets Eyes as well", &problems)
        expect(eval(86, noMain).due == nil && eval(86, noMain).next?.tier == .ultradian,
               "and the countdown names the guard", &problems)
        return problems
    }

    private static func presetsPromptAtTheirNumbers() -> [String] {
        var problems: [String] = []
        let pomodoro = plan(.pomodoro)
        expect(eval(24, pomodoro).due != .cognitive, "Pomodoro is not due at 24 minutes", &problems)
        let p26 = eval(26, pomodoro)
        expect(p26.due == .cognitive && p26.prompt?.threshold == 1_500 && p26.prompt?.breakLength == 300,
               "Pomodoro is due at 25 with a 5-minute break", &problems)

        let deep = eval(91, plan(.deepWork))
        expect(deep.due == .cognitive && deep.prompt?.title == "Take 15 minutes"
               && deep.prompt?.breakLength == 900,
               "Deep work at 91 is the main break, not the guard", &problems)

        let custom = plan(.custom, custom: CustomRhythm(workMinutes: 40, breakMinutes: 8))
        let c41 = eval(41, custom)
        expect(c41.due == .cognitive && c41.prompt?.breakLength == 480 && c41.prompt?.title == "Take 8 minutes",
               "Custom 40 and 8 at 41 minutes", &problems)
        return problems
    }

    private static func flowPromptsOnlyTheGuard() -> [String] {
        var problems: [String] = []
        let flow = plan(.flow)
        let long = eval(200, flow)
        expect(long.due == .ultradian && long.prompt?.breakLength == 1_200
               && long.prompt?.title == "Step away for 20 minutes",
               "Flow at 200 minutes offers the longest break", &problems)
        let ninety = eval(91, flow).prompt
        expect(ninety?.breakLength == 1_080 && ninety?.title == "Step away for 18 minutes",
               "and at 91 a fifth of the stretch, in whole minutes", &problems)
        let hour = eval(60, flow)
        expect(hour.due == nil || hour.due == .micro, "Flow has no main break at an hour", &problems)
        expect(hour.breakLength == 720, "Start break suggests 12 minutes after an hour", &problems)
        expect(eval(60, plan(.flow, guardMinutes: nil)).breakLength == 720,
               "the suggestion does not need the guard", &problems)
        expect(flow.creditGap == nil && flow.tiers == [.micro, .ultradian], "Flow has no fixed rest or main tier", &problems)
        return problems
    }

    private static func flowRestReachesSuggestion() -> [String] {
        var problems: [String] = []
        let flow = plan(.flow)
        // An hour, a gap, forty minutes to now.
        func after(gap: Double) -> BreakReminder.Evaluation {
            BreakReminder.evaluate([stretch(0, 60), stretch(60 + gap, 100 + gap)], now: at(100 + gap),
                                   last: nil, plan: flow)
        }
        expect(after(gap: 10).due == .ultradian, "10 minutes is short of the hour's 12, so 100 are due",
               &problems)
        expect(after(gap: 12).due != .ultradian, "12 minutes reaches it", &problems)
        expect(after(gap: 25).due != .ultradian, "and a gap of 20 or more always does", &problems)

        let run = BreakCycles.flowRun([stretch(72, 112), stretch(0, 60)], now: at(112))
        expect(run.seconds == 40 * 60 && run.start == at(72), "the run starts after the rest", &problems)
        let short = BreakCycles.flowRun([stretch(0, 20)], now: at(24))
        expect(short.seconds == 20 * 60 && short.start == at(0), "a short stretch needs 5 minutes", &problems)
        let rested = BreakCycles.flowRun([stretch(0, 20)], now: at(25))
        expect(rested.seconds == 0 && rested.start == nil, "5 minutes after it, the run is over", &problems)
        expect(BreakCycles.flowRun([], now: at(5)).seconds == 0, "nothing worked is nothing", &problems)
        return problems
    }

    private static func guardFollowsLongBlock() -> [String] {
        var problems: [String] = []
        let deep = plan(.deepWork)
        expect(eval(91, deep).due == .cognitive && eval(104, deep).due == .cognitive
               && eval(106, deep).due == .ultradian,
               "Deep work and a 90-minute guard: the main break, then the guard 15 minutes after the block",
               &problems)
        expect(eval(91).due == .ultradian, "Steady keeps its guard at 90", &problems)
        var skipped = BreakClock()
        skipped.skip(.cognitive, at: at(90))
        expect(eval(95, deep, clock: skipped).due != .ultradian,
               "skipping the main break does not bring the guard a minute later", &problems)
        expect(deep.workLength(.ultradian) == 6_300 && plan(.steady).workLength(.ultradian) == 5_400
               && plan(.pomodoro).workLength(.ultradian) == 5_400 && plan(nil).workLength(.ultradian) == 5_400
               && plan(.flow).workLength(.ultradian) == 5_400,
               "only a fixed block longer than the guard moves it", &problems)
        let long = plan(.deepWork, guardMinutes: 120)
        expect(long.workLength(.ultradian) == 7_200, "a guard past the wait keeps its own number", &problems)
        return problems
    }

    private static func noRemindersKeepsAddOns() -> [String] {
        var problems: [String] = []
        let off = plan(nil)
        expect(eval(51, off).due == .micro && eval(91, off).due == .ultradian
               && [20.5, 51, 91, 130].allSatisfy { eval($0, off).due != .cognitive },
               "Eyes and the guard still come, the main break never", &problems)
        expect(off.creditGap == 300 && eval(10, off).breakLength == 300,
               "a rest and Start break are 5 minutes with no rhythm", &problems)

        var schedule = BreakSchedule()
        schedule.weekdays[3] = .off
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10)) ?? start
        let resolved = BreakPlan.resolve(schedule: schedule, eyes: true, guardMinutes: 90, on: wednesday,
                                         calendar: calendar)
        expect(resolved.rhythm == nil && resolved.eyes && resolved.guardLength == 5_400,
               "a day set to No reminders keeps the add-ons", &problems)
        let thursday = wednesday.addingTimeInterval(86_400)
        expect(BreakPlan.resolve(schedule: schedule, eyes: false, guardMinutes: nil, on: thursday,
                                 calendar: calendar) == BreakPlan(rhythm: BreakRhythm(.steady), eyes: false,
                                                                  guardLength: nil, override: nil),
               "other days follow the rhythm, with the add-ons as set", &problems)
        return problems
    }

    private static func repeatWaitsForPlanLength() -> [String] {
        var problems: [String] = []
        func said(_ minutes: Double, before now: Double) -> BreakNotice {
            BreakNotice(tier: .cognitive, at: at(now - minutes))
        }
        expect(eval(30, plan(.pomodoro), last: said(26, before: 30)).prompt != nil,
               "Pomodoro repeats after its own 25 minutes", &problems)
        expect(eval(55, last: said(26, before: 55)).prompt == nil,
               "Steady waits for 50 minutes", &problems)
        expect(eval(55, last: said(51, before: 55)).prompt != nil, "and then repeats", &problems)
        return problems
    }

    private static func rhythmChangeUnderLater() -> [String] {
        var problems: [String] = []
        var later = BreakClock()
        later.later(.cognitive, at: at(53))
        let deep = plan(.deepWork)
        let changed = eval(55, deep, clock: later)
        expect(changed.prompt?.tier != .cognitive && changed.clock.snooze == nil,
               "a Later for a break that is no longer due is dropped, not kept", &problems)
        let back = eval(92, deep, clock: later).prompt
        expect(back?.tier == .cognitive && back?.breakLength == 900, "and the new rhythm's break comes at 90", &problems)

        let flow = eval(55, plan(.flow), clock: later)
        expect(flow.due == .micro && flow.clock.snooze == nil, "a Later on a tier the plan lacks is dropped", &problems)
        var guardLater = BreakClock()
        guardLater.later(.ultradian, at: at(93))
        expect(eval(95, plan(.steady, guardMinutes: nil), clock: guardLater).clock.snooze == nil,
               "and so is one on a guard that was turned off", &problems)
        return problems
    }

    private static func customExtremes() -> [String] {
        var problems: [String] = []
        let tiny = plan(.custom, custom: CustomRhythm(workMinutes: 10, breakMinutes: 1))
        expect(tiny.creditGap == 180, "a rest is never under the idle cutoff", &problems)
        let gapped = BreakReminder.evaluate([stretch(0, 4), stretch(6, 13)], now: at(13), last: nil, plan: tiny)
        expect(gapped.due == .cognitive, "a 2-minute gap is no rest, so 11 minutes are due", &problems)
        expect(eval(21, tiny).due == .cognitive, "Eyes never prompts while the block is shorter than 20", &problems)
        expect(eval(11, tiny).prompt?.title == "Take 1 minute", "one minute reads as one minute", &problems)

        let wide = plan(.custom, guardMinutes: 60, custom: CustomRhythm(workMinutes: 180, breakMinutes: 30))
        expect(eval(61, wide).due == .ultradian && eval(50, wide).due == .micro,
               "a guard shorter than the block comes first", &problems)
        expect(eval(59, wide).due == nil && eval(59, wide).prompt == nil, "and quiets Eyes before it", &problems)

        var schedule = BreakSchedule()
        schedule.rhythm = .custom
        schedule.custom = CustomRhythm(workMinutes: 1, breakMinutes: 99)
        let calendar = Calendar(identifier: .gregorian)
        let clamped = BreakPlan.resolve(schedule: schedule, eyes: true, guardMinutes: 10, on: start, calendar: calendar)
        let high = BreakPlan.resolve(schedule: schedule, eyes: true, guardMinutes: 999, on: start, calendar: calendar)
        expect(clamped.guardLength == 3_600 && high.guardLength == 10_800
               && clamped.rhythm?.work == 600 && clamped.rhythm?.breakLength == 1_800,
               "the guard and Custom stay inside their ranges", &problems)
        return problems
    }
}
