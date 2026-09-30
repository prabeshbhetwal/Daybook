import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 54

    static func testAutoSessionDetector() -> [String] {
        var problems: [String] = []
        let t0 = base
        let highScore = makeFocusScore(0.8, purpose: .coding, explanation: "Warp 5m")

        // Starts only after sustained qualification, not on a single high reading.
        var detector = AutoSessionDetector(breakLength: 600)
        var d = detector.evaluate(score: highScore, at: t0, sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(d == .none, "a single high reading is not enough to start", &problems)

        d = detector.evaluate(score: highScore, at: t0.addingTimeInterval(240),
                              sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(d == .none, "240s of qualification is still short of the 300s dwell", &problems)

        d = detector.evaluate(score: highScore, at: t0.addingTimeInterval(300),
                              sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        if case .start(let workType, _, let backdatedTo, let because) = d {
            expect(workType == .deepWork, "coding purpose maps to deep work", &problems)
            expect(backdatedTo == t0,
                  "backdated to when the qualifying run began, not the decision moment", &problems)
            expect(because == highScore.explanation, "because carries the score's explanation", &problems)
        } else {
            problems.append("expected .start after sustained qualification, got \(d)")
        }

        // A dip below threshold resets the run — verified with a fresh detector.
        var resetter = AutoSessionDetector(breakLength: 600)
        _ = resetter.evaluate(score: highScore, at: t0, sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        let lowScore = makeFocusScore(0.2, explanation: "idle")
        _ = resetter.evaluate(score: lowScore, at: t0.addingTimeInterval(200),
                              sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        let afterDip = resetter.evaluate(score: highScore, at: t0.addingTimeInterval(200 + 300),
                                         sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(afterDip == .none, "a dip below threshold resets the qualifying run", &problems)

        // A hand-started session is never touched, whatever the score does.
        var handsOff = AutoSessionDetector(breakLength: 600)
        let untouched1 = handsOff.evaluate(score: lowScore, at: t0, sessionRunning: true, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(untouched1 == .none, "a hand-started session is never paused", &problems)
        let stillHigh = makeFocusScore(0.9)
        let untouched2 = handsOff.evaluate(score: stillHigh, at: t0.addingTimeInterval(10_000),
                                           sessionRunning: true, sessionWasAutoStarted: false,
                          enginePaused: false)
        expect(untouched2 == .none, "a hand-started session is never ended either", &problems)

        // Media/low score pauses rather than ends, and a pause that outlives
        // breakLength ends at the moment the pause began.
        var running = AutoSessionDetector(breakLength: 600)
        _ = running.evaluate(score: highScore, at: t0, sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        let started = running.evaluate(score: highScore, at: t0.addingTimeInterval(300),
                                       sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
        guard case .start = started else {
            problems.append("setup failed: expected the session to auto-start")
            return problems
        }
        let startMoment = t0.addingTimeInterval(300)

        // Too soon after starting: rule 4 protects it even though score has cratered.
        let mediaScore = makeFocusScore(0.1, purpose: .media, explanation: "Netflix 10m · media")
        let tooSoon = running.evaluate(score: mediaScore, at: startMoment.addingTimeInterval(60),
                                       sessionRunning: true, sessionWasAutoStarted: true,
                                       enginePaused: false)
        expect(tooSoon == .none, "one minute in is inside autoMinRunDwell, so no pause yet", &problems)

        let pauseMoment = startMoment.addingTimeInterval(FocusConstants.autoMinRunDwell + 30)
        let paused = running.evaluate(score: mediaScore, at: pauseMoment,
                                      sessionRunning: true, sessionWasAutoStarted: true,
                                       enginePaused: false)
        if case .pause(let because) = paused {
            expect(because == mediaScore.explanation, "pause explanation carries the score's reason", &problems)
        } else {
            problems.append("expected .pause once the score dropped and min run dwell had passed, got \(paused)")
        }

        // Still within the break allowance: stays paused, no repeat decision.
        let stillPaused = running.evaluate(score: mediaScore, at: pauseMoment.addingTimeInterval(300),
                                           sessionRunning: true, sessionWasAutoStarted: true,
                                           enginePaused: true)
        expect(stillPaused == .none, "a pause shorter than breakLength does not end the session", &problems)

        // Outlives the break length: ends, backdated to when the pause began.
        let endMoment = pauseMoment.addingTimeInterval(601)
        let ended = running.evaluate(score: mediaScore, at: endMoment,
                                     sessionRunning: true, sessionWasAutoStarted: true,
                                     enginePaused: true)
        if case .end(let at, _) = ended {
            expect(at == pauseMoment,
                  "end is backdated to when the pause began, not the timeout moment", &problems)
        } else {
            problems.append("expected .end once the pause outlived breakLength, got \(ended)")
        }

        return problems
    }

    // MARK: - 55

    static func testAutoSessionHysteresis() -> [String] {
        var problems: [String] = []
        var detector = AutoSessionDetector(breakLength: 600)
        let t0 = base
        // Both readings sit strictly between autoStopThreshold (0.35) and
        // autoStartThreshold (0.65) — the flapping zone. Alternate across far
        // more evaluations than any dwell constant so a bug that averages, or
        // that treats "not below start" as "above stop", gets every chance to
        // show up.
        let low = makeFocusScore(0.5, explanation: "drifting")
        let high = makeFocusScore(0.6, explanation: "drifting")
        var moment = t0
        for i in 0..<200 {
            let score = (i % 2 == 0) ? low : high
            let decision = detector.evaluate(score: score, at: moment,
                                             sessionRunning: false, sessionWasAutoStarted: false,
                          enginePaused: false)
            expect(decision == .none,
                  "evaluation \(i) at \(moment.timeIntervalSince(t0))s in the hysteresis band produced \(decision)",
                  &problems)
            moment = moment.addingTimeInterval(30)
        }
        // 200 * 30s = 6000s (100 minutes), comfortably past autoStartDwell (300s),
        // autoMinRunDwell (180s), and the 600s breakLength used elsewhere.
        return problems
    }

        // MARK: - RewardEngine
}
