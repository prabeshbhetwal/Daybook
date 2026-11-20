import Foundation

/// An absence ends when a person comes back, not when the idle timer does. On 20 November 2026 the
/// timer reset two hours into an absence with no key, click or pointer move behind it, the idle pause
/// ended, and the person was asked about a 19-minute slice of a four-hour absence.
enum AwayGapChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("After a long quiet, an idle timer reset with no input behind it is not a return", phantomResetIsQuiet),
        ("A phantom reset leaves an idle pause paused, and the first real input ends it", phantomResetKeepsPause),
        ("After a wake, a second idle drop with no input behind it is not a person", wakeDropNeedsInput),
        ("A confirmed return starts the quiet afresh, and late counted input still counts", confirmAndLateInput),
        ("An app coming to the front by itself leaves an idle pause paused until a person",
         activationWithoutInputWaits),
        ("A second absence the away question sits through never starts before the return it asks about",
         secondAbsenceStartsAtReturn),
        ("Seconds since an agent stopped are not input", samplerLowReadingIsNotInput),
        ("An app delivered later replaces one still waiting for a person", deliveredActivationReplacesQueued),
        ("A declared away is not ended by an app coming to the front by itself", declaredAwayWaitsForPerson),
        ("After a wake, input counted one sample after its idle drop still confirms the person",
         wakeCountOneSampleLate),
        ("An app waiting for a person keeps the ticker running in a manual pause", queuedActivationKeepsTicker),
        ("The app delivered at the first input moves app-use recording to it", queuedActivationMovesTracker),
    ]

    private static func wakeCountOneSampleLate() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        var gate = PresenceGate()
        func observe(_ raw: TimeInterval, _ count: UInt64) -> PresenceObservation {
            gate.observe(rawIdleSeconds: raw, at: clock.value, displayAwake: true, screenLocked: false,
                         inputCount: count)
        }
        _ = observe(0, 100)
        clock.advance(600)
        _ = observe(600, 100)
        gate.noteMachineWake()
        clock.advance(1)
        _ = observe(30.1, 100)
        clock.advance(1)
        _ = observe(0.1, 100)                                   // the key lands between the two reads
        clock.advance(1)
        if case .active = observe(1.1, 101) {} else {
            problems.append("the count on the next sample confirms the drop it explains")
        }
        expect(!gate.isAwaitingConfirmation, "and the wake stops waiting", &problems)
        return problems
    }

    /// App-use recording off: a manual pause stops the ticker, and an app then waits for a person.
    private static func queuedActivationKeepsTicker() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: true, ticker: true, countsInput: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.activate("com.microsoft.VSCode")
            r.run(30) { _ in r.keys.value &+= 3; r.idle.value = 0 }
            r.run(10) { t in r.idle.value = TimeInterval(1 + t) }
            r.engine.transition(on: .manualPause)
            r.store.refresh()
            expect(!r.store.hasScheduledTicker, "a manual pause with nothing recording stops the ticker", &problems)
            r.activate("com.apple.dt.Xcode")
            expect(r.store.hasScheduledTicker, "an app waiting for a person starts it again", &problems)
            r.run(1) { _ in r.keys.value &+= 1; r.idle.value = 0.2 }
            expect(r.engine.currentAppBundleID == "com.apple.dt.Xcode",
                   "and the first key delivers it, got \(String(describing: r.engine.currentAppBundleID))", &problems)
            return problems
        }
    }

    private static func queuedActivationMovesTracker() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: true, tracker: true, countsInput: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.activate("com.microsoft.VSCode")
            r.run(30) { _ in r.keys.value &+= 3; r.idle.value = 0 }
            r.engine.transition(on: .manualPause)
            r.store.refresh()
            r.run(10) { t in r.idle.value = TimeInterval(1 + t) }
            r.activate("com.apple.dt.Xcode")
            r.run(1) { _ in r.keys.value &+= 1; r.idle.value = 0.2 }
            expect(r.store.tracker?.currentBundleID == "com.apple.dt.Xcode",
                   "app-use recording follows the app delivered, got \(String(describing: r.store.tracker?.currentBundleID))",
                   &problems)
            return problems
        }
    }

    /// Claude comes to the front with nobody there and waits; the cap ends the session; Xcode is
    /// then delivered. The first key must not replay Claude over it.
    private static func deliveredActivationReplacesQueued() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: true, countsInput: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.persistence.longAwayCap = 1_200
            r.activate("com.microsoft.VSCode")
            var lastInput = 0
            r.run(660) { t in
                if t < 60 { lastInput = t; r.keys.value &+= 3 }
                r.idle.value = TimeInterval(t - lastInput)
            }
            r.activate("com.anthropic.claudefordesktop")
            r.run(700) { t in r.idle.value = TimeInterval(601 + t) }
            expect(r.engine.state == .idle, "the cap ends the session, got \(r.engine.state)", &problems)
            r.activate("com.apple.dt.Xcode")
            r.run(1) { _ in r.keys.value &+= 1; r.idle.value = 0.2 }
            expect(r.engine.currentAppBundleID == "com.apple.dt.Xcode",
                   "the app in front is the one delivered last, got \(String(describing: r.engine.currentAppBundleID))",
                   &problems)
            return problems
        }
    }

    private static func declaredAwayWaitsForPerson() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: true, countsInput: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.activate("com.microsoft.VSCode")
            r.run(60) { _ in r.keys.value &+= 3; r.idle.value = 0 }
            r.store.markAway()
            r.run(1_200) { t in r.idle.value = TimeInterval(1 + t) }
            expect(r.engine.state == .paused(reason: .away), "marked away, got \(r.engine.state)", &problems)
            r.activate("com.apple.dt.Xcode")
            expect(r.engine.state == .paused(reason: .away),
                   "an app coming to the front with nobody there keeps the away, got \(r.engine.state)", &problems)
            r.run(1) { _ in r.keys.value &+= 1; r.idle.value = 0.2 }
            expect(r.engine.state != .paused(reason: .away),
                   "the first key brings the person and the app back, got \(r.engine.state)", &problems)
            return problems
        }
    }

    /// As at 11:10:26 on 20 November: nobody at the Mac, and the assistant in front activates.
    private static func activationWithoutInputWaits() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: true, countsInput: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.activate("com.microsoft.VSCode")
            var lastInput = 0
            r.run(660) { t in
                if t < 60 { lastInput = t; r.keys.value &+= 3 }
                r.idle.value = TimeInterval(t - lastInput)
            }
            expect(r.engine.state == .paused(reason: .idle), "the quiet pauses the session, got \(r.engine.state)", &problems)
            r.activate("com.anthropic.claudefordesktop")
            // Read at once: the quiet ticks after would pause a resumed session again.
            expect(r.engine.state == .paused(reason: .idle),
                   "the activation itself does not end the pause, got \(r.engine.state)", &problems)
            r.run(5) { t in r.idle.value = TimeInterval(601 + t) }
            expect(r.engine.state == .paused(reason: .idle),
                   "an activation with nobody there keeps the pause, got \(r.engine.state)", &problems)
            r.run(1) { _ in r.keys.value &+= 1; r.idle.value = 0.2 }
            expect(r.engine.state != .paused(reason: .idle),
                   "the first key delivers the waiting activation and ends the pause, got \(r.engine.state)", &problems)
            return problems
        }
    }

    /// Work to 2300 s, an idle pause from there, an activation at 3300 s opens the question, and the
    /// quiet the card sits through is measured from 2300 s, inside the absence already asked about.
    private static func secondAbsenceStartsAtReturn() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.store.longAwayCap = 3_600
        engine.start(workType: .deepWork, intent: "Coding")
        engine.transition(on: .appActivated(bundleID: "com.microsoft.VSCode", name: "Code"))
        clock.advance(3_000)
        engine.transition(on: .idleObserved(seconds: 700))
        clock.advance(300)
        engine.transition(on: .appActivated(bundleID: "com.anthropic.claudefordesktop", name: "Claude"))
        guard case .awaitingUserDecision = engine.state else {
            return ["the activation should open the question, got \(engine.state)"]
        }
        clock.advance(700)
        engine.transition(on: .idleObserved(seconds: 1_700))
        clock.advance(3_000)
        engine.transition(on: .idleObserved(seconds: 4_700))
        expect(engine.decide(.tookBreak, label: "Brunch"), "the answer is saved", &problems)
        let coding = engine.archive.records.first { $0.workType == .deepWork }
        SelfTest.expectClose(coding?.workSeconds ?? 0, 2_300,
                             "the session keeps every second it worked, got \(String(describing: coding?.workSeconds))",
                             &problems)
        let brunch = engine.archive.records.first { $0.name == "Brunch" }
        SelfTest.expectClose(brunch?.workSeconds ?? 0, 1_000, "the break is the thousand seconds asked about", &problems)
        return problems
    }

    private static func samplerLowReadingIsNotInput() -> [String] {
        var problems: [String] = []
        var sampler = QuietSampler()
        let start = SelfTest.base
        _ = sampler.read(now: start, quiet: 3_599, film: false, agentSeen: start, idlePaused: false)
        let next = sampler.read(now: start.addingTimeInterval(1), quiet: 3_600, film: false, agentSeen: nil,
                                idlePaused: false)
        if case .idleObserved(let seconds) = next.event {
            expect(seconds >= FocusConstants.awayDebounce,
                   "a second after the agent stopped is quiet, not a keypress, got \(seconds) s", &problems)
        } else {
            problems.append("once the agent stops, the sample is idle, got \(next.event)")
        }
        return problems
    }

    private static func wakeDropNeedsInput() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        var gate = PresenceGate()
        func observe(_ raw: TimeInterval, _ count: UInt64) -> PresenceObservation {
            gate.observe(rawIdleSeconds: raw, at: clock.value, displayAwake: true, screenLocked: false,
                         inputCount: count)
        }
        _ = observe(0, 100)
        clock.advance(600)
        _ = observe(600, 100)
        gate.noteMachineWake()
        clock.advance(1)
        _ = observe(0.5, 100)                                   // the wake's own reset
        clock.advance(30)
        if case .active = observe(0.3, 100) {
            problems.append("a second uncounted drop after a wake must not confirm a person")
        }
        expect(gate.isAwaitingConfirmation, "the wake still waits for a person", &problems)
        clock.advance(1)
        if case .active = observe(0.2, 101) {} else {
            problems.append("a key after the wake confirms the person")
        }
        expect(!gate.isAwaitingConfirmation, "and the wake stops waiting", &problems)
        return problems
    }

    private static func confirmAndLateInput() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        var gate = PresenceGate()
        func observe(_ raw: TimeInterval, _ count: UInt64) -> PresenceObservation {
            gate.observe(rawIdleSeconds: raw, at: clock.value, displayAwake: true, screenLocked: false,
                         inputCount: count)
        }
        _ = observe(0, 100)
        clock.advance(3_600)
        _ = observe(3_600, 100)
        gate.confirm(at: clock.value)                           // an unlock: the person is back
        clock.advance(1)
        if case .active = observe(0.4, 100) {} else {
            problems.append("just after a confirmed return, the hour before it is not carried again")
        }

        // A phantom, then a key sampled only once the idle time has passed five seconds.
        clock.advance(3_600)
        _ = observe(3_600, 100)
        clock.advance(1)
        _ = observe(0.3, 100)
        clock.advance(6)
        _ = observe(6, 101)
        clock.advance(1)
        if case .active = observe(0.3, 101) {} else {
            problems.append("counted input ends the carried quiet even when sampled late")
        }
        return problems
    }

    private static func phantomResetIsQuiet() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        var gate = PresenceGate()
        func observe(_ raw: TimeInterval, _ count: UInt64?) -> PresenceObservation {
            gate.observe(rawIdleSeconds: raw, at: clock.value, displayAwake: true, screenLocked: false,
                         inputCount: count)
        }
        _ = observe(0, 100)
        clock.advance(3_600)
        _ = observe(3_600, 100)
        clock.advance(1)
        if case .quiet(let seconds) = observe(0.3, 100) {
            expect(seconds >= 3_600, "the quiet runs on from the last input, got \(seconds) s", &problems)
        } else {
            problems.append("a reset with the counters still is a phantom, not a return")
        }
        clock.advance(1)
        if case .active = observe(0.2, 101) {} else {
            problems.append("a reset with one counted input is a return")
        }

        // A short pause in typing keeps today's rule, and so does a monitor that cannot count.
        clock.advance(30)
        if case .active = observe(0.4, 101) {} else {
            problems.append("thirty seconds after typing, a low idle time is still the person")
        }
        var blind = PresenceGate()
        blind.confirm(at: clock.value)
        clock.advance(3_600)
        if case .active = blind.observe(rawIdleSeconds: 0.3, at: clock.value, displayAwake: true,
                                        screenLocked: false) {} else {
            problems.append("without counters, a low idle time is a return as before")
        }

        let counters = InputCounters(keys: { 1 }, clicks: { 2 }, scrolls: { 3 }, otherInput: { 4 })
        expect(counters.total() == 10, "every counted kind of input adds up, got \(counters.total())", &problems)
        return problems
    }

    /// Typing, ten minutes' quiet (the rig pauses at two), then the idle timer resets with nothing
    /// counted, as at 11:10:26. The pause must hold; a key afterwards ends it.
    private static func phantomResetKeepsPause() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: true, countsInput: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.activate("com.microsoft.VSCode")
            var lastInput = 0, tick = 0
            r.run(660) { t in
                tick = t
                if t < 60 { lastInput = t; r.keys.value &+= 3 }
                r.idle.value = TimeInterval(t - lastInput)
            }
            expect(r.engine.state == .paused(reason: .idle), "ten minutes' quiet pauses the session, got \(r.engine.state)",
                   &problems)

            let resetAt = tick + 1
            r.run(60) { t in r.idle.value = 0.3 + TimeInterval(t) }
            expect(r.engine.state == .paused(reason: .idle),
                   "a reset with no input keeps the pause, nobody is asked, got \(r.engine.state) (from \(resetAt))",
                   &problems)

            r.run(1) { _ in r.keys.value &+= 1; r.idle.value = 0.2 }
            expect(r.engine.state != .paused(reason: .idle),
                   "a key after the reset ends the pause, got \(r.engine.state)", &problems)
            return problems
        }
    }
}
