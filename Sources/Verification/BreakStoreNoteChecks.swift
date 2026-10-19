import Foundation

/// The session side of `BreakStoreChecks`: the actions that must end a break
/// first, what the app does when one ends, and the ticker that runs it.
extension BreakStoreChecks {
    static func undoEndsBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for route in ["Undo", "the naming row's Undo", "Retry", "an activity rule's Undo"] {
                guard let f = make(rules: route == "an activity rule's Undo",
                                   prepare: route == "an activity rule's Undo" ? { _, _ in } : autoRunning)
                else { return problems + ["could not create isolated preferences"] }
                defer { f.close() }
                var ended = 0
                f.store.onBreakEnded = { ended += 1 }
                var owner: AutomaticActivityRecord?
                if route == "an activity rule's Undo" {
                    f.clock.advance(120)
                    owner = f.store.applyAutomaticActivity(f.autoAction())
                    f.clock.advance(1_200)
                }
                f.store.startBreak()
                expect(f.store.isAutoSession, "\(route): the session is the app's own", &problems)
                f.clock.advance(100)
                var undone = false
                switch route {
                case "Undo": undone = f.store.undoAutoSession()
                case "the naming row's Undo":
                    f.store.undoAutomaticSessionCorrection()
                    undone = f.engine.state == .idle
                case "Retry":
                    f.store.correctionRetry = .discarding(threadID: f.engine.activeThreadID,
                                                          sessionStart: f.engine.sessionStartDate,
                                                          resumeTracking: false)
                    undone = f.store.retryLastCorrection()
                default:
                    undone = owner.map { f.store.undoAutomaticActivity(expectedRecordID: $0.resultingRecordID) } ?? false
                }
                expect(undone && f.engine.state == .idle, "\(route) works on a session with a break on it", &problems)
                expect(f.engine.activeBreak == nil && !f.store.isOnBreak,
                       "\(route): no break is left standing without its session", &problems)
                expect(f.breaks.count == 1 && f.breaks.first?.workSeconds == 100,
                       "\(route): the break is recorded once, at its real length", &problems)
                expect(f.engine.archive.records.allSatisfy { $0.workType == .breakTime },
                       "\(route): the invented session leaves nothing in history, got "
                       + "\(f.engine.archive.records.filter { $0.workType != .breakTime }.map(\.name))", &problems)
                expect(ended == 1 && f.persistence.breakClock.floors.count == BreakTier.allCases.count,
                       "\(route): the rest counts, once, got \(ended)", &problems)
            }
            return problems
        }
    }

    static func sessionActionsEndBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Start with a break and no session: the break ends, then the session starts.
            if let f = make() {
                defer { f.close() }
                f.store.startBreak()
                f.clock.advance(120)
                f.store.intent = "Parser"
                f.store.workType = .deepWork
                f.store.start()
                expect(!f.store.isOnBreak && f.engine.state == .running && f.engine.sessionName == "Parser",
                       "Start ends the break and begins the session, got \(f.engine.state)", &problems)
                expect(f.breaks.count == 1, "and the break is on record", &problems)
            }
            if let f = make() {
                defer { f.close() }
                f.store.startBreak()
                f.clock.advance(120)
                f.store.startQuick(QuickStart(id: "parser", name: "Parser", workType: .deepWork))
                expect(!f.store.isOnBreak && f.engine.state == .running, "so does a quick start", &problems)
            }
            if let f = make() {
                defer { f.close() }
                f.store.startBreak()
                f.clock.advance(120)
                expect(f.store.performSessionHotKeyAction() == .started && !f.store.isOnBreak
                       && f.breaks.count == 1, "so does the shortcut", &problems)
            }
            // Pause on a break is Resume, and Resume is End break.
            if let f = make(prepare: running) {
                defer { f.close() }
                f.store.startBreak()
                f.clock.advance(60)
                f.store.togglePause()
                expect(!f.store.isOnBreak && f.engine.state == .running && f.breaks.count == 1,
                       "Pause during a break ends it and the session runs, got \(f.engine.state)", &problems)
                expect(f.persistence.breakClock.floors.count == BreakTier.allCases.count,
                       "and the rest counts, as End break's does", &problems)
                f.store.togglePause()
                expect(f.engine.state == .paused(reason: .manual), "and the next press pauses", &problems)
            }
            return problems
        }
    }

    static func frontmostFedBack() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: { engine, clock in
                engine.start(workType: .deepWork, intent: "Parser")
                clock.advance(600)
                engine.transition(on: .appActivated(bundleID: "com.a", name: "Alpha"))
            }) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            f.store.startBreak()
            f.engine.transition(on: .appActivated(bundleID: "com.b", name: "Beta"))
            expect(f.engine.currentAppBundleID == "com.a", "a break drops app activations", &problems)
            f.front.value = (bundleID: "com.b", name: "Beta")
            f.clock.advance(100)
            f.store.endBreak()
            expect(f.engine.currentAppBundleID == "com.b" && f.engine.currentAppName == "Beta",
                   "the app now in front is what the session reads, got \(String(describing: f.engine.currentAppBundleID))",
                   &problems)

            // No session behind the break: a work app in front starts nothing,
            // though the legacy heuristic would start one from idle.
            guard let g = make() else { return problems + ["could not create isolated preferences"] }
            defer { g.close() }
            g.store.startBreak()
            g.front.value = (bundleID: "com.apple.dt.Xcode", name: "Xcode")
            g.clock.advance(100)
            expect(g.persistence.automationMode == .legacyHeuristic, "setup: the legacy heuristic is on", &problems)
            g.store.endBreak()
            expect(g.engine.state == .idle && !g.store.isOnBreak, "a break with no session starts none", &problems)
            return problems
        }
    }

    static func noStaleLongAwayCard() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: { engine, clock in
                engine.start(workType: .deepWork, intent: "Parser")
                clock.advance(600)
                engine.transition(on: .awayBegan(trigger: .screenLock))
                clock.advance(engine.store.longAwayCap + 60)
                engine.transition(on: .awayEnded)
            }) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            expect(f.engine.lastLongAwayTransition != nil, "setup: a long absence has just ended", &problems)
            f.store.startBreak()
            expect(f.store.isOnBreak, "the break begins", &problems)
            expect(f.engine.lastLongAwayTransition == nil,
                   "the absence's result does not outlive the break's start", &problems)
            expect(f.store.correctionError == nil, "and no card is shown for it", &problems)
            return problems
        }
    }

    static func tickerAndExtend() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var over = 0
            var reachedScreen = false
            f.store.onBreakOver = { _ in over += 1; return reachedScreen }
            f.store.startBreak(length: 300)
            f.clock.advance(100)
            f.store.runTick()
            expect(f.store.breakRemaining == 200, "the time left counts down, got \(f.store.breakRemaining)", &problems)
            f.clock.advance(200)
            f.store.runTick()
            f.clock.advance(1)
            f.store.runTick()
            expect(over == 2 && f.store.activeBreak?.overNoticed == false,
                   "a prompt that missed the screen is offered again, got \(over)", &problems)
            reachedScreen = true
            f.clock.advance(1)
            f.store.runTick()
            f.clock.advance(1)
            f.store.runTick()
            expect(over == 3 && f.store.activeBreak?.overNoticed == true,
                   "one that reached it is not, got \(over)", &problems)
            expect(f.store.breakRemaining == -3, "overtime counts as negative time left", &problems)

            f.store.extendBreak()
            // Three seconds over: five minutes from now, not from the old end.
            expect(f.store.activeBreak?.plannedLength == 603 && f.store.activeBreak?.overNoticed == false
                   && f.store.breakRemaining == 300, "+5 min gives five minutes and re-arms the prompt", &problems)
            f.clock.advance(300)
            f.store.runTick()
            expect(over == 4, "the prompt comes back at the new end, got \(over)", &problems)

            // The ticker keeps running for a break that has no session and no tracker.
            guard let g = make(ticker: true) else { return problems + ["could not create isolated preferences"] }
            defer { g.close() }
            expect(!g.store.hasScheduledTicker, "nothing ticks with nothing under way", &problems)
            g.store.startBreak()
            expect(g.store.hasScheduledTicker, "a break keeps the ticker running", &problems)
            g.store.endBreak()
            expect(!g.store.hasScheduledTicker, "and it stops with the break", &problems)
            return problems
        }
    }
}
