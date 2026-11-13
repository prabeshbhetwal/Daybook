import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 1

    static func testElapsedWithPauseCycles() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        clock.advance(600)
        engine.transition(on: .manualPause)
        clock.advance(120)
        engine.transition(on: .manualResume)
        clock.advance(300)
        engine.transition(on: .manualPause)
        clock.advance(60)
        engine.transition(on: .manualResume)
        clock.advance(100)

        expectClose(engine.elapsed, 1000, "elapsed", &problems)
        expectClose(engine.totalPausedDuration, 180, "totalPaused", &problems)
        expect(engine.state == .running, "state should be running", &problems)
        return problems
    }

    // MARK: - 2

    static func testDebounce() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        clock.advance(100)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(3)
        engine.transition(on: .awayEnded)

        expectClose(engine.totalPausedDuration, 0, "totalPaused", &problems)
        expectClose(engine.elapsed, 103, "elapsed", &problems)
        expect(engine.state == .running, "state should stay running", &problems)
        return problems
    }

    // MARK: - 3

    static func testMicroBreak() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        var decisions = 0
        engine.onNeedsDecision = { _, _ in decisions += 1 }

        engine.transition(on: .launch)
        clock.advance(60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(480)
        engine.transition(on: .awayEnded)

        expectClose(engine.totalPausedDuration, 480, "totalPaused", &problems)
        expectClose(engine.elapsed, 60, "elapsed", &problems)
        expect(engine.state == .running, "state should stay running", &problems)
        expect(decisions == 0, "no alert should be raised for a micro-break", &problems)
        return problems
    }

    // MARK: - 4

    static func testExtendedBreak() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        var raised: TimeInterval?
        engine.onNeedsDecision = { away, _ in raised = away }

        engine.transition(on: .launch)
        clock.advance(60)
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        clock.advance(1320)
        engine.transition(on: .awayEnded)

        if case .awaitingUserDecision(let away, _) = engine.state {
            expectClose(away, 1320, "away", &problems)
        } else {
            problems.append("state should be awaitingUserDecision, got \(engine.state)")
        }
        expectClose(raised ?? -1, 1320, "raised alert away", &problems)

        // Events arriving while the alert is up are recorded but never transition
        // (D10), and must not leave a stale away interval behind after the answer.
        engine.transition(on: .awayBegan(trigger: .screenLock))
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        expect(engine.state != .running, "events during the alert must not resume", &problems)
        engine.transition(on: .decision(.mergeTime))
        clock.advance(10)
        engine.transition(on: .awayEnded)
        expect(engine.state == .running, "state should be running after the decision", &problems)
        expectClose(engine.totalPausedDuration, 0, "totalPaused after a stale interval", &problems)
        return problems
    }

    // MARK: - 5

    static func testMergeVersusContinue() -> [String] {
        var problems: [String] = []
        let away: TimeInterval = 1320

        func elapsedAfter(_ decision: UserDecision) -> TimeInterval {
            let clock = TestClock(base)
            let engine = makeEngine(clock)
            engine.transition(on: .launch)
            clock.advance(60)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)
            engine.transition(on: .decision(decision))
            return engine.elapsed
        }

        let merged = elapsedAfter(.mergeTime)
        let continued = elapsedAfter(.continueSession)

        expectClose(merged, 60 + away, "merged elapsed", &problems)
        // Continue now closes the old session where the user left and opens a
        // new one at the moment of return, so its clock starts from zero rather
        // than carrying the pre-away work forward. The two are no longer
        // comparable as one minus the other.
        expectClose(continued, 0, "continue starts a fresh clock", &problems)
        return problems
    }

    // MARK: - 6

    static func testCategoryPrecedence() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        let terminal = "com.apple.Terminal"

        expect(engine.categories.category(for: terminal) == .work,
               "built-in map should classify Terminal as work", &problems)
        engine.categories.setOverride(.breakTime, for: terminal)
        expect(engine.categories.category(for: terminal) == .breakTime,
               "override should beat the built-in map", &problems)
        engine.categories.clearOverride(for: terminal)
        expect(engine.categories.category(for: terminal) == .work,
               "clearing the override should fall back to the built-in map", &problems)
        expect(engine.categories.category(for: "com.example.unknown") == .neutral,
               "unknown bundle identifiers should be neutral", &problems)
        expect(engine.categories.category(for: nil) == .neutral,
               "a nil bundle identifier should be neutral", &problems)
        return problems
    }

    // MARK: - 7

    static func testCoalescing() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        clock.advance(100)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(5)
        engine.transition(on: .awayBegan(trigger: .systemSleep))   // ignored
        clock.advance(595)
        engine.transition(on: .awayEnded)                          // resolves once
        engine.transition(on: .awayEnded)                          // idempotent

        expectClose(engine.totalPausedDuration, 600, "totalPaused", &problems)
        expect(engine.state == .running, "state should stay running", &problems)
        return problems
    }

    // MARK: - 8

    static func testClockSkew() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        // A pause that ends "before" it began must contribute 0, not a negative
        // duration. Without the clamp in `interval(from:)` this accumulates -50
        // and inflates elapsed, so the assertion below fails.
        engine.transition(on: .launch)
        clock.advance(100)
        engine.transition(on: .manualPause)
        clock.value = base.addingTimeInterval(50)      // clock jumps backwards
        engine.transition(on: .manualResume)
        expectClose(engine.totalPausedDuration, 0, "totalPaused after a backwards pause",
                    &problems)

        // Same for an away interval resolved against a backwards clock.
        clock.value = base.addingTimeInterval(200)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.value = base.addingTimeInterval(150)
        engine.transition(on: .awayEnded)
        expectClose(engine.totalPausedDuration, 0, "totalPaused after a backwards away",
                    &problems)
        expect(engine.state == .running, "state should stay running", &problems)

        clock.value = base.addingTimeInterval(-500)    // before the session start
        expectClose(engine.elapsed, 0, "elapsed", &problems)
        return problems
    }
}
