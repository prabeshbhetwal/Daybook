import Foundation

/// The Core defects of the 2026-11-13 production audit (C1 to C3): a session
/// must end, and keep the work it did, whatever state its folder or the
/// clock is in.
enum EndingSafetyChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A correction history this build cannot read never stops a session from ending",
         unreadableHistoryStillEnds),
        ("With 'Ask me after: Never' a night away still ends the session at the long-away cap",
         neverAskStillEndsAtCap),
    ]

    /// An engine whose preferences and folder survive a relaunch.
    private final class Machine {
        let clock = TestClock(SelfTest.base)
        let suite = "fc-selftest-ending-\(UUID().uuidString)"
        let directory = SelfTest.scratchDirectory()
        lazy var defaults = MemoryDefaults.suite(named: suite)!
        var engine: SessionEngine!

        init(history: String? = nil) {
            if let history {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? history.write(to: historyURL, atomically: true, encoding: .utf8)
            }
            engine = make()
        }

        var historyURL: URL { directory.appendingPathComponent("correction-history.json") }

        func make() -> SessionEngine {
            let clock = self.clock
            return SessionEngine(store: PersistenceStore(defaults: defaults),
                                 archive: SessionArchive(directory: directory, now: { clock.value }),
                                 ownBundleID: "fc.ending.fixture", schedulesDwell: false,
                                 now: { clock.value })
        }

        func relaunch() {
            engine = make()
            if let saved = engine.launchSnapshot() { engine.restore(from: saved) }
        }

        func files() -> [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        }

        func close() { MemoryDefaults.remove(named: suite) }
    }

    private static func unreadableHistoryStillEnds() -> [String] {
        var problems: [String] = []
        for (label, contents) in [("unreadable", "{"), ("newer", "{\"version\":2}")] {
            let machine = Machine(history: contents); defer { machine.close() }
            machine.engine.start(workType: .deepWork, intent: "Writing")
            machine.clock.advance(3_600)
            expect(machine.engine.stop(), "\(label): Stop should end the session", &problems)
            expect(machine.engine.state == .idle, "\(label): idle after Stop, got \(machine.engine.state)", &problems)
            expect(machine.engine.archive.records.count == 1,
                   "\(label): one record after Stop, got \(machine.engine.archive.records.count)", &problems)
            // And again after a relaunch on the same folder.
            machine.relaunch()
            machine.engine.start(workType: .deepWork, intent: "Reading")
            machine.clock.advance(3_600)
            expect(machine.engine.stop(), "\(label): Stop after a relaunch should end the session", &problems)
            expect(machine.engine.archive.records.count == 2,
                   "\(label): two records after the relaunch, got \(machine.engine.archive.records.count)", &problems)
            let kept = (try? String(contentsOf: machine.historyURL, encoding: .utf8)) ?? ""
            let asides = machine.files().filter { $0.hasPrefix("correction-history-corrupt-") }
            if label == "newer" {
                expect(kept == contents, "a newer build's history is left as it was, got \(kept.prefix(40))", &problems)
                expect(asides.isEmpty, "a newer build's history is not set aside, got \(asides)", &problems)
            } else {
                expect(asides.count == 1, "an unreadable history is set aside once, got \(asides)", &problems)
            }
        }
        return problems
    }

    private static func neverAskStillEndsAtCap() -> [String] {
        var problems: [String] = []
        let machine = Machine(); defer { machine.close() }
        let engine = machine.engine!
        engine.breakThreshold = FocusConstants.never
        engine.start(workType: .deepWork, intent: "Writing")
        machine.clock.advance(3_600)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        machine.clock.advance(10 * 3_600)
        engine.transition(on: .awayEnded)
        expect(engine.state == .idle, "a 10 h absence past the cap ends the session, got \(engine.state)", &problems)
        let records = engine.archive.records
        expect(records.count == 1, "one record for the hour before the absence, got \(records.count)", &problems)
        if let record = records.first {
            SelfTest.expectClose(record.workSeconds, 3_600, "the record's work", &problems)
            SelfTest.expectClose(record.end.timeIntervalSince(record.start), 3_600,
                                 "the record ends where the absence began", &problems)
        }
        return problems
    }
}
