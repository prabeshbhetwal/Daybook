import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 10

    static func testExhaustiveTransitions() -> [String] {
        var problems: [String] = []

        let setups: [(String, (SessionEngine, TestClock) -> Void)] = [
            ("idle", { _, _ in }),
            ("running", { engine, _ in engine.transition(on: .launch) }),
            ("paused", { engine, _ in
                engine.transition(on: .launch)
                engine.transition(on: .manualPause)
            }),
            ("awaiting", { engine, clock in
                engine.transition(on: .launch)
                engine.transition(on: .awayBegan(trigger: .screenLock))
                clock.advance(1_320)
                engine.transition(on: .awayEnded)
            })
        ]

        let events: [SessionEvent] = [
            .launch,
            .awayBegan(trigger: .screenLock),
            .awayBegan(trigger: .systemSleep),
            .awayEnded,
            .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"),
            .appActivated(bundleID: "com.spotify.client", name: "Spotify"),
            .appActivated(bundleID: nil, name: ""),
            .dwellExpired(bundleID: "com.spotify.client"),
            .dwellExpired(bundleID: "com.unknown.app"),
            .manualPause,
            .manualResume,
            .markedAway,
            .idleObserved(seconds: 0),
            .idleObserved(seconds: FocusConstants.idlePauseThreshold + 1),
            .decision(.continueSession),
            .decision(.mergeTime),
            .decision(.tookBreak),
            .decision(.resetTimer),
            .resetSession,
            .overrideApplied(bundleID: "com.apple.Terminal")
        ]

        for (label, setup) in setups {
            for event in events {
                let clock = TestClock(base)
                let engine = makeEngine(clock)
                setup(engine, clock)
                let before = engine.state
                clock.advance(10)
                engine.transition(on: event)
                clock.advance(10)

                if engine.elapsed < 0 {
                    problems.append("\(label) + \(event): negative elapsed")
                }
                if engine.totalPausedDuration < 0 {
                    problems.append("\(label) + \(event): negative totalPaused")
                }
                if before == .idle, engine.state != .idle {
                    // Only launch, a work activation, or an explicit reset may
                    // start a session from idle.
                    let allowed: Bool
                    switch event {
                    case .launch, .resetSession:
                        allowed = true
                    case .appActivated(let bundleID, _):
                        allowed = engine.categories.category(for: bundleID) == .work
                    default:
                        allowed = false
                    }
                    if !allowed {
                        problems.append("\(label) + \(event): unexpected exit from idle")
                    }
                }
            }
        }
        return problems
    }
}
