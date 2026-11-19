import Foundation

/// Reads begin with the recording: a session that has not ticked yet reads nothing, and no count from
/// before a recording stands against its breaker. Fakes only.
extension SiteSignalWiringChecks {
    static let recordingTests: [(String, () -> [String])] = [
        ("Reads begin with the recording, and nothing from before it trips its breaker", readsBeginWithTheRecording),
    ]

    private static func readsBeginWithTheRecording() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // The session has started, but no tick has run: nothing is being recorded yet.
            guard let w = wired() else { return ["could not create isolated preferences"] }
            defer { w.close() }
            w.fake.answer = .timedOut
            w.r.activate(chrome)
            expect(w.fake.asked.isEmpty, "an activation before the first tick reads nothing, got \(w.fake.asked.count)", &problems)
            w.r.run(1)
            expect(w.fake.asked.count == 1, "the first tick asks once, got \(w.fake.asked.count)", &problems)
            w.r.run(30)
            expect(w.fake.asked.count == 2, "one timeout leaves the next edge free to ask, got \(w.fake.asked.count)", &problems)
            // Two timeouts held by the reader when recording starts are cleared by it.
            guard let v = wired() else { return problems + ["could not create isolated preferences"] }
            defer { v.close() }
            v.fake.answer = .timedOut
            for _ in 0..<2 { v.r.evidence.siteReader?.request(app: chrome, pid: SiteSignalChecks.chromePID, at: v.r.clock.value) }
            v.r.activate(chrome)
            v.r.run(1)
            expect(v.fake.asked.count == 3, "timeouts from before the recording do not stop it reading, got \(v.fake.asked.count)", &problems)
            return problems
        }
    }
}
