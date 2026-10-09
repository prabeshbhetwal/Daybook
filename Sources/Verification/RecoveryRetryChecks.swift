import Foundation

/// A write that fails delays what it carried; it never loses it. Each check
/// refuses a write that used to leave its data with no durable copy: usage
/// recovered from a damaged journal, and a rest the session archive refused.
enum RecoveryRetryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Usage recovered from a damaged journal survives a snapshot that could not be written",
         recoveredUsageOutlivesFailedSnapshot),
        ("An Away rest the archive refused is saved at the next Stop", refusedAwayRestIsSaved),
        ("A Watching rest the archive refused is saved at the next Stop", refusedWatchingRestIsSaved),
        ("A refused rest outlives a relaunch and is saved only once", refusedRestOutlivesRelaunch),
    ]

    private static let base = SelfTest.base

    // MARK: - Usage journal

    private static func stretch(_ offset: TimeInterval, _ app: String) -> AppUsageSession {
        AppUsageSession(id: UUID(), bundleID: "com.example.\(app.lowercased())", appName: app,
                        start: base.addingTimeInterval(offset),
                        end: base.addingTimeInterval(offset + 300), endReason: .appSwitch)
    }

    private static func appNames(in directory: URL) -> [String] {
        AppUsageArchive(directory: directory, now: { base }).sessions.map(\.appName).sorted()
    }

    /// Whether any file in the directory still holds this text.
    private static func preserved(_ text: String, in directory: URL) -> Bool {
        let bytes = Data(text.utf8)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name)))?.range(of: bytes) != nil
        }
    }

    private static func recoveredUsageOutlivesFailedSnapshot() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        let directory = SelfTest.scratchDirectory()
        let snapshot = directory.appendingPathComponent("app-usage.json")
        let journal = directory.appendingPathComponent("app-usage-journal.jsonl")
        // A snapshot holding Gamma: recorded as a journal line, then compacted
        // into the snapshot by the next launch.
        AppUsageArchive(directory: directory, now: { base }).record(stretch(1_200, "Gamma"))
        _ = AppUsageArchive(directory: directory, now: { base })
        // Real journal lines for Alpha and Beta, written by the archive itself.
        let source = SelfTest.scratchDirectory()
        let writer = AppUsageArchive(directory: source, now: { base })
        writer.record(stretch(0, "Alpha"))
        writer.record(stretch(600, "Beta"))
        let text = (try? String(contentsOf: source.appendingPathComponent("app-usage-journal.jsonl"),
                                encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        guard manager.fileExists(atPath: snapshot.path), !manager.fileExists(atPath: journal.path),
              lines.count == 2 else { return ["could not build the journal fixture"] }
        let unreadable = "not a journal line"
        try? Data((lines[0] + "\n" + unreadable + "\n" + lines[1] + "\n").utf8).write(to: journal)

        // The snapshot cannot be replaced, so the launch that recovers the
        // readable lines has nowhere new to write them.
        try? manager.setAttributes([.immutable: true], ofItemAtPath: snapshot.path)
        let damaged = AppUsageArchive(directory: directory, now: { base })
        let shown = damaged.sessions.map(\.appName).sorted()
        try? manager.setAttributes([.immutable: false], ofItemAtPath: snapshot.path)
        guard (try? Data(contentsOf: snapshot))?.range(of: Data("Alpha".utf8)) == nil else {
            return ["could not make the snapshot unwritable for the damaged launch"]
        }
        expect(shown == ["Alpha", "Beta", "Gamma"],
               "the damaged launch shows every readable record, got \(shown)", &problems)

        let relaunched = appNames(in: directory)
        expect(relaunched == ["Alpha", "Beta", "Gamma"],
               "after a relaunch expected Alpha, Beta and Gamma once each, got \(relaunched)", &problems)
        let again = appNames(in: directory)
        expect(again == ["Alpha", "Beta", "Gamma"],
               "a second relaunch expected Alpha, Beta and Gamma once each, got \(again)", &problems)
        expect(preserved(unreadable, in: directory), "the unreadable journal line was not kept", &problems)
        return problems
    }

    // MARK: - Rests

    /// Files and preferences that outlive one engine, as they outlive a launch.
    /// While `refusing` is set, the archive refuses any write that holds a
    /// rest, as a full disk refuses the write that would add one.
    private final class Rig {
        var now = base
        var refusing = false
        let directory = SelfTest.scratchDirectory()
        let suite: String
        let defaults: UserDefaults

        init?() {
            let suite = "fc-selftest-rest-retry-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
            self.suite = suite
            self.defaults = defaults
        }

        func launch() -> SessionEngine {
            let prefs = PersistenceStore(defaults: defaults)
            prefs.breakThreshold = 5 * 60
            let archive = SessionArchive(directory: directory, now: { self.now }, writeOverride: { candidate in
                self.refusing && candidate.contains { $0.workType == .breakTime } ? "The disk is full." : nil
            })
            return SessionEngine(store: prefs, archive: archive, ownBundleID: "fc.rest.retry",
                                 schedulesDwell: false, now: { self.now })
        }

        func close() {
            MemoryDefaults.remove(named: suite)
        }
    }

    private static func rests(_ engine: SessionEngine) -> [SessionRecord] {
        engine.archive.records.filter { $0.workType == .breakTime }
    }

    /// Works five minutes, steps away for forty and comes back while the
    /// archive refuses the Away rest.
    private static func awayRefused(_ rig: Rig) -> SessionEngine {
        let engine = rig.launch()
        engine.start(workType: .deepWork, intent: "Report")
        rig.now += 300
        engine.transition(on: .markedAway)
        rig.now += 2_400
        rig.refusing = true
        engine.transition(on: .manualResume)
        rig.refusing = false
        return engine
    }

    private static func refusedAwayRestIsSaved() -> [String] {
        guard let rig = Rig() else { return ["no isolated preferences"] }
        defer { rig.close() }
        var problems: [String] = []
        let engine = awayRefused(rig)
        guard rests(engine).isEmpty, engine.archive.records.count == 1 else {
            return ["the fixture should save the stretch and refuse the rest, got \(engine.archive.records.map(\.name))"]
        }
        expect(engine.awayDecisionError == nil,
               "a refused rest left awayDecisionError set: \(engine.awayDecisionError ?? "")", &problems)
        rig.now += 600
        let stopped = engine.stop()
        let saved = rests(engine)
        expect(stopped, "Stop failed after the refused rest", &problems)
        expect(saved.map(\.name) == ["Away"], "Stop saves the refused rest once, got \(saved.map(\.name))", &problems)
        expect(saved.first?.start == base.addingTimeInterval(300) && saved.first?.end == base.addingTimeInterval(2_700),
               "the rest covers the absence, got \(String(describing: saved.first.map { [$0.start, $0.end] }))",
               &problems)
        return problems
    }

    private static func refusedWatchingRestIsSaved() -> [String] {
        guard let rig = Rig() else { return ["no isolated preferences"] }
        defer { rig.close() }
        var problems: [String] = []
        let engine = rig.launch()
        engine.start(workType: .deepWork, intent: "Film night")
        rig.now += 30 * 60
        engine.transition(on: .watchingObserved(seconds: 600))
        rig.now += 35 * 60
        rig.refusing = true
        engine.transition(on: .idleObserved(seconds: 2))
        rig.refusing = false
        guard engine.state == .running, rests(engine).isEmpty else {
            return ["the fixture should end the watching and refuse its rest, got \(engine.state), \(rests(engine).map(\.name))"]
        }
        rig.now += 600
        let stopped = engine.stop()
        let saved = rests(engine)
        expect(stopped, "Stop failed after the refused rest", &problems)
        expect(saved.map(\.name) == ["Watching"], "Stop saves the refused rest once, got \(saved.map(\.name))", &problems)
        expect(saved.first?.start == base.addingTimeInterval(1_200) && saved.first?.end == base.addingTimeInterval(3_900),
               "the rest covers the watching, got \(String(describing: saved.first.map { [$0.start, $0.end] }))",
               &problems)
        return problems
    }

    private static func refusedRestOutlivesRelaunch() -> [String] {
        guard let rig = Rig() else { return ["no isolated preferences"] }
        defer { rig.close() }
        var problems: [String] = []
        _ = awayRefused(rig)
        // The app quits here, the rest still unsaved, and relaunches from
        // the state it left in its preferences.
        guard let quit = PersistenceStore(defaults: rig.defaults).loadState() else {
            return ["the live state was not saved"]
        }
        let relaunched = rig.launch()
        relaunched.restore(from: quit)
        rig.now += 600
        let stopped = relaunched.stop()
        expect(stopped, "Stop failed after the relaunch", &problems)
        expect(rests(relaunched).map(\.name) == ["Away"],
               "the relaunched Stop saves the refused rest once, got \(rests(relaunched).map(\.name))", &problems)

        // Launched again from that same older state, the rest is already
        // saved under its id and the next Stop does not add it again.
        let stale = rig.launch()
        stale.restore(from: quit)
        stale.start(workType: .deepWork, intent: "Next")
        rig.now += 600
        _ = stale.stop()
        expect(rests(stale).map(\.name) == ["Away"],
               "a relaunch from an older state saved the rest again: \(rests(stale).map(\.name))", &problems)
        return problems
    }
}
