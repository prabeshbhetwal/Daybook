import Foundation

/// Pomodoro's long break: the cycles counted from the usage record and the
/// credited rests, and the main prompt that becomes the long break after every
/// fourth one. A Pomodoro block here is 26 minutes of work, and a gap of six
/// minutes after it is a credited rest.
enum BreakCycleChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The fourth Pomodoro break is the long one", fourthBreakIsLong),
        ("A long rest taken early starts the count again", longRestResetsCount),
        ("Skip is not a cycle, and a short block is not one", skipAndShortBlockAreNotCycles),
        ("A break ended early still counts as a cycle", endedBreakCounts),
        ("Break clocks read across builds", clockFormatsInterchange),
    ]

    private static let start = SelfTest.base

    private static func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private static func stretch(_ from: Double, _ to: Double) -> AppUsageSession {
        AppUsageSession(bundleID: "com.a", appName: "Alpha", start: at(from), end: at(to))
    }

    private static let pomodoro = BreakPlan(rhythm: BreakRhythm(.pomodoro), eyes: true,
                                            guardLength: 5_400, override: nil)
    /// The same rhythm with no add-on that could be due ahead of it.
    private static let mainOnly = BreakPlan(rhythm: BreakRhythm(.pomodoro), eyes: false,
                                            guardLength: nil, override: nil)

    /// The answer at minute `now`, working from `stretches`.
    private static func eval(_ stretches: [AppUsageSession], _ now: Double, plan: BreakPlan = pomodoro,
                            clock: BreakClock = BreakClock()) -> BreakReminder.Evaluation {
        BreakReminder.evaluate(stretches, now: at(now), last: nil, plan: plan, clock: clock)
    }

    /// Pomodoro's own numbers, newest end first as the engine hands them over.
    private static func cycles(_ stretches: [AppUsageSession], _ now: Double,
                               credits: [Date] = []) -> Int {
        BreakCycles.completedCycles(stretches.sorted { $0.end > $1.end }, now: at(now),
                                    credits: credits, work: 1_500, rest: 300, longRest: 900)
    }

    private static func fourthBreakIsLong() -> [String] {
        var problems: [String] = []
        // Three finished blocks, six minutes apart, and the fourth under way.
        let four = [stretch(0, 26), stretch(32, 58), stretch(64, 90), stretch(96, 122)]
        let result = eval(four, 122)
        let prompt = result.prompt
        expect(prompt?.isLong == true && prompt?.kind == .long && prompt?.breakLength == 900
               && prompt?.title == "Take 15 minutes" && result.breakLength == 900,
               "the fourth block's prompt is the 15-minute long break, got "
               + "\(String(describing: [prompt?.title])) \(result.breakLength)", &problems)

        let two = eval(Array(four.prefix(3)), 90)
        expect(two.prompt?.isLong == false && two.prompt?.breakLength == 300
               && two.prompt?.title == "Take 5 minutes" && two.breakLength == 300,
               "after two finished blocks the third is the usual 5 minutes", &problems)

        // Start break begins the long break as soon as it is the next one.
        let early = eval(Array(four.prefix(3)) + [stretch(96, 106)], 106)
        expect(early.prompt == nil && early.breakLength == 900,
               "with the fourth block 10 minutes in, nothing is due but Start break offers 15", &problems)
        let owed = eval(four + [stretch(128, 154)], 154)
        expect(owed.prompt?.isLong == true && owed.breakLength == 900,
               "a long break passed over for a short one stays owed", &problems)

        let steady = BreakPlan(rhythm: BreakRhythm(.steady), eyes: false, guardLength: nil, override: nil)
        let plain = eval([stretch(0, 52), stretch(58, 110), stretch(116, 168), stretch(174, 226)], 226, plan: steady)
        expect(plain.prompt?.isLong == false && plain.breakLength == 300,
               "a rhythm without a long break never offers one", &problems)
        let custom = BreakPlan(rhythm: BreakRhythm(.custom, custom: CustomRhythm(
            workMinutes: 10, breakMinutes: 5, longEvery: 2, longMinutes: 20)),
                               eyes: false, guardLength: nil, override: nil)
        let second = eval([stretch(0, 12), stretch(18, 30)], 30, plan: custom)
        expect(second.prompt?.isLong == true && second.prompt?.title == "Take 20 minutes"
               && second.breakLength == 1_200, "Custom offers its own long break every second one", &problems)
        return problems
    }

    private static func longRestResetsCount() -> [String] {
        var problems: [String] = []
        // Blocks 1 and 2, a 16-minute rest, then blocks 3 and 4 with a gap between.
        let rested = [stretch(0, 26), stretch(32, 58), stretch(74, 100), stretch(106, 132)]
        expect(cycles(rested, 132) == 1, "only block 3 is a cycle after the long rest, got \(cycles(rested, 132))",
               &problems)
        let result = eval(rested, 132)
        expect(result.prompt?.isLong == false && result.breakLength == 300,
               "so block 4 is an ordinary break", &problems)
        // The same day with a six-minute gap in place of the long rest.
        let short = [stretch(0, 26), stretch(32, 58), stretch(64, 90), stretch(96, 122)]
        expect(cycles(short, 122) == 3, "the long rest is what changed it, got \(cycles(short, 122))", &problems)
        // And 15 minutes away after the last block, with nothing since.
        expect(cycles(short, 137) == 0 && eval(short, 137).breakLength == 300,
               "a long rest taken now starts from none, and Start break offers 5 minutes", &problems)
        return problems
    }

    private static func skipAndShortBlockAreNotCycles() -> [String] {
        var problems: [String] = []
        // Three blocks that run straight on, each answered with Skip.
        let run = [stretch(0, 26), stretch(26, 52), stretch(52, 78)]
        var skipped = BreakClock()
        skipped.skip(.cognitive, at: at(26))
        skipped.skip(.cognitive, at: at(52))
        skipped.skip(.cognitive, at: at(78))
        expect(cycles(run, 78) == 0, "skipping is not resting", &problems)
        let result = eval(run + [stretch(78, 104)], 104, plan: mainOnly, clock: skipped)
        expect(result.prompt?.tier == .cognitive && result.prompt?.isLong == false && result.breakLength == 300,
               "so the next break is still the usual one", &problems)

        // A ten-minute block between two credited rests is not a cycle.
        let withShort = [stretch(0, 26), stretch(32, 42), stretch(48, 74)]
        let without = [stretch(0, 26), stretch(32, 58)]
        expect(cycles(withShort, 74) == 1 && cycles(withShort, 74) == cycles(without, 58),
               "the short block adds none, got \(cycles(withShort, 74))", &problems)
        expect(cycles([], 10) == 0 && cycles([stretch(0, 10)], 10) == 0, "nothing worked, nothing counted", &problems)
        return problems
    }

    private static func endedBreakCounts() -> [String] {
        var problems: [String] = []
        // A two-minute gap after block 1 is a break ended early: a credit at its end.
        let blocks = [stretch(0, 26), stretch(28, 54), stretch(60, 86), stretch(92, 118)]
        var credited = BreakClock()
        credited.credit(at: at(28))
        let counted = eval(blocks, 118, clock: credited)
        expect(counted.prompt?.isLong == true && counted.breakLength == 900,
               "with the credit the fourth block is the long break", &problems)
        expect(cycles(blocks, 118, credits: credited.credits) == 3 && cycles(blocks, 118) == 2,
               "it is the credit that makes block 1 a cycle", &problems)
        let plain = eval(blocks, 118)
        expect(plain.prompt?.isLong == false && plain.breakLength == 300,
               "without it the first two blocks ran together", &problems)

        // The gap to now counts as well: a break ended early after the last block.
        expect(cycles([stretch(0, 26)], 28, credits: [at(28)]) == 1 && cycles([stretch(0, 26)], 28) == 0,
               "a credit in the gap since the last stretch is a rest", &problems)
        return problems
    }

    private static func clockFormatsInterchange() -> [String] {
        var problems: [String] = []
        // What the first release stored and read: floors and a Later, nothing else.
        struct FirstRelease: Codable {
            var floors: [BreakTier: Date]
            var snooze: BreakSnooze?
        }
        var clock = BreakClock()
        clock.skip(.cognitive, at: at(10))
        clock.credit(at: at(20))
        clock.later(.cognitive, at: at(30))
        guard let data = try? JSONEncoder().encode(clock),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ["a clock should encode to a JSON object"]
        }
        expect(object["credits"] != nil && !clock.floors.isEmpty && clock.snooze != nil && clock.credits == [at(20)],
               "the clock under test holds floors, a Later and a credit", &problems)
        expect((try? JSONDecoder().decode(BreakClock.self, from: data)) == clock, "a clock reads back as written",
               &problems)
        if let older = try? JSONDecoder().decode(FirstRelease.self, from: data) {
            expect(older.floors == clock.floors && older.snooze == clock.snooze,
                   "a build without credits reads the same floors and Later", &problems)
        } else {
            problems.append("a build without credits could not read a clock that has them")
        }
        object.removeValue(forKey: "credits")
        if let stripped = try? JSONSerialization.data(withJSONObject: object),
           let read = try? JSONDecoder().decode(BreakClock.self, from: stripped) {
            expect(read.credits.isEmpty && read.floors == clock.floors && read.snooze == clock.snooze,
                   "a clock stored without credits has none", &problems)
        } else {
            problems.append("a clock stored without credits could not be read")
        }

        var trimmed = BreakClock()
        for hours in [0.0, 3.0, 25.0] { trimmed.credit(at: at(hours * 60)) }
        expect(trimmed.credits == [at(180), at(1_500)], "credits older than a day go on the next credit, got "
               + "\(trimmed.credits.count)", &problems)
        var many = BreakClock()
        for index in 0..<40 { many.credit(at: at(Double(index) * 10)) }
        expect(many.credits.count == BreakClock.maxCredits && many.credits.first == at(80)
               && many.credits.last == at(390), "at most 32 stay, the newest of them", &problems)
        var unordered = BreakClock()
        unordered.credit(at: at(100))
        unordered.credit(at: at(50))
        expect(unordered.credits == [at(50), at(100)], "and they stay in order", &problems)

        var ahead = BreakClock()
        ahead.credit(at: at(50))
        ahead.credit(at: at(500))
        expect(ahead.sanitized(now: at(100)).credits == [at(50)], "a credit in the future is not believed",
               &problems)

        var damaged = BreakClock()
        damaged.snooze = BreakSnooze(tier: .cognitive, until: at(10), count: -3)
        guard let damagedData = try? JSONEncoder().encode(damaged),
              let reloaded = try? JSONDecoder().decode(BreakClock.self, from: damagedData) else {
            return problems + ["a damaged count should still decode"]
        }
        expect(reloaded.snooze?.count == -3 && reloaded.sanitized(now: at(5)).snooze?.count == 0,
               "a negative Later count reads as none", &problems)
        return problems
    }
}
