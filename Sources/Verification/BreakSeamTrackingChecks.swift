import Foundation

/// The usage tracker and the presence gate across a break: nothing is
/// recorded while one runs, and a break nobody was at proves nobody is back.
extension BreakSeamChecks {
    private enum Way: String, CaseIterable {
        case appSwitch = "an app switch"
        case unlock = "an unlock"
        case input = "input at the keys"
    }

    /// One of the ways the app asks the tracker to start, with Slack in front.
    @MainActor
    private static func tryToStart(_ way: Way, _ f: BreakStoreChecks.Fixture) {
        switch way {
        case .appSwitch:
            _ = f.store.handleApplicationActivation(bundleID: "com.slack", name: "Slack")
        case .unlock:
            f.store.prepareTrackingResume(bundleID: "com.slack", name: "Slack")
            _ = f.store.confirmPresence(at: f.clock.value)
        case .input:
            f.store.prepareTrackingResume(bundleID: "com.slack", name: "Slack")
            _ = f.store.applyPresenceObservation(.active(since: f.clock.value))
        }
    }

    static func breakRecordsNoAppUse() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for way in Way.allCases {
                guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                    return problems + ["could not create isolated preferences"]
                }
                defer { f.close() }
                let tracker = trackerOn(f)
                tracker.appActivated(bundleID: "com.xcode", name: "Xcode")
                f.clock.advance(60)
                f.store.startBreak(length: 300)
                let began = f.clock.value
                f.clock.advance(30)
                tryToStart(way, f)
                f.clock.advance(30)
                tracker.flush()
                expect(tracker.currentBundleID == nil,
                       "\(way.rawValue) started the tracker on \(tracker.currentBundleID ?? "nil") during the break",
                       &problems)
                let during = f.usage.sessions.filter { $0.end > began }.map(\.bundleID)
                expect(during.isEmpty, "\(way.rawValue) recorded \(during) during the break", &problems)

                // The break ends with the person at the keys: use is recorded again.
                f.front.value = ("com.safari", "Safari")
                f.store.endBreak()
                f.store.refresh()
                f.clock.advance(60)
                tracker.flush()
                expect(tracker.currentBundleID == "com.safari",
                       "after \(way.rawValue) and the break's end the tracker follows Safari, got "
                       + "\(tracker.currentBundleID ?? "nil")", &problems)
                expect(f.usage.sessions.contains { $0.bundleID == "com.safari" && $0.end > began },
                       "and Safari's use is recorded once the break is over", &problems)
            }
            return problems
        }
    }

    static func capExpiryProvesNoPresence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // The Mac slept through the break and nobody has touched it since.
            guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            let tracker = trackerOn(f)
            var released = 0
            f.store.onDeferredAutomationReady = { released += 1 }
            f.front.value = ("com.xcode", "Xcode")
            f.store.startBreak(length: 300)
            f.store.noteMachineWake()
            f.clock.advance(300 + f.persistence.longAwayCap)
            f.store.runTick()
            f.store.refresh()
            expect(!f.store.isOnBreak && f.breaks.count == 1 && f.engine.state == .idle,
                   "setup: the break ran out its cap and ended the session, got \(f.engine.state)", &problems)
            expect(tracker.isObserving && tracker.currentBundleID == nil,
                   "the tracker has the app in front waiting for a person, not recording", &problems)
            expect(released == 0, "no deferred automation is released by a break nobody was at", &problems)
            let delivered = f.store.handleApplicationActivation(bundleID: "com.slack", name: "Slack")
            expect(!delivered && f.engine.state == .idle,
                   "the wake gate still waits: a switch is held back and starts no session, got \(f.engine.state)",
                   &problems)

            // A real return still starts everything.
            _ = f.store.confirmPresence(at: f.clock.value)
            expect(tracker.currentBundleID == "com.slack" && released == 1,
                   "a person's return then starts the waiting app and releases automation once", &problems)

            // The same wake, but the person pressed End break: that is a return.
            guard let g = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { g.close() }
            let gTracker = trackerOn(g)
            var gReleased = 0
            g.store.onDeferredAutomationReady = { gReleased += 1 }
            g.front.value = ("com.xcode", "Xcode")
            g.store.startBreak(length: 300)
            g.store.noteMachineWake()
            g.clock.advance(100)
            g.store.endBreak()
            g.store.refresh()
            expect(gTracker.currentBundleID == "com.xcode" && gReleased == 1,
                   "a break the person ended proves they are back: the app records and automation is released",
                   &problems)
            return problems
        }
    }

    static func breakOverWaitsForPresence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            var asked = 0
            f.store.onBreakOver = { _ in asked += 1; return true }
            f.store.startBreak(length: 300)
            f.store.noteMachineWake()
            f.clock.advance(301)
            f.store.runTick()
            expect(asked == 0 && f.store.activeBreak?.overNoticed == false,
                   "behind the wake gate the break-over prompt is not shown, asked \(asked) times", &problems)

            _ = f.store.confirmPresence(at: f.clock.value)
            f.store.screenLocked = true
            f.clock.advance(1)
            f.store.runTick()
            expect(asked == 0, "nor to a locked screen, asked \(asked) times", &problems)

            f.store.screenLocked = false
            f.clock.advance(1)
            f.store.runTick()
            expect(asked == 1 && f.store.activeBreak?.overNoticed == true,
                   "once someone can be there it is shown, once, asked \(asked) times", &problems)
            f.clock.advance(1)
            f.store.runTick()
            expect(asked == 1, "and not again", &problems)
            return problems
        }
    }
}
