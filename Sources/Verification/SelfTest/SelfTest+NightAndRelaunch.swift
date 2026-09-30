import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 77

    /// The ordinary overnight: input stops, the session pauses itself, the
    /// display sleeps and locks, and the next thing the engine hears is the
    /// unlock in the morning. The unlock used to drop the interval because the
    /// session was already paused, and the first sample afterwards already saw
    /// fresh input, so the night was merged back into a surviving session —
    /// the lock-while-running path ended it, the idle-then-lock path did not.
    static func testIdleThenLockedNightEndsSession() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Evening")
        clock.advance(45 * 60)
        let left = clock.value                                    // last keystroke
        clock.advance(FocusConstants.idlePauseThreshold)
        engine.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        expect(engine.state == .paused(reason: .idle), "pauses itself first", &problems)

        // Display sleep locks the screen a few minutes later; the ticker stops
        // with the usage stretch. Nothing is heard until morning.
        clock.advance(5 * 60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(9 * 3_600)
        engine.transition(on: .awayEnded)
        expect(engine.state == .idle,
               "the unlock ends a session whose absence outgrew the cap, got \(engine.state)",
               &problems)
        guard let record = engine.archive.records.last else {
            return problems + ["a record should have been written"]
        }
        expectClose(record.workSeconds, 45 * 60, "with only the evening's work", &problems)
        expectClose(record.end.timeIntervalSince(left), 0,
                    "ending at the last keystroke", &problems)

        // The same night with the machine never locked and the app relaunched
        // in the morning: the first sample after restore already sees input.
        let clock2 = TestClock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Evening")
        clock2.advance(30 * 60)
        clock2.advance(FocusConstants.idlePauseThreshold)
        engine2.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        let blob = engine2.snapshot()
        clock2.advance(8 * 3_600)
        let morning = makeEngine(clock2)                          // fresh process
        morning.restore(from: blob)
        // The relaunch itself now sees the night past the cap and ends it.
        expect(morning.state == .idle, "a relaunch past the cap ends the paused stretch, got \(morning.state)",
               &problems)
        expectClose(morning.archive.records.last?.workSeconds ?? -1, 30 * 60,
                    "and the record holds the evening's work only", &problems)

        // The same night with the app never quit: the first sample in the
        // morning already sees input, and must not rescue the paused stretch.
        let clockLive = TestClock(base)
        let live = makeEngine(clockLive)
        live.start(workType: .deepWork, intent: "Evening")
        clockLive.advance(30 * 60)
        let liveLeft = clockLive.value                            // last keystroke
        clockLive.advance(FocusConstants.idlePauseThreshold)
        live.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clockLive.advance(8 * 3_600)
        live.transition(on: .idleObserved(seconds: 1))            // the user is typing
        expect(live.state == .idle,
               "a sample showing input does not rescue a night past the cap, got \(live.state)",
               &problems)
        expectClose(live.archive.records.last?.workSeconds ?? -1, 30 * 60,
                    "and the live record holds the evening's work only", &problems)
        expectClose(live.archive.records.last.map { $0.end.timeIntervalSince(liveLeft) } ?? -1, 0,
                    "ending where the pause began", &problems)

        // Under the asking threshold, input still resumes an idle pause quietly.
        let clock3 = TestClock(base)
        let engine3 = makeEngine(clock3)
        engine3.start(workType: .deepWork, intent: "Short")
        clock3.advance(20 * 60)
        clock3.advance(FocusConstants.idlePauseThreshold)
        engine3.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock3.advance(2 * 60)
        engine3.transition(on: .idleObserved(seconds: 0))
        expect(engine3.state == .running, "a twelve-minute idle resumes", &problems)
        expectClose(engine3.elapsed, 20 * 60,
                    "having excluded exactly the absence", &problems)

        // Between the threshold and the cap it is asked about, like a lock.
        clock3.advance(5 * 60)
        clock3.advance(FocusConstants.idlePauseThreshold)
        engine3.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock3.advance(25 * 60)
        engine3.transition(on: .idleObserved(seconds: 0))
        guard case .awaitingUserDecision(let asked, _) = engine3.state else {
            return problems + ["a 35-minute idle absence should be asked about, got \(engine3.state)"]
        }
        expectClose(asked, 35 * 60, "and the card names the whole absence", &problems)
        engine3.transition(on: .decision(.continueSession))
        expectClose(engine3.archive.records.last?.workSeconds ?? -1, 25 * 60,
                    "'I was away' closes the session with its 25 worked minutes", &problems)

        // The same through an unlock: idle, then locked, then back under the cap.
        let clock4 = TestClock(base)
        let engine4 = makeEngine(clock4)
        engine4.start(workType: .deepWork, intent: "Lunch")
        clock4.advance(30 * 60)
        clock4.advance(FocusConstants.idlePauseThreshold)
        engine4.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock4.advance(3 * 60)
        engine4.transition(on: .awayBegan(trigger: .screenLock))
        clock4.advance(40 * 60)
        engine4.transition(on: .awayEnded)
        guard case .awaitingUserDecision(let lunch, _) = engine4.state else {
            return problems + ["an idle-then-locked lunch should be asked about, got \(engine4.state)"]
        }
        expectClose(lunch, 53 * 60, "measured from the last keystroke, not the lock", &problems)
        return problems
    }

    // MARK: - 78

    /// The shadow of a second absence is persisted. Bank thirty minutes while
    /// the card is up, quit, relaunch, answer: the successor used to inherit
    /// those thirty minutes as work because the bank lived only in memory. And
    /// an absence still *open* at the quit is measured from when it began, not
    /// from the write.
    static func testShadowAwaySurvivesRelaunch() -> [String] {
        var problems: [String] = []
        // A closed second absence, then a quit while working.
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Refactor")
        clock.advance(40 * 60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(33 * 60)
        engine.transition(on: .awayEnded)                          // card up
        clock.advance(7 * 60)                                      // working
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(30 * 60)
        engine.transition(on: .awayEnded)                          // banked
        clock.advance(5 * 60)                                      // working
        let blob = engine.snapshot()
        expectClose(blob.shadowAway ?? 0, 30 * 60, "the bank is written down", &problems)
        clock.advance(2 * 3_600)                                   // quit; two hours pass
        let relaunched = makeEngine(clock)
        relaunched.restore(from: blob)
        guard case .awaitingUserDecision = relaunched.state else {
            return problems + ["should still be awaiting, got \(relaunched.state)"]
        }
        relaunched.transition(on: .decision(.continueSession))
        // Keep the actual return rather than moving the interval to relaunch:
        // 40m belongs before the first absence; the later 7m + 5m belongs to
        // its successor. Neither absence nor closed-app time becomes work.
        expectClose(relaunched.archive.records.last?.workSeconds ?? -1, 40 * 60,
                    "the closed session retains work before the absence", &problems)
        expectClose(relaunched.elapsed, 12 * 60,
                    "the successor retains work after the real return", &problems)
        expectClose(relaunched.sessionStartDate.timeIntervalSince(base), 73 * 60,
                    "the successor starts at the real return, not the relaunch", &problems)
        expectClose((relaunched.archive.records.last?.workSeconds ?? 0) + relaunched.elapsed,
                    52 * 60, "all fifty-two worked minutes survive", &problems)

        // The same, but the second absence is still open at the quit.
        let clock2 = TestClock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Refactor")
        clock2.advance(40 * 60)
        engine2.transition(on: .awayBegan(trigger: .screenLock))
        clock2.advance(33 * 60)
        engine2.transition(on: .awayEnded)                         // card up
        clock2.advance(7 * 60)
        engine2.transition(on: .awayBegan(trigger: .screenLock))   // locked…
        clock2.advance(10 * 60)
        let blob2 = engine2.snapshot()                             // …written while locked
        clock2.advance(50 * 60)                                    // still locked; quit; relaunch
        let relaunched2 = makeEngine(clock2)
        relaunched2.restore(from: blob2)
        relaunched2.transition(on: .decision(.mergeTime))
        // 40m worked + 33m merged + 7m worked. The locked hour is not work.
        expectClose(relaunched2.elapsed, 80 * 60,
                    "an absence open at the quit is excluded from its start", &problems)
        return problems
    }

    // MARK: - 79

    /// The stat row's Sessions, Focused and Longest must answer about the
    /// selected day. They read the engine's today-only figures whatever day the
    /// dashboard was browsing, so Yesterday showed yesterday's Tracked beside
    /// today's session count. And Longest named the busiest app, which is not
    /// what the figure measures.
    static func testDayScopedSessionFigures() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let archive = makeArchive(clock)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.value)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return ["could not build a two-day window"]
        }
        func record(_ name: String, day: Date, hour: Double, minutes: Double,
                    type: WorkType = .deepWork) {
            let start = day.addingTimeInterval(hour * 3_600)
            archive.append(SessionRecord(name: name, workType: type, start: start,
                                         end: start.addingTimeInterval(minutes * 60),
                                         workSeconds: minutes * 60))
        }
        record("Slides", day: yesterday, hour: 9, minutes: 50)
        record("Review", day: yesterday, hour: 14, minutes: 95)
        record("Lunch", day: yesterday, hour: 12, minutes: 40, type: .breakTime)
        record("Parser", day: today, hour: 10, minutes: 30)

        expectClose(archive.workSeconds(on: yesterday), 145 * 60,
                    "focused yesterday", &problems)
        return problems
    }
}
