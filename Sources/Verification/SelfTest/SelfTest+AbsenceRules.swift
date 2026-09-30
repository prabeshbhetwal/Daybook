import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 74

    /// A second absence while the away card is up must not dissolve into the
    /// successor session as work. `apply` used to drop the recorded interval on
    /// the floor, so locking the screen again before answering credited the
    /// whole second absence to whichever session survived the decision.
    static func testShadowAwayIsNotWork() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 40 * 60
        let away: TimeInterval = 33 * 60          // past the default 15m threshold
        let secondAway: TimeInterval = 30 * 60
        let workedBetween: TimeInterval = 7 * 60  // back and working, then locked again
        let workedAfter: TimeInterval = 5 * 60    // unlocked and working, then answered

        func run(_ decision: UserDecision) -> SessionEngine {
            let clock = TestClock(base)
            let engine = makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Refactor")
            clock.advance(work)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)          // the card goes up
            clock.advance(workedBetween)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(secondAway)
            engine.transition(on: .awayEnded)          // banked; card still up
            clock.advance(workedAfter)
            engine.transition(on: .decision(decision))
            return engine
        }

        let kept = run(.continueSession)
        expectClose(kept.elapsed, workedBetween + workedAfter,
                    "'I was away': the new session holds only worked minutes",
                    &problems)

        let merged = run(.mergeTime)
        expectClose(merged.elapsed, work + away + workedBetween + workedAfter,
                    "'I was working' merges the first gap and only the first",
                    &problems)
        return problems
    }

    // MARK: - 75

    /// An absence with the screen never locked used to escape the long-away
    /// rule entirely: the lock path ends a session past the cap, but a lid left
    /// open overnight held it paused forever and produced a record spanning the
    /// whole night on resume.
    static func testUnlockedAbsenceEndsSession() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Evening")
        clock.advance(50 * 60)
        // Input stops; ten minutes later the ticker's sample crosses the
        // threshold and the pause is backdated to the last keystroke.
        clock.advance(FocusConstants.idlePauseThreshold)
        engine.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        let left = clock.value.addingTimeInterval(-FocusConstants.idlePauseThreshold)
        expect(engine.state == .paused(reason: .idle), "idle pauses first", &problems)

        // The absence grows past the cap with no lock and no wake event.
        let cap = engine.store.longAwayCap
        clock.advance(cap)
        engine.transition(on: .idleObserved(
            seconds: cap + FocusConstants.idlePauseThreshold))
        expect(engine.state == .idle, "past the cap the session ends", &problems)
        guard let record = engine.archive.records.last else {
            return problems + ["a record should have been written"]
        }
        expectClose(record.workSeconds, 50 * 60,
                    "with only the worked minutes", &problems)
        expectClose(record.end.timeIntervalSince(left), 0,
                    "ending where input stopped", &problems)

        // The marked-away version comes back through a button, not a tick.
        let clock2 = TestClock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Errand")
        clock2.advance(20 * 60)
        let marked = clock2.value
        engine2.transition(on: .markedAway)
        clock2.advance(engine2.store.longAwayCap + 60)
        let thread = engine2.activeThreadID
        engine2.transition(on: .manualResume)   // "I'm back"
        expect(engine2.state == .running,
               "coming back starts a fresh session", &problems)
        expectClose(engine2.elapsed, 0, "whose clock starts now", &problems)
        expect(engine2.activeThreadID == thread, "on the same thread", &problems)
        guard let closed = engine2.archive.records.last else {
            return problems + ["the marked-away session should be archived"]
        }
        expectClose(closed.end.timeIntervalSince(marked), 0,
                    "archived where they marked away", &problems)
        expectClose(closed.workSeconds, 20 * 60,
                    "with the work done before it", &problems)
        return problems
    }

    // MARK: - 76

    /// A distraction pause is hands-on by definition — the dwell that paused
    /// the session required using the break app — so the span-times-usage
    /// intersection credited every paused YouTube minute to the focus goal.
    /// Each record's credit is now capped at the work actually done in it.
    static func testGoalDistractionCap() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }

        // Two hours at the Mac, but 45 minutes of the session were paused on a
        // distraction: the record spans 9-11 while its work is 1h 15m.
        let record = SessionRecord(name: "S", workType: .deepWork,
                                   start: at(9), end: at(11),
                                   workSeconds: 1.25 * 3_600)
        let used = AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                   start: at(9), end: at(11))
        expectClose(FocusedActiveTime.seconds(on: day, records: [record],
                                              usage: [used], running: nil,
                                              calendar: calendar),
                    1.25 * 3_600,
                    "hands-on time inside a pause cannot outgrow the work",
                    &problems)

        // The idle case is unchanged: hands-off time was never in the overlap.
        let idleUse = AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                      start: at(9), end: at(10.25))
        expectClose(FocusedActiveTime.seconds(on: day, records: [record],
                                              usage: [idleUse], running: nil,
                                              calendar: calendar),
                    1.25 * 3_600,
                    "an idle pause is already outside hands-on", &problems)

        // The running session gets the same cap when its work is known.
        expectClose(FocusedActiveTime.seconds(on: day, records: [],
                                              usage: [used],
                                              running: (at(9), at(11)),
                                              runningWork: 30 * 60,
                                              calendar: calendar),
                    30 * 60,
                    "the in-flight session is capped at its work", &problems)
        return problems
    }
}
