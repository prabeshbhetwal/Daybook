import Foundation

/// Recovery preserves a session's original app and refuses a journal append
/// whose preceding bytes cannot be inspected and repaired.
enum RecoveryAuditChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A relaunch and Stop preserve the app captured when the session began", restoredOriginalApp),
        ("A refused automatic switch and later Stop preserve the original app", refusedSwitchKeepsOriginalApp),
        ("An unreadable journal refuses an append unchanged and repairs on retry", journalRepairRefusesUnreadableTail),
    ]

    private static let originalApp = "com.example.coding"
    private static let laterApp = "com.example.research"

    private final class Fixture {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let directory = SelfTest.scratchDirectory()
        let suite: String
        let persistence: PersistenceStore
        var refusingArchive = false

        init?() {
            let suite = "fc-selftest-recovery-audit-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
            self.suite = suite
            persistence = PersistenceStore(defaults: defaults)
            persistence.autoSessionsEnabled = false
            persistence.activityRuleAutomationEnabled = false
        }

        func launch() -> SessionEngine {
            let archive = SessionArchive(directory: directory, now: { self.clock.value },
                writeOverride: { _ in self.refusingArchive ? "The archive is unavailable." : nil })
            return SessionEngine(store: persistence, archive: archive,
                ownBundleID: "com.example.recovery-check", schedulesDwell: false,
                now: { self.clock.value })
        }

        func close() { MemoryDefaults.remove(named: suite) }
    }

    private static func restoredOriginalApp() -> [String] {
        guard let fixture = Fixture() else { return ["could not create isolated preferences"] }
        defer { fixture.close() }
        let engine = fixture.launch()
        engine.transition(on: .appActivated(bundleID: originalApp, name: "Coding"))
        guard engine.start(workType: .deepWork, intent: "Coding") else {
            return ["could not start the original session"]
        }
        fixture.clock.advance(600)
        engine.transition(on: .appActivated(bundleID: laterApp, name: "Research"))
        engine.transition(on: .manualPause)
        guard let saved = fixture.persistence.loadState(), saved.lastAppBundleID == laterApp else {
            return ["the saved fixture must distinguish the original app from the latest app"]
        }
        let restored = fixture.launch()
        restored.restore(from: saved)
        guard restored.stop() else { return ["the restored session could not be stopped"] }
        let records = restored.archive.records
        var problems: [String] = []
        expect(records.count == 1, "expected one restored record, got \(records.count)", &problems)
        expect(records.first?.detectedApp == originalApp,
               "expected original app \(originalApp), got \(records.first?.detectedApp ?? "nil")", &problems)
        return problems
    }

    private static func refusedSwitchKeepsOriginalApp() -> [String] {
        guard let fixture = Fixture() else { return ["could not create isolated preferences"] }
        defer { fixture.close() }
        let engine = fixture.launch()
        let started = fixture.clock.value
        engine.transition(on: .appActivated(bundleID: originalApp, name: "Coding"))
        fixture.clock.advance(600)
        let first = ActivityAutomaticAction(ruleID: UUID(), ruleName: "Coding", workType: .deepWork,
            evidence: DateInterval(start: started, end: fixture.clock.value),
            reason: "Coding foreground evidence", ruleVersion: 1, generation: 1, expectedRecordID: nil)
        guard engine.startAutomatically(action: first),
              let recordID = fixture.persistence.loadState()?.activeRecordID else {
            return ["could not start an automatic session with a durable record identity"]
        }
        let boundary = fixture.clock.value
        engine.transition(on: .appActivated(bundleID: laterApp, name: "Research"))
        fixture.clock.advance(300)
        let second = ActivityAutomaticAction(ruleID: UUID(), ruleName: "Research", workType: .deepWork,
            evidence: DateInterval(start: boundary, end: fixture.clock.value),
            reason: "Research foreground evidence", ruleVersion: 1, generation: 2, expectedRecordID: recordID)
        fixture.refusingArchive = true
        let switched = engine.switchAutomatically(action: second, expectedRecordID: recordID)
        fixture.refusingArchive = false
        guard !switched, engine.archive.records.isEmpty else {
            return ["the unavailable archive must refuse the switch without saving a partial record"]
        }
        guard engine.stop() else { return ["Stop could not save the original session after recovery"] }
        let records = engine.archive.records
        var problems: [String] = []
        expect(records.count == 1 && records.first?.id == recordID && records.first?.name == "Coding",
               "expected only the original Coding record after Stop, got \(records.map(\.name))", &problems)
        expect(records.first?.detectedApp == originalApp,
               "expected original app \(originalApp), got \(records.first?.detectedApp ?? "nil")", &problems)
        return problems
    }

    private struct Change: Decodable { let value: Int }

    private static func journalRepairRefusesUnreadableTail() -> [String] {
        let manager = FileManager.default
        let directory = SelfTest.scratchDirectory()
        let url = directory.appendingPathComponent("recovery-journal.jsonl")
        let original = Data("{\"value\":1}\n{\"value\":".utf8)
        let change = Data("{\"value\":2}".utf8)
        let journal = JournalFile(url: url)
        defer { try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try original.write(to: url)
            try manager.setAttributes([.posixPermissions: 0o200], ofItemAtPath: url.path)
            guard (try? Data(contentsOf: url)) == nil else {
                return ["the write-only journal fixture did not deny reads; repair refusal was not exercised"]
            }
            let writer = try FileHandle(forWritingTo: url)
            try writer.close()
            var refused = false
            do { try journal.append(change) } catch { refused = true }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            var problems: [String] = []
            expect(refused, "append must report failure when its existing tail cannot be read", &problems)
            let afterRefusal = try Data(contentsOf: url)
            expect(afterRefusal == original, "the refused append changed the journal's existing bytes", &problems)
            try journal.append(change)
            guard let contents = journal.read() else { return problems + ["the repaired journal could not be read"] }
            let replay = journal.replay(Change.self, from: contents)
            expect(replay.changes.map(\.value) == [1, 2],
                   "retry must replay each durable change once, got \(replay.changes.map(\.value))", &problems)
            expect(!contents.lastWriteCut && replay.unreadableLine == nil && !replay.skippedTornLine,
                   "retry left a torn or unreadable line in the journal", &problems)
            return problems
        } catch {
            return ["could not exercise journal repair refusal and retry: \(error.localizedDescription)"]
        }
    }
}
