import Foundation

/// What the person's actions do about a break, as `BreakStoreChecks` sees the
/// store: stepping away, Stop and Continue when the break cannot be ended, a
/// break restored at launch, and a break begun after a Later.
extension BreakStoreChecks {
    static func awayIsIgnoredOnBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var began = 0, resumed = 0
            f.store.onAwayBegan = { began += 1 }
            f.store.onAwayEnded = { resumed += 1 }
            f.store.startBreak()
            f.clock.advance(60)
            f.store.markAway()
            expect(f.engine.state == .paused(reason: .onBreak) && f.store.isOnBreak,
                   "I'm stepping away leaves the break as it was, got \(f.engine.state)", &problems)
            expect(began == 0, "and does not suspend the tracker, got \(began)", &problems)
            f.store.endAway()
            expect(!f.store.isOnBreak && resumed == 0, "I'm back on a break is End break, and resumes nothing", &problems)
            return problems
        }
    }

    static func refusedEndStopsStop() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            f.store.startBreak()
            f.clock.advance(100)
            f.gate.refuseNext = 1
            f.store.stop()
            expect(f.store.isOnBreak && f.engine.state == .paused(reason: .onBreak),
                   "Stop does not go on without the break, got \(f.engine.state)", &problems)
            expect(f.store.correctionError != nil, "and the reason is still shown", &problems)
            expect(f.engine.archive.records.isEmpty, "nothing was half written", &problems)

            f.store.stop()
            expect(!f.store.isOnBreak && f.engine.state == .idle && f.breaks.count == 1
                   && f.store.correctionError == nil,
                   "once it can be saved Stop ends the break and the session", &problems)
            return problems
        }
    }

    static func refusedContinueKeepsBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            let app = AppUsageSummary(bundleID: "com.example.target", appName: "Target",
                                      totalSeconds: 600, longestSeconds: 600, recent: [])
            f.store.startBreak()
            f.clock.advance(100)
            f.store.continueApp(app)
            expect(f.store.isOnBreak && f.breaks.isEmpty && f.persistence.breakClock.floors.isEmpty,
                   "a Continue that is refused neither ends nor credits the break", &problems)
            f.appRunning.value = true
            f.store.continueApp(app)
            expect(!f.store.isOnBreak && f.engine.state == .running && f.breaks.count == 1,
                   "one that goes ahead ends it first", &problems)
            return problems
        }
    }

    static func restoredBreakIsSeeded() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: { engine, clock in
                engine.start(workType: .deepWork, intent: "Parser")
                clock.advance(600)
                engine.startBreak(length: 300)
                clock.advance(100)
                // Quit and launched again, mid-break.
                engine.restore(from: engine.snapshot())
            }) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            expect(f.store.isOnBreak, "setup: the break survived the relaunch", &problems)
            expect(f.store.breakRemaining == 200,
                   "its time left is known before the first tick, got \(f.store.breakRemaining)", &problems)
            return problems
        }
    }

    static func laterThenStartAnswers() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = makeDue() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var shown: BreakPrompt?
            f.store.onBreakDue = { shown = $0; return true }
            f.store.refresh()
            guard let prompt = shown else { return ["no reminder was raised"] }
            f.store.laterBreak(prompt)
            f.clock.advance(120)
            f.store.startBreak()
            let entry = f.store.breakLog.prompts.first { $0.id == prompt.id }
            expect(entry?.outcome == .started && entry?.laterCount == 1,
                   "the break answers the reminder that was put off, got \(String(describing: entry?.outcome))",
                   &problems)
            return problems
        }
    }
}
