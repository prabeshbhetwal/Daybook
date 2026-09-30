import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 59

    static func testPurposeLearner() -> [String] {
        var problems: [String] = []
        let base = FocusConstants.autoStartThreshold

        // Nothing learned yet: the shared default stands.
        let cold = PurposeLearner(signals: [:])
        expectClose(cold.startThreshold(for: "com.google.Chrome"), base,
                    "an app with no history uses the default", &problems)
        expect(cold.summary(for: "com.google.Chrome") == nil,
               "no claim is made without observations", &problems)

        // One rejection is not a pattern. Adapting to it would make the app
        // erratic in exactly the way an automatic mode must not be.
        var signals = PurposeLearner(signals: [:]).recordingUndone("com.google.Chrome")
        expectClose(PurposeLearner(signals: signals).startThreshold(for: "com.google.Chrome"),
                    base, "one undo is below the minimum and moves nothing", &problems)

        // Three rejections are. The app becomes harder to convince.
        signals = PurposeLearner(signals: signals).recordingUndone("com.google.Chrome")
        signals = PurposeLearner(signals: signals).recordingUndone("com.google.Chrome")
        let cautious = PurposeLearner(signals: signals)
        expect(cautious.startThreshold(for: "com.google.Chrome") > base,
               "repeated undos demand more evidence", &problems)
        expect(cautious.summary(for: "com.google.Chrome")?.contains("Slower") == true,
               "and the app can say so in plain words", &problems)

        // Sessions kept pull the other way.
        var kept: [String: LearnedSignal] = [:]
        for _ in 0..<4 {
            kept = PurposeLearner(signals: kept).recordingKept("com.apple.dt.Xcode")
        }
        let eager = PurposeLearner(signals: kept)
        expect(eager.startThreshold(for: "com.apple.dt.Xcode") < base,
               "sessions consistently kept make the app quicker to start", &problems)

        // Bounded both ways: learning may not cross the stop threshold, or
        // starting and stopping would fight each other.
        var lopsided: [String: LearnedSignal] = [:]
        for _ in 0..<50 {
            lopsided = PurposeLearner(signals: lopsided).recordingKept("com.apple.Terminal")
        }
        let floor = PurposeLearner(signals: lopsided).startThreshold(for: "com.apple.Terminal")
        expect(floor > FocusConstants.autoStopThreshold,
               "the learned threshold stays above the stop threshold, got \(floor)", &problems)
        var undone: [String: LearnedSignal] = [:]
        for _ in 0..<50 {
            undone = PurposeLearner(signals: undone).recordingUndone("com.apple.Terminal")
        }
        expect(PurposeLearner(signals: undone).startThreshold(for: "com.apple.Terminal") <= 0.9,
               "and never rises past 0.9, which would mute it entirely", &problems)

        // Learning never touches recorded facts, only the threshold.
        expect(PurposeLearner(signals: signals).startThreshold(for: nil) == base,
               "an unknown app cannot be learned about", &problems)
        return problems
    }

    // MARK: - 61

    /// The reported defect: a session read as stopped until the away card was
    /// answered, and the gap counted as work while it sat there. Both directions
    /// matter — the clock must keep running, and the unanswered default must be
    /// the honest one rather than the flattering one.
    static func testUnansweredAwayIsHonest() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 600
        // Long enough to raise the card, short enough not to trip the cap that
        // ends a session outright — a lunch, not a night.
        let away: TimeInterval = 2 * 3_600
        let since: TimeInterval = 480

        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.transition(on: .launch)
        clock.advance(work)
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        clock.advance(away)
        engine.transition(on: .awayEnded)

        // Nothing answered yet.
        expectClose(engine.elapsed, work, "the gap is excluded before any answer", &problems)
        clock.advance(since)
        expectClose(engine.elapsed, work + since,
                    "the clock keeps running while the card is up", &problems)
        expect(engine.state != .idle, "an unanswered card must not idle the session",
               &problems)

        // Answering "I was working" is the only thing that adds the gap back.
        engine.transition(on: .decision(.mergeTime))
        expectClose(engine.elapsed, work + away + since,
                    "merge adds the gap back exactly once", &problems)

        // A card left up across a quit must not turn the downtime into work.
        let saved = TestClock(base)
        let stale = makeEngine(saved)
        stale.transition(on: .launch)
        saved.advance(work)
        stale.transition(on: .awayBegan(trigger: .systemSleep))
        saved.advance(away)
        stale.transition(on: .awayEnded)
        let snapshot = stale.snapshot()

        let later = TestClock(saved.value.addingTimeInterval(2 * 86_400))
        let reopened = makeEngine(later)
        reopened.restore(from: snapshot)
        // Two days is past the cap, so the stretch now ends at the relaunch
        // where it was left; its work is on the record rather than the clock.
        let kept = reopened.archive.records.reduce(0) { $0 + $1.workSeconds }
            + (reopened.state == .idle ? 0 : reopened.elapsed)
        expectClose(kept, work,
                    "two days with the app shut must not become work", &problems)
        expect(reopened.state == .idle,
               "a card left up for two days ends at the relaunch, got \(reopened.state)", &problems)
        expectClose(reopened.archive.records.last.map { $0.end.timeIntervalSince(snapshot.savedAt) } ?? -1, 0,
                    "the record ends where the app was left", &problems)
        return problems
    }

    // MARK: - 63

    /// An absence long enough to be a night ends the session where it began,
    /// rather than holding it open and asking about it later. Sessions kept open
    /// across a night produced records spanning thirty-two hours, and every
    /// per-day figure in the app then had to guess which day the work belonged to.
    static func testLongAwayEndsSession() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 40 * 60

        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.sessionName = "Evening"
        engine.transition(on: .launch)
        clock.advance(work)
        let leftAt = clock.value
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        clock.advance(9 * 3_600)
        engine.transition(on: .awayEnded)

        expect(engine.state == .idle,
               "a nine-hour absence should end the session, got \(engine.state)", &problems)
        guard let record = engine.archive.records.last else {
            problems.append("the ended session should be archived")
            return problems
        }
        expectClose(record.workSeconds, work, "archived work is what was worked", &problems)
        expectClose(record.end.timeIntervalSince(leftAt), 0,
                    "the record ends where the user walked away", &problems)
        expectClose(record.span, work, "span must not swallow the night", &problems)

        // The threshold is a cap, not a replacement for the card: a two-hour
        // lunch still asks.
        let lunchClock = TestClock(base)
        let lunch = makeEngine(lunchClock)
        lunch.transition(on: .launch)
        lunchClock.advance(work)
        lunch.transition(on: .awayBegan(trigger: .screenLock))
        lunchClock.advance(2 * 3_600)
        lunch.transition(on: .awayEnded)
        if case .awaitingUserDecision = lunch.state {} else {
            problems.append("a two-hour absence should still ask, got \(lunch.state)")
        }

        // The cap is a setting, not a constant: raise it and the same nine-hour
        // absence becomes a question again rather than an ending.
        let patientClock = TestClock(base)
        let patient = makeEngine(patientClock)
        patient.store.longAwayCap = 12 * 3_600
        patient.transition(on: .launch)
        patientClock.advance(work)
        patient.transition(on: .awayBegan(trigger: .systemSleep))
        patientClock.advance(9 * 3_600)
        patient.transition(on: .awayEnded)
        if case .awaitingUserDecision = patient.state {} else {
            problems.append("with a 12h cap, nine hours should still ask, got "
                            + "\(patient.state)")
        }

        // A misclick is not history.
        let quickClock = TestClock(base)
        let quick = makeEngine(quickClock)
        quick.start(workType: .deepWork, intent: "oops")
        quickClock.advance(3)
        quick.stop()
        expect(quick.archive.records.isEmpty,
               "a three-second session must not be archived", &problems)
        return problems
    }
}
