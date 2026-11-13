import Foundation

/// App-layer fixes from the production audit of 13 November 2026: what keeps
/// the ticker, what a quit saves, what the shortcut and the detector report,
/// what the power queue keeps, and how Ask and the name suggester end.
enum AppAuditChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An idle or watching pause keeps the ticker with recording off, until the cap ends it",
         unattendedPauseKeepsTicker),
    ]

    private static func unattendedPauseKeepsTicker() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // No tracker: app-use recording is off, so only the session can keep the ticker.
            guard let f = BreakStoreChecks.make(ticker: true, prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            let threshold = f.persistence.idlePauseThreshold, cap = f.persistence.longAwayCap
            f.engine.transition(on: .idleObserved(seconds: threshold))
            f.store.refresh()
            expect(f.engine.state == .paused(reason: .idle), "quiet pauses the session, got \(f.engine.state)", &problems)
            expect(f.store.hasScheduledTicker, "an idle pause keeps the ticker that resumes it", &problems)
            f.engine.transition(on: .idleObserved(seconds: 1))
            f.store.refresh()
            expect(f.engine.state.isRunning, "input resumes the idle pause, got \(f.engine.state)", &problems)

            // Nobody comes back: past the cap the session ends, and nothing is left to tick for.
            f.engine.transition(on: .idleObserved(seconds: threshold))
            f.clock.advance(cap)
            f.engine.transition(on: .idleObserved(seconds: threshold + cap))
            f.store.refresh()
            expect(f.engine.state == .idle, "the cap ends an abandoned idle pause, got \(f.engine.state)", &problems)
            expect(!f.store.hasScheduledTicker, "the ticker stops once the session has ended", &problems)

            guard let g = BreakStoreChecks.make(ticker: true, prepare: BreakStoreChecks.running) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { g.close() }
            g.engine.transition(on: .watchingObserved(seconds: threshold))
            g.store.refresh()
            expect(g.engine.state == .paused(reason: .watching), "a film pauses the session, got \(g.engine.state)", &problems)
            expect(g.store.hasScheduledTicker, "a watching pause keeps the ticker that ends it", &problems)
            return problems
        }
    }
}
