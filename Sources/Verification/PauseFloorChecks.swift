import Foundation

/// A back-dated pause starts no earlier than the session did or than its last
/// pause ended. The last keypress can be older than both, and a pause dated to
/// it took minutes off that were already off, or that were never in.
enum PauseFloorChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Watching that stops and starts again in one quiet stretch takes nothing off twice",
         watchingRestartKeepsWork),
        ("An idle pause never reaches back before the session began", idleStaysInsideSession),
    ]

    private static func watchingRestartKeepsWork() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Film")
        clock.advance(30 * 60)                                  // 20m of work, then 10m quiet
        engine.transition(on: .watchingObserved(seconds: 10 * 60))
        clock.advance(5 * 60)                                   // the film stops for a moment
        engine.transition(on: .idleObserved(seconds: 1))
        clock.advance(5)                                        // and goes on
        engine.transition(on: .watchingObserved(seconds: 15 * 60 + 5))
        expect(engine.state == .paused(reason: .watching),
               "the film pauses the session again, got \(engine.state)", &problems)
        clock.advance(10 * 60)
        engine.transition(on: .idleObserved(seconds: 1))        // a keypress
        expect(engine.state == .running, "input resumes the session, got \(engine.state)", &problems)
        SelfTest.expectClose(engine.elapsed, 20 * 60, "the 20 minutes before the film are kept", &problems)
        return problems
    }

    private static func idleStaysInsideSession() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Late start")  // after a quiet half hour
        clock.advance(60)
        engine.transition(on: .idleObserved(seconds: 31 * 60))
        clock.advance(60)
        engine.transition(on: .idleObserved(seconds: 1))
        if case .awaitingUserDecision(let away, _) = engine.state {
            problems.append("a two-minute session is never asked about \(Int(away / 60))m away")
        }
        expect(engine.state == .running, "the session carries on, got \(engine.state)", &problems)
        SelfTest.expectClose(engine.elapsed, 0, "the untouched two minutes are not work", &problems)
        return problems
    }
}
