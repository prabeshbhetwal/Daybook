import Foundation

/// Putting a reminder off or skipping it: the per-reminder clock that sits
/// beside the usage record, and what each answer does to it.
enum BreakClockChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Later brings the reminder back in ten minutes", laterReturnsInTen),
        ("Later is offered twice, not a third time", laterCapsAtTwo),
        ("Skip restarts that reminder only", skipLeavesOtherTiers),
        ("A taken break restarts every reminder", creditResetsAll),
        ("The reminder clock survives a relaunch", clockPersists),
        ("A Later that has run out brings the reminder back once", expiredLaterReturnsOnce),
        ("A Later does not outlive the break it was pressed for", laterEndsWithItsRun),
        ("A clock value from the future does not silence a reminder", futureValuesIgnored),
        ("Skipping the long break does not restart it", skipLeavesLongGuard),
        ("A damaged Later count cannot crash", damagedCountIsClamped),
    ]

    private static let start = SelfTest.base

    /// One unbroken stretch in an app, from `from` to `to` (both offsets in
    /// minutes after `start`).
    private static func stretch(_ from: Double, _ to: Double) -> AppUsageSession {
        AppUsageSession(bundleID: "com.a", appName: "Alpha",
                        start: start.addingTimeInterval(from * 60),
                        end: start.addingTimeInterval(to * 60))
    }

    private static func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    private static func laterReturnsInTen() -> [String] {
        var problems: [String] = []
        // Work that began at minute 0 and never stops.
        func evaluate(atMinute minute: Double, clock: BreakClock,
                      last: BreakNotice? = nil) -> BreakReminder.Evaluation {
            BreakReminder.evaluate([stretch(0, minute)], now: at(minute), last: last, clock: clock)
        }
        let first = evaluate(atMinute: 55, clock: BreakClock())
        expect(first.prompt?.tier == .cognitive, "55 minutes asks for a break", &problems)

        var clock = BreakClock()
        clock.later(.cognitive, at: at(55))
        expect(clock.snooze?.until == at(65) && clock.snooze?.count == 1,
               "Later is ten minutes and counted once", &problems)
        let quiet = evaluate(atMinute: 60, clock: clock)
        expect(quiet.prompt == nil, "quiet at +5", &problems)
        expect(quiet.due == .cognitive, "still due while put off", &problems)
        let said = BreakNotice(tier: .cognitive, at: at(55))
        let back = evaluate(atMinute: 65, clock: clock, last: said)
        expect(back.prompt?.tier == .cognitive, "back at +10 despite lastBreakNotice", &problems)
        expect(back.prompt?.canLater == true, "one Later used, one left", &problems)

        // The long-stretch prompt waits fifteen minutes, not ten.
        var long = BreakClock()
        long.later(.ultradian, at: at(95))
        expect(long.snooze?.until == at(110), "Later on the long break is fifteen minutes", &problems)

        // A deeper tier coming due is not held back by a shallower Later.
        var running = BreakClock()
        running.later(.cognitive, at: at(90))
        let deeper = BreakReminder.evaluate([stretch(0, 91)], now: at(91), last: said, clock: running)
        expect(deeper.prompt?.tier == .ultradian, "a deeper break still gets through", &problems)

        // Stopped being due: the snooze goes.
        clock.clearSnoozeIfNotDue(nil)
        expect(clock.snooze == nil, "a snooze with nothing due is dropped", &problems)
        var shallow = BreakClock()
        shallow.later(.cognitive, at: at(55))
        shallow.clearSnoozeIfNotDue(.micro)
        expect(shallow.snooze == nil, "a lower tier due drops the snooze", &problems)
        shallow.later(.cognitive, at: at(55))
        shallow.clearSnoozeIfNotDue(.ultradian)
        expect(shallow.snooze != nil, "a deeper tier due keeps it", &problems)
        return problems
    }

    private static func laterCapsAtTwo() -> [String] {
        var problems: [String] = []
        var clock = BreakClock()
        func prompt(atMinute minute: Double) -> BreakPrompt? {
            BreakReminder.evaluate([stretch(0, minute)], now: at(minute), last: nil,
                                   clock: clock).prompt
        }
        expect(prompt(atMinute: 55)?.canLater == true, "a fresh prompt can be put off", &problems)
        clock.later(.cognitive, at: at(55))
        expect(prompt(atMinute: 65)?.canLater == true, "after one Later, another is offered", &problems)
        clock.later(.cognitive, at: at(65))
        expect(clock.snooze?.count == 2, "two Laters counted", &problems)
        expect(prompt(atMinute: 75)?.canLater == false, "after two, none is offered", &problems)
        clock.later(.micro, at: at(75))
        expect(clock.snooze?.count == 1, "a different tier starts its count again", &problems)
        return problems
    }

    private static func skipLeavesOtherTiers() -> [String] {
        var problems: [String] = []
        // Ninety-five minutes in one go; the person skips the 50-minute break.
        var clock = BreakClock()
        clock.later(.cognitive, at: at(95))
        clock.skip(.cognitive, at: at(95))
        expect(clock.snooze == nil, "skipping a tier clears its Later", &problems)
        let eval = BreakReminder.evaluate([stretch(0, 96)], now: at(96), last: nil, clock: clock)
        expect(eval.due == .ultradian,
               "cognitive restarted and the long break still counts the whole run, got "
               + "\(String(describing: eval.due))", &problems)
        expect((eval.prompt?.worked ?? 0) >= 95 * 60, "ultradian still counts the whole run", &problems)

        // Skipping the 20-minute reminder leaves the 50-minute one alone.
        var micro = BreakClock()
        micro.skip(.micro, at: at(55))
        expect(BreakReminder.evaluate([stretch(0, 56)], now: at(56), last: nil,
                                      clock: micro).due == .cognitive,
               "skipping the eye break keeps the 50-minute one due", &problems)

        // A skipped tier comes due again after its own threshold of new work.
        var skipped = BreakClock()
        skipped.skip(.cognitive, at: at(55))
        let pair: [BreakTier] = [.micro, .cognitive]
        expect(BreakReminder.evaluate([stretch(0, 100)], now: at(100), last: nil,
                                      tiers: pair, clock: skipped).due == .micro,
               "45 minutes after a skip it is not yet due again", &problems)
        expect(BreakReminder.evaluate([stretch(0, 106)], now: at(106), last: nil,
                                      tiers: pair, clock: skipped).due == .cognitive,
               "51 minutes after a skip it is due again", &problems)

        // A stretch that straddles the floor counts only from the floor.
        let straddle = BreakReminder.evaluate([stretch(0, 60)], now: at(60), last: nil,
                                              tiers: [.micro], clock: micro)
        expect(straddle.next?.tier == .micro, "clipped work counts from the floor", &problems)
        expect(abs((straddle.next?.seconds ?? 0) - 15 * 60) < 1,
               "five minutes of 20 gone, got \(String(describing: straddle.next?.seconds))", &problems)
        return problems
    }

    private static func creditResetsAll() -> [String] {
        var problems: [String] = []
        var clock = BreakClock()
        clock.later(.cognitive, at: at(95))
        clock.credit(at: at(95))
        expect(clock.snooze == nil, "a taken break clears any Later", &problems)
        let eval = BreakReminder.evaluate([stretch(0, 95)], now: at(95), last: nil, clock: clock)
        expect(eval.due == nil, "nothing due after a taken break", &problems)
        expect(eval.next?.tier == .micro && eval.next?.seconds == 20 * 60,
               "the eye break is a full 20 minutes away", &problems)
        return problems
    }

    private static func clockPersists() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-breakclock"
        MemoryDefaults.remove(named: name)
        defer { MemoryDefaults.remove(named: name) }
        let store = PersistenceStore(defaults: MemoryDefaults.suite(named: name)!)
        expect(store.breakClock == BreakClock(), "a fresh store holds an empty clock", &problems)

        var clock = BreakClock()
        clock.skip(.cognitive, at: at(10))
        clock.credit(at: at(20))
        clock.skip(.micro, at: at(30))
        clock.later(.ultradian, at: at(40))
        store.breakClock = clock
        let reopened = PersistenceStore(defaults: MemoryDefaults.suite(named: name)!)
        expect(reopened.breakClock == clock, "floors and Later come back equal", &problems)
        expect(reopened.breakClock.floors[.cognitive] == at(20), "a floor keeps its time", &problems)

        reopened.breakClock = BreakClock()
        expect(PersistenceStore(defaults: MemoryDefaults.suite(named: name)!).breakClock
               == BreakClock(), "an emptied clock stays empty", &problems)
        reopened.breakClock = clock
        reopened.removeAll()
        expect(reopened.breakClock == BreakClock(), "erasing everything clears it", &problems)
        return problems
    }

    // MARK: - Fix round 1

    private static func expiredLaterReturnsOnce() -> [String] {
        var problems: [String] = []
        var clock = BreakClock()
        clock.later(.cognitive, at: at(55))
        // 1 Hz from the end of the Later, rewriting the notice after each prompt.
        var last: BreakNotice? = BreakNotice(tier: .cognitive, at: at(55))
        var shown = 0
        for second in 0..<120 {
            let minute = 65 + Double(second) / 60
            let eval = BreakReminder.evaluate([stretch(0, minute)], now: at(minute), last: last,
                                              clock: clock)
            if eval.prompt != nil {
                shown += 1
                last = BreakNotice(tier: .cognitive, at: at(minute))
            }
        }
        expect(shown == 1, "the returned reminder shows once in two minutes, got \(shown)", &problems)
        return problems
    }

    private static func laterEndsWithItsRun() -> [String] {
        var problems: [String] = []
        var clock = BreakClock()
        clock.later(.cognitive, at: at(55))
        clock.later(.cognitive, at: at(65))
        // An hour's rest, then a new 51-minute run.
        let run = [stretch(0, 80), stretch(140, 191)]
        let said = BreakNotice(tier: .cognitive, at: at(190))
        let quiet = BreakReminder.evaluate(run, now: at(191), last: said, clock: clock)
        expect(quiet.due == .cognitive, "the new run is due", &problems)
        expect(quiet.prompt == nil, "an old Later does not bypass the repeat guard", &problems)
        let fresh = BreakReminder.evaluate(run, now: at(191), last: nil, clock: clock).prompt
        expect(fresh?.canLater == true, "the new break can be put off again", &problems)

        // Nothing due at all: the old Later says nothing about a new, shallower break.
        let micro = BreakReminder.evaluate([stretch(0, 80), stretch(160, 185)], now: at(185),
                                           last: nil, clock: clock).prompt
        expect(micro?.tier == .micro && micro?.canLater == true,
               "a stale deeper Later does not touch a new eye break", &problems)
        return problems
    }

    private static func futureValuesIgnored() -> [String] {
        var problems: [String] = []
        let run = [stretch(0, 55)]
        let far = Date(timeIntervalSinceReferenceDate: 1e300)
        for floor in [at(115), at(55 + 60 * 24 * 365), far] {
            var clock = BreakClock()
            clock.floors[.cognitive] = floor
            clock.floors[.micro] = floor
            let eval = BreakReminder.evaluate(run, now: at(55), last: nil, clock: clock)
            expect(eval.due == .cognitive && eval.prompt?.tier == .cognitive,
                   "a floor from the future is ignored, got \(String(describing: eval.due))",
                   &problems)
        }
        for until in [at(55 + 31), at(55 + 60 * 24 * 365), far] {
            var clock = BreakClock()
            clock.snooze = BreakSnooze(tier: .cognitive, until: until, count: 1)
            expect(BreakReminder.evaluate(run, now: at(55), last: nil, clock: clock)
                    .prompt?.tier == .cognitive,
                   "a Later that ends too far ahead is ignored", &problems)
        }
        var real = BreakClock()
        real.later(.cognitive, at: at(55))
        expect(BreakReminder.evaluate(run, now: at(55), last: nil, clock: real).prompt == nil,
               "a real Later still holds", &problems)
        return problems
    }

    private static func skipLeavesLongGuard() -> [String] {
        var problems: [String] = []
        var clock = BreakClock()
        clock.skip(.ultradian, at: at(95))
        expect(clock.floors[.ultradian] == nil, "no floor is set", &problems)
        let eval = BreakReminder.evaluate([stretch(0, 96)], now: at(96), last: nil, clock: clock)
        expect(eval.due == .ultradian, "the long break is still due after Skip", &problems)
        return problems
    }

    private static func damagedCountIsClamped() -> [String] {
        var problems: [String] = []
        let json = "{\"tier\":1,\"until\":0,\"count\":\(Int.max)}"
        guard var snooze = try? JSONDecoder().decode(BreakSnooze.self, from: Data(json.utf8)) else {
            return ["the damaged Later should still decode"]
        }
        snooze.until = at(55)
        var clock = BreakClock()
        clock.snooze = snooze
        clock.later(.cognitive, at: at(55))
        expect(clock.snooze?.count == BreakClock.maxLaters + 1, "the count is clamped", &problems)
        let prompt = BreakReminder.evaluate([stretch(0, 66)], now: at(66), last: nil,
                                            clock: clock).prompt
        expect(prompt?.tier == .cognitive && prompt?.canLater == false,
               "no further Later is offered", &problems)
        return problems
    }
}
