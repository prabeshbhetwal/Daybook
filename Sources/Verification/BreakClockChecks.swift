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
        expect(eval.due != .cognitive, "cognitive restarted", &problems)
        expect(eval.due == .ultradian, "the long break still counts the whole run", &problems)
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
}
