import Foundation
import SwiftUI

/// The motion contract: everything that settles is one critically damped
/// spring, so an interrupted change carries its speed and nothing overshoots,
/// and a day arrives from the side it lies on.
enum MotionChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every settling motion is a spring: hand-moved things overshoot once, the rest and all exits do not", settlesOnSprings),
        ("A step to the next or previous day says which way it went; a jump does not", dayStepDirection),
    ]

    private static func settlesOnSprings() -> [String] {
        var problems: [String] = []
        // Damping 1.0 never overshoots. Below about 0.55 a spring visibly
        // wobbles, which reads as a toy on a desktop control.
        let springs: [(String, Animation, Double, Double)] = [
            ("release", Tokens.Motion.release, 0.32, 0.6),
            ("hover", Tokens.Motion.hover, 0.18, 1.0),
            ("selection", Tokens.Motion.selection, 0.30, 0.78),
            ("tick", Tokens.Motion.tick, 0.25, 1.0),
            ("rise", Tokens.Motion.rise, 0.32, 0.8),
            ("swap", Tokens.Motion.swap, 0.32, 1.0),
            ("reveal", Tokens.Motion.reveal, 0.36, 0.82),
            ("dismiss", Tokens.Motion.dismiss, 0.26, 1.0),
            ("settle", Tokens.Motion.settle, 0.5, 0.72),
        ]
        for (name, animation, response, damping) in springs {
            expect(animation == Animation.spring(response: response, dampingFraction: damping),
                   "\(name) should be a spring with response \(response) and damping \(damping)", &problems)
            expect(damping >= 0.55, "\(name) is damped at \(damping), loose enough to wobble", &problems)
        }
        let response = Dictionary(uniqueKeysWithValues: springs.map { ($0.0, $0.2) })
        expect((response["dismiss"] ?? 1) < (response["reveal"] ?? 0),
               "closing should be quicker than opening", &problems)
        return problems
    }

    private static func dayStepDirection() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(SelfTest.base)
        let defaults = MemoryDefaults.suite(named: "fc-selftest-motion") ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence,
                                   archive: SessionArchive(directory: directory, now: { clock.value }),
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })

        store.selectDay(offset: 1)
        expect(store.dayStep == -1, "today to yesterday is a step back, got \(store.dayStep)", &problems)
        store.selectDay(offset: 0)
        expect(store.dayStep == 1, "yesterday to today is a step forward, got \(store.dayStep)", &problems)
        store.selectDay(offset: 3)
        expect(store.dayStep == 0, "three days at once is a jump, got \(store.dayStep)", &problems)
        store.selectDay(offset: 3)
        expect(store.dayStep == 0, "the same day again is not a step, got \(store.dayStep)", &problems)
        return problems
    }
}
