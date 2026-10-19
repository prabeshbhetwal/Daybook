import Foundation

/// How a break ends, as `BreakStoreChecks` sees the store: every route that
/// ends one restarts the reminders once and only for a rest that was recorded,
/// +5 min from deep overtime, and an end that cannot be saved.
extension BreakStoreChecks {
    static func everyEndIsSettledOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for route in ["Start adopts the session", "I'm back", "the engine alone"] {
                guard let f = make(prepare: autoRunning) else { return problems + ["could not create isolated preferences"] }
                defer { f.close() }
                var ended = 0, resumed = 0
                f.store.onBreakEnded = { ended += 1 }
                f.store.onAwayEnded = { resumed += 1 }
                f.store.startBreak()
                f.clock.advance(100)
                let end = f.clock.value
                switch route {
                case "Start adopts the session":
                    f.store.workType = .deepWork
                    f.store.applyAutomaticSessionCorrection()
                case "I'm back":
                    f.store.endAway()
                default:
                    // What a transition anywhere in the app does to a break.
                    f.engine.transition(on: .manualResume)
                    f.store.refresh()
                }
                expect(!f.store.isOnBreak && f.engine.state == .running && f.breaks.count == 1,
                       "\(route): the break ends and is on record, got \(f.engine.state)", &problems)
                expect(ended == 1, "\(route): the end is announced once, got \(ended)", &problems)
                expect(f.persistence.breakClock.floors.count == BreakTier.allCases.count
                       && Set(f.persistence.breakClock.floors.values) == [end],
                       "\(route): every reminder restarts at the end of the break", &problems)
                expect(resumed == 0, "\(route): a tracker that never stopped is not resumed", &problems)

                // Nothing counts the same break again.
                f.clock.advance(30)
                f.store.refresh()
                f.store.refresh()
                expect(ended == 1 && Set(f.persistence.breakClock.floors.values) == [end],
                       "\(route): and it is not credited again later, got \(ended)", &problems)
            }
            return problems
        }
    }

    static func shortBreakCreditsNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for (seconds, recorded) in [(5.0, false), (60.0, true)] {
                guard let f = make(prepare: running) else { return problems + ["could not create isolated preferences"] }
                defer { f.close() }
                var ended = 0
                f.store.onBreakEnded = { ended += 1 }
                f.store.startBreak()
                f.clock.advance(seconds)
                f.store.endBreak()
                expect(ended == 1 && !f.store.isOnBreak, "a \(Int(seconds)) s break still ends", &problems)
                expect(f.breaks.isEmpty == !recorded, "and is recorded only if it was long enough", &problems)
                expect(f.persistence.breakClock.floors.isEmpty == !recorded,
                       "a \(Int(seconds)) s break \(recorded ? "restarts" : "leaves alone") the reminders, got "
                       + "\(f.persistence.breakClock.floors.count) floors", &problems)
            }
            return problems
        }
    }

    static func extendFromOvertime() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var over = 0
            f.store.onBreakOver = { _ in over += 1; return true }
            f.store.startBreak(length: 300)
            f.clock.advance(1_500)
            f.store.runTick()
            expect(over == 1 && f.store.breakRemaining == -1_200, "twenty minutes over and announced", &problems)

            f.store.extendBreak()
            expect(f.store.breakRemaining == 300 && f.store.activeBreak?.overNoticed == false,
                   "+5 min is five minutes from now, got \(f.store.breakRemaining)", &problems)
            f.clock.advance(1)
            f.store.runTick()
            expect(over == 1 && f.store.breakRemaining == 299,
                   "and the prompt does not come straight back, got \(over)", &problems)

            // With time left it adds five, as it says.
            f.store.extendBreak()
            expect(f.store.breakRemaining == 599, "with time left it adds five minutes to it", &problems)
            return problems
        }
    }

    static func failedEndIsReportedAndRetried() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            f.store.startBreak(length: 300)
            let cap = f.store.activeBreak?.capEnd(longAwayCap: f.persistence.longAwayCap)
            f.clock.advance(300 + f.persistence.longAwayCap)
            f.gate.refuses = true
            f.store.runTick()
            let perTry = f.gate.attempts
            expect(perTry > 0 && f.store.isOnBreak, "setup: the end was refused", &problems)
            expect(f.store.correctionError != nil, "and the person is told", &problems)
            for _ in 0..<9 {
                f.clock.advance(1)
                f.store.runTick()
            }
            expect(f.gate.attempts <= 2 * perTry,
                   "ten seconds make two tries, not ten, got \(f.gate.attempts) writes for \(perTry) a try", &problems)
            expect(f.store.isOnBreak && f.store.correctionError != nil, "still reported, still a break", &problems)

            f.gate.refuses = false
            f.clock.advance(5)
            f.store.runTick()
            expect(!f.store.isOnBreak && f.store.correctionError == nil,
                   "once it can be saved the break ends and the error goes", &problems)
            expect(f.breaks.count == 1 && f.breaks.first?.end == cap, "recorded ending at its cap", &problems)

            // The same for the end that input brings.
            guard let g = make(prepare: running) else { return problems + ["could not create isolated preferences"] }
            defer { g.close() }
            g.store.startBreak(length: 300)
            g.clock.advance(300)
            g.gate.refuses = true
            g.idle.value = 0
            for _ in 0..<60 { g.store.runTick(); g.clock.advance(1) }
            expect(g.store.isOnBreak && g.store.correctionError != nil,
                   "work that cannot be saved is reported and the break stands", &problems)
            g.gate.refuses = false
            for _ in 0..<70 { g.store.runTick(); g.clock.advance(1) }
            expect(!g.store.isOnBreak && g.store.correctionError == nil,
                   "and ends once it can", &problems)
            return problems
        }
    }

    static func capEndIsSettled() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var ended = 0
            f.store.onBreakEnded = { ended += 1 }
            f.store.startBreak(length: 300)
            guard let capEnd = f.store.activeBreak?.capEnd(longAwayCap: f.persistence.longAwayCap) else {
                return ["no break began"]
            }
            f.clock.advance(300 + f.persistence.longAwayCap - 1)
            f.store.runTick()
            expect(f.store.isOnBreak, "a second before the cap it is still a break", &problems)
            f.clock.advance(1)
            f.store.runTick()
            expect(!f.store.isOnBreak && f.engine.state == .idle, "at the cap it ends, and so does the session", &problems)
            expect(f.breaks.count == 1 && f.breaks.first?.end == capEnd, "recorded ending at the cap", &problems)
            expect(ended == 1 && Set(f.persistence.breakClock.floors.values) == [capEnd]
                   && f.persistence.breakClock.floors.count == BreakTier.allCases.count,
                   "and a rest that counts, from where it was recorded to end", &problems)
            return problems
        }
    }
}
