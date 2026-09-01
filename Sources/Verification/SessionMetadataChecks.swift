import Foundation
import SwiftUI
import AppKit
import IOKit.ps

/// Focused contracts for local record-scoped notes and observed power context.
/// Every fixture owns a complete isolated data directory; no check reads or
/// writes the live Application Support folder or samples the current Mac.
enum SessionMetadataChecks {
    static let tests: [(String, () -> [String])] = [
        ("Session metadata: note persists by exact stretch identity", notePersistsByRecordID),
        ("Session metadata: failed atomic note write preserves durable evidence", failedWriteIsNonMutating),
        ("Session metadata: complete data-directory copy and removal includes sidecar", directoryPortability),
        ("Session metadata: legacy record and active stretch identities are stable", stableStretchIdentity),
        ("Session metadata: legacy pending snapshots reuse their predecessor identity", pendingIdentityMigration),
        ("Session metadata: note drafts survive failed saves and guarded dismissal", draftFailureAndDismissal),
        ("Session metadata: short End removes orphan metadata while archived notes survive Undo", retentionAndCorrectionCoexistence),
        ("Session metadata: injected power monitor records boundaries and events only", injectedPowerMonitor),
        ("Session metadata: grouped notes and power retain exact stretch scope", groupedMetadataConsumers),
        ("Session metadata: Command-Return targets only the focused note editor", focusedEditorCommand),
        ("Session metadata: legacy identity ignores rename and open drafts retain evidence", identityAndDraftRetentionHardening),
        ("Session metadata: grouped power qualifies partial coverage without losing source", groupedPowerCoverageHardening),
        ("Session metadata: duplicate entries and equal-time observations load deterministically", duplicateMetadataHardening),
        ("Session metadata: public IOPS descriptions parse without live sampling", powerDescriptionParser),
        ("Session metadata: literal battery and charging sequences stay factual", powerSummaries),
        ("Session metadata: mixed, partial and invalid power evidence stays qualified", partialPowerEvidence),
        ("Session metadata: old sessions never acquire current power", oldSessionHasNoPowerFallback)
    ]

    private static func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-session-metadata-\(UUID().uuidString)", isDirectory: true)
    }

    private static func expect(_ condition: @autoclosure () -> Bool,
                               _ message: String, _ problems: inout [String]) {
        if !condition() { problems.append(message) }
    }

    private static func notePersistsByRecordID() -> [String] {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = UUID(), continued = UUID()
        let archive = SessionMetadataArchive(directory: folder)
        var problems: [String] = []
        expect(archive.saveNote("Found the race at the archive boundary.", for: first) == .saved,
               "saving a note returned failure", &problems)
        expect(archive.saveNote("Second stretch", for: continued) == .saved,
               "saving a continued stretch note returned failure", &problems)
        let reloaded = SessionMetadataArchive(directory: folder)
        expect(reloaded.metadata(for: first)?.note == "Found the race at the archive boundary.",
               "first stretch note did not survive reload", &problems)
        expect(reloaded.metadata(for: continued)?.note == "Second stretch",
               "continued stretch did not keep its own note", &problems)
        expect(reloaded.allMetadata.count == 2,
               "continuation duplicated or merged record-scoped metadata", &problems)
        return problems
    }

    private static func failedWriteIsNonMutating() -> [String] {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let recordID = UUID()
        let good = SessionMetadataArchive(directory: folder)
        guard good.saveNote("Durable draft", for: recordID) == .saved else {
            return ["could not seed durable metadata"]
        }
        let blocked = SessionMetadataArchive(directory: folder,
            writeOverride: { _ in "The metadata folder is unavailable." })
        let result = blocked.saveNote("Unsaved revision", for: recordID)
        let reloaded = SessionMetadataArchive(directory: folder)
        var problems: [String] = []
        expect(result == .failed("The metadata folder is unavailable."),
               "failed write did not expose its exact storage error", &problems)
        expect(blocked.metadata(for: recordID)?.note == "Durable draft",
               "failed write changed the published in-memory note", &problems)
        expect(reloaded.metadata(for: recordID)?.note == "Durable draft",
               "failed write replaced the durable note", &problems)
        return problems
    }

    private static func directoryPortability() -> [String] {
        let source = directory(), copy = directory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: copy)
        }
        let recordID = UUID()
        let archive = SessionMetadataArchive(directory: source)
        guard archive.saveNote("Travels with the data folder", for: recordID) == .saved else {
            return ["could not seed portable metadata"]
        }
        do {
            try FileManager.default.copyItem(at: source, to: copy)
        } catch {
            return ["could not copy isolated data directory: \(error.localizedDescription)"]
        }
        var problems: [String] = []
        expect(SessionMetadataArchive(directory: copy).metadata(for: recordID)?.note
               == "Travels with the data folder",
               "copying the complete data directory omitted metadata", &problems)
        try? FileManager.default.removeItem(at: source)
        expect(!FileManager.default.fileExists(atPath:
            source.appendingPathComponent("session-metadata.json").path),
               "removing the complete data directory left metadata behind", &problems)
        return problems
    }

    private static func engine(at date: Date, directory: URL, suite: String) -> SessionEngine? {
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        return SessionEngine(store: PersistenceStore(defaults: defaults),
            archive: SessionArchive(directory: directory, now: { date }),
            ownBundleID: "com.example.metadata", schedulesDwell: false, now: { date })
    }

    private static func stableStretchIdentity() -> [String] {
        let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.identity.\(UUID())"
        defer {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        let date = Date(timeIntervalSince1970: 1_788_550_000)
        let recordID = UUID()
        let legacy: [String: Any] = [
            "id": recordID.uuidString,
            "name": "Legacy",
            "workType": WorkType.deepWork.rawValue,
            "start": date.timeIntervalSinceReferenceDate,
            "end": date.addingTimeInterval(600).timeIntervalSinceReferenceDate,
            "workSeconds": 600,
            "isAuto": false
        ]
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .deferredToDate
        decoder.dateDecodingStrategy = .deferredToDate
        var problems: [String] = []
        if let data = try? JSONSerialization.data(withJSONObject: legacy),
           let first = try? decoder.decode(SessionRecord.self, from: data),
           let second = try? decoder.decode(SessionRecord.self, from: data) {
            expect(first.threadID == recordID && second.threadID == recordID,
                   "legacy SessionRecord thread fallback changed between loads", &problems)
        } else { problems.append("could not decode legacy SessionRecord fixture") }

        guard let subject = engine(at: date, directory: folder, suite: suite) else {
            problems.append("could not create isolated engine"); return problems
        }
        subject.start(workType: .deepWork, intent: "Stable")
        let activeID = subject.activeRecordID
        subject.transition(on: .manualPause)
        subject.transition(on: .manualResume)
        subject.backdate(to: date.addingTimeInterval(-60))
        expect(subject.activeRecordID == activeID,
               "pause, resume or backdate rotated the active stretch identity", &problems)
        // The injected clock is fixed; backdating makes this a recordable minute.
        expect(subject.stop(), "ordinary Stop failed", &problems)
        expect(subject.archive.records.last?.id == activeID,
               "ordinary Stop archived under a different record identity", &problems)
        return problems
    }

    private static func pendingIdentityMigration() -> [String] {
        let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.pending.\(UUID())"
        defer {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        let date = Date(timeIntervalSince1970: 1_788_580_000)
        guard let source = engine(at: date, directory: folder, suite: suite) else {
            return ["could not create pending migration source"]
        }
        source.start(workType: .deepWork, intent: "Pending")
        var snapshot = source.snapshot()
        snapshot.kind = .awaiting
        snapshot.pendingAway = 1_200
        snapshot.pendingDecisionID = UUID()
        snapshot.activeRecordID = nil // legacy schema
        guard let pendingID = snapshot.pendingDecisionID else {
            return ["pending migration fixture lost its decision identity"]
        }
        let restored = engine(at: date, directory: folder, suite: suite + ".reload")!
        restored.restore(from: snapshot)
        let expected = AwayDecisionReceipt.precedingRecordID(for: pendingID)
        return restored.activeRecordID == expected ? []
            : ["legacy pending snapshot did not reuse its reserved predecessor identity"]
    }

    private static func draftFailureAndDismissal() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.draft.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let date = Date(timeIntervalSince1970: 1_788_590_000)
            guard let subject = engine(at: date, directory: folder, suite: suite) else {
                return ["could not create draft fixture"]
            }
            let metadata = SessionMetadataArchive(directory: folder,
                writeOverride: { _ in "The note could not be saved." })
            let store = SessionStore(engine: subject, schedulesTicker: false,
                                     metadataArchive: metadata, now: { date })
            let first = UUID(), second = UUID()
            store.beginNoteEditing(for: first)
            store.setNoteDraft("Unsaved first note", for: first)
            store.beginNoteEditing(for: second)
            store.setNoteDraft("Independent second note", for: second)
            var problems: [String] = []
            expect(!store.saveNote(for: first), "failed atomic note save reported success", &problems)
            expect(store.noteDraft(for: first) == "Unsaved first note",
                   "failed save discarded the first draft", &problems)
            expect(store.noteDraft(for: second) == "Independent second note",
                   "one editor overwrote another expanded entry draft", &problems)
            expect(store.noteError(for: first) == "The note could not be saved.",
                   "failed save did not expose its storage error", &problems)
            expect(!store.cancelNoteEditing(for: first),
                   "unguarded dismissal discarded unsaved text", &problems)
            expect(store.cancelNoteEditing(for: first, discardingChanges: true),
                   "confirmed draft dismissal remained blocked", &problems)
            return problems
        }
    }

    private final class Clock {
        var value: Date
        init(_ value: Date) { self.value = value }
        func advance(_ seconds: TimeInterval) { value.addTimeInterval(seconds) }
    }

    private static func retentionAndCorrectionCoexistence() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.retention.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let clock = Clock(Date(timeIntervalSince1970: 1_788_595_000))
            let archive = SessionArchive(directory: folder, now: { clock.value })
            let subject = SessionEngine(store: PersistenceStore(
                defaults: UserDefaults(suiteName: suite)!), archive: archive,
                ownBundleID: "com.example.metadata", schedulesDwell: false,
                now: { clock.value })
            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: subject, schedulesTicker: false,
                                     metadataArchive: metadata, now: { clock.value })
            var problems: [String] = []

            subject.start(workType: .deepWork, intent: "Misclick")
            let shortID = subject.activeRecordID
            expect(metadata.saveNote("Temporary", for: shortID) == .saved,
                   "could not seed active metadata", &problems)
            store.stop()
            expect(subject.state == .idle, "short End failed", &problems)
            store.refreshSessionMetadataRetention()
            expect(metadata.metadata(for: shortID) == nil,
                   "record-free short End left orphan metadata", &problems)

            subject.start(workType: .deepWork, intent: "Retained")
            let retainedID = subject.activeRecordID
            clock.advance(600)
            expect(metadata.saveNote("Keep through Undo", for: retainedID) == .saved,
                   "could not seed retained note", &problems)
            store.stop()
            expect(subject.state == .idle, "recorded End failed", &problems)
            guard let record = archive.records.first(where: { $0.id == retainedID }) else {
                problems.append("recorded End used the wrong identity"); return problems
            }
            let row = DaySession(id: record.id, threadID: record.threadID, name: record.name,
                workType: record.workType, start: record.start, end: record.end,
                worked: record.workSeconds, stretches: 1,
                spans: [DateInterval(start: record.start, end: record.end)], isRunning: false)
            expect(store.setWorkType(.admin, for: row), "classification edit failed", &problems)
            expect(store.undoLastCorrection(), "classification Undo failed", &problems)
            expect(SessionMetadataArchive(directory: folder).metadata(for: retainedID)?.note
                   == "Keep through Undo",
                   "classification edit or Undo erased independent note metadata", &problems)
            return problems
        }
    }

    private final class FakePowerMonitor: PowerSourceMonitoring {
        var sample: PowerObservation
        var starts = 0
        var stops = 0
        var handler: ((PowerObservation) -> Void)?
        init(sample: PowerObservation) { self.sample = sample }
        func observation(at timestamp: Date,
                         boundary: PowerCoverageBoundary?) -> PowerObservation {
            PowerObservation(timestamp: timestamp, source: sample.source,
                percentage: sample.percentage, charging: sample.charging, boundary: boundary)
        }
        func start(_ handler: @escaping (PowerObservation) -> Void) {
            starts += 1; self.handler = handler
        }
        func stop() { stops += 1 }
    }

    private static func injectedPowerMonitor() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.power.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let clock = Clock(Date(timeIntervalSince1970: 1_788_598_000))
            let archive = SessionArchive(directory: folder, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: archive, ownBundleID: "com.example.metadata", schedulesDwell: false,
                now: { clock.value })
            let metadata = SessionMetadataArchive(directory: folder)
            let monitor = FakePowerMonitor(sample: PowerObservation(timestamp: clock.value,
                source: .battery, percentage: 78, charging: .notCharging))
            var store: SessionStore? = SessionStore(engine: engine, schedulesTicker: false,
                metadataArchive: metadata, powerMonitor: monitor, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Observed")
            store?.refresh()
            let recordID = engine.activeRecordID
            clock.advance(600)
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .battery,
                percentage: 64, charging: .notCharging, boundary: .sourceChanged))
            var problems: [String] = []
            expect(monitor.starts == 1, "injected monitor was not started exactly once", &problems)
            expect(metadata.metadata(for: recordID)?.power.map(\.percentage) == [78, 64],
                   "boundary and notification samples did not attach to the active stretch", &problems)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(1_200)
            engine.transition(on: .awayEnded)
            _ = engine.decide(.continueSession)
            store?.refresh()
            let successorID = engine.activeRecordID
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .external,
                percentage: 63, charging: .notCharging, boundary: .sourceChanged))
            expect(successorID != recordID,
                   "Away split did not rotate the stretch identity", &problems)
            expect(metadata.metadata(for: recordID)?.power.last?.boundary == .stretchEnded,
                   "Away split did not close power evidence against its archived predecessor", &problems)
            expect(metadata.metadata(for: successorID)?.power.first?.boundary == .stretchStarted,
                   "Away split did not start power evidence against its successor", &problems)
            expect(metadata.metadata(for: successorID)?.power.last?.percentage == 63,
                   "post-split notification attached to a stale predecessor identity", &problems)
            let fixtureStore = SessionStore(engine: engine, schedulesTicker: false,
                                            metadataArchive: metadata, now: { clock.value })
            expect(fixtureStore.powerMonitor == nil,
                   "a fixture-style store constructed a live power monitor", &problems)
            store = nil
            expect(monitor.stops == 1,
                   "store teardown did not stop the injected monitor exactly once", &problems)
            return problems
        }
    }

    private static func groupedMetadataConsumers() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.grouped.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let start = Date(timeIntervalSince1970: 1_788_599_000)
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: SessionArchive(directory: folder, now: { start }), schedulesDwell: false,
                now: { start })
            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: engine, schedulesTicker: false,
                                     metadataArchive: metadata, now: { start })
            let first = UUID(), latest = UUID()
            _ = metadata.saveNote("Earlier stretch note", for: first)
            _ = metadata.saveNote("Latest stretch note", for: latest)
            _ = metadata.appendPower(PowerObservation(timestamp: start, source: .battery,
                percentage: 78, charging: .notCharging, boundary: .stretchStarted), for: first)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(300),
                source: .battery, percentage: 72, charging: .notCharging,
                boundary: .stretchEnded), for: first)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(600),
                source: .external, percentage: 70, charging: .charging,
                boundary: .stretchStarted), for: latest)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(900),
                source: .external, percentage: 81, charging: .charging,
                boundary: .stretchEnded), for: latest)
            let summary = store.powerSummary(for: [first, latest],
                interval: DateInterval(start: start, duration: 900))
            var problems: [String] = []
            expect(store.sessionMetadata(for: first)?.note == "Earlier stretch note"
                   && store.sessionMetadata(for: latest)?.note == "Latest stretch note",
                   "grouped entry did not expose each exact record-scoped note", &problems)
            store.beginNoteEditing(for: first)
            expect(store.expandedNoteEditorIDs.contains(first)
                   && !store.expandedNoteEditorIDs.contains(latest),
                   "editing an earlier note targeted only the latest record", &problems)
            expect(summary?.headline == "Power changed"
                   && summary?.symbolName == "arrow.triangle.2.circlepath"
                   && summary?.detail?.contains("gaps between stretches are not power coverage") == true,
                   "grouped power implied one continuous span", &problems)
            expect(PowerContextSummary.make(observations: [PowerObservation(timestamp: start,
                source: .battery, percentage: 78, charging: .notCharging)],
                interval: DateInterval(start: start, duration: 1))?.symbolName == "battery.75percent",
                   "battery evidence used the wrong secondary symbol", &problems)
            expect(PowerContextSummary.make(observations: [PowerObservation(timestamp: start,
                source: .external, percentage: 70, charging: .notCharging)],
                interval: DateInterval(start: start, duration: 1))?.symbolName == "powerplug",
                   "external power used the battery symbol", &problems)
            return problems
        }
    }

    private static func focusedEditorCommand() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.focus.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let moment = Date(timeIntervalSince1970: 1_788_599_900)
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: SessionArchive(directory: folder, now: { moment }), schedulesDwell: false,
                now: { moment })
            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: engine, schedulesTicker: false,
                                     metadataArchive: metadata, now: { moment })
            let first = UUID(), second = UUID()
            store.beginNoteEditing(for: first); store.setNoteDraft("First\nnewline", for: first)
            store.beginNoteEditing(for: second); store.setNoteDraft("Second", for: second)
            store.setHistoryQuery("Xcode")
            let host = NSHostingView(rootView: VStack {
                SessionNoteEditor(store: store, recordID: first)
                SessionNoteEditor(store: store, recordID: second)
            })
            host.frame = NSRect(x: 0, y: 0, width: 480, height: 260)
            host.layoutSubtreeIfNeeded()
            store.focusedNoteEditorID = second
            var problems: [String] = []
            expect(store.saveFocusedNote(), "focused Command-Return route failed", &problems)
            expect(metadata.metadata(for: second)?.note == "Second"
                   && metadata.metadata(for: first)?.note == nil,
                   "focused save also saved the unfocused editor", &problems)
            expect(store.focusedNoteEditorID == nil,
                   "successful focused save retained a stale editor identity", &problems)
            expect(store.noteDraft(for: first) == "First\nnewline",
                   "ordinary Return/newline was not retained in the other draft", &problems)
            expect(store.historyFilter.query == "Xcode",
                   "note Command-Return changed History search", &problems)
            return problems
        }
    }

    private static func identityAndDraftRetentionHardening() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.harden-id.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let moment = Date(timeIntervalSince1970: 1_788_601_000)
            guard let source = engine(at: moment, directory: folder, suite: suite) else {
                return ["could not create legacy rename fixture"]
            }
            source.start(workType: .deepWork, intent: "Before rename")
            var before = source.snapshot(); before.activeRecordID = nil
            var after = before; after.name = "After rename"
            let first = engine(at: moment, directory: folder, suite: suite + ".first")!
            let second = engine(at: moment, directory: folder, suite: suite + ".second")!
            first.restore(from: before); second.restore(from: after)
            var problems: [String] = []
            expect(first.activeRecordID == second.activeRecordID,
                   "legacy active identity changed after a rename", &problems)

            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: first, schedulesTicker: false,
                                     metadataArchive: metadata, now: { moment })
            let draftID = UUID()
            _ = metadata.saveNote("Durable before editing", for: draftID)
            store.beginNoteEditing(for: draftID)
            store.setNoteDraft("Unsaved revision", for: draftID)
            store.refreshSessionMetadataRetention()
            expect(metadata.metadata(for: draftID)?.note == "Durable before editing",
                   "retention removed durable metadata owned by a guarded open draft", &problems)
            return problems
        }
    }

    private static func groupedPowerCoverageHardening() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.harden-power.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let start = Date(timeIntervalSince1970: 1_788_602_000)
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: SessionArchive(directory: folder, now: { start }), schedulesDwell: false,
                now: { start })
            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: engine, schedulesTicker: false,
                                     metadataArchive: metadata, now: { start })
            let first = UUID(), second = UUID()
            _ = metadata.appendPower(PowerObservation(timestamp: start, source: .battery,
                percentage: 78, charging: .notCharging, boundary: .stretchStarted), for: first)
            var partial = store.powerSummary(for: [first, second],
                interval: DateInterval(start: start, duration: 1_200))
            var problems: [String] = []
            expect(partial?.headline == "Battery · 78%" && partial?.symbolName == "battery.75percent",
                   "partial grouped evidence lost its factual battery source", &problems)
            expect(partial?.detail?.contains("1 of 2 stretches") == true,
                   "partial grouped evidence did not disclose missing stretch coverage", &problems)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(900),
                source: .battery, percentage: 64, charging: .notCharging,
                boundary: .stretchEnded), for: second)
            partial = store.powerSummary(for: [first, second],
                interval: DateInterval(start: start, duration: 1_200))
            expect(partial?.headline == "Battery · 78% → 64%"
                   && partial?.symbolName == "battery.75percent",
                   "complete multi-stretch evidence replaced the factual source with a generic headline", &problems)
            expect(partial?.detail?.contains("gaps between stretches are not power coverage") == true,
                   "multi-stretch evidence omitted its coverage-gap qualification", &problems)
            return problems
        }
    }

    private struct DuplicateDocument: Codable {
        let version: Int
        let entries: [SessionMetadata]
    }

    private static func duplicateMetadataHardening() -> [String] {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let recordID = UUID(), firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let moment = Date(timeIntervalSince1970: 1_788_603_000)
        let entries = [
            SessionMetadata(recordID: recordID, note: "First"),
            SessionMetadata(recordID: recordID, note: "Second")
        ]
        let bytes = try? JSONEncoder().encode(DuplicateDocument(version: 1, entries: entries))
        try? bytes?.write(to: folder.appendingPathComponent("session-metadata.json"), options: .atomic)
        let archive = SessionMetadataArchive(directory: folder)
        var problems: [String] = []
        expect(archive.allMetadata.count == 1 && archive.metadata(for: recordID)?.note == "Second",
               "duplicate record IDs trapped or loaded nondeterministically", &problems)
        _ = archive.appendPower(PowerObservation(id: secondID, timestamp: moment, source: .battery,
            percentage: 64, charging: .notCharging, boundary: .sourceChanged), for: recordID)
        _ = archive.appendPower(PowerObservation(id: firstID, timestamp: moment, source: .battery,
            percentage: 64, charging: .notCharging, boundary: .sourceChanged), for: recordID)
        expect(archive.metadata(for: recordID)?.power.map(\.id) == [firstID, secondID],
               "equal timestamp and boundary observations lacked a deterministic ID tie-break", &problems)
        return problems
    }

    private static func powerDescriptionParser() -> [String] {
        let moment = Date(timeIntervalSince1970: 1_788_604_000)
        func description(type: String = kIOPSInternalBatteryType,
                         state: String, current: Any? = 64, maximum: Any? = 100,
                         charging: Any? = false) -> [String: Any] {
            var value: [String: Any] = [kIOPSTypeKey as String: type,
                                        kIOPSPowerSourceStateKey as String: state]
            if let current { value[kIOPSCurrentCapacityKey as String] = current }
            if let maximum { value[kIOPSMaxCapacityKey as String] = maximum }
            if let charging { value[kIOPSIsChargingKey as String] = charging }
            return value
        }
        let battery = PowerSourceMonitor.parse(descriptions: [description(
            state: kIOPSBatteryPowerValue, current: 78)], at: moment, boundary: .stretchStarted)
        let plugged = PowerSourceMonitor.parse(descriptions: [description(
            state: kIOPSACPowerValue)], at: moment, boundary: nil)
        let charging = PowerSourceMonitor.parse(descriptions: [description(
            state: kIOPSACPowerValue, current: 81, charging: true)], at: moment, boundary: nil)
        let ups = PowerSourceMonitor.parse(descriptions: [description(type: kIOPSUPSType,
            state: kIOPSACPowerValue)], at: moment, boundary: nil)
        let desktop = PowerSourceMonitor.parse(descriptions: [description(type: "External",
            state: kIOPSACPowerValue, current: nil, maximum: nil, charging: nil)],
            at: moment, boundary: nil)
        let invalid = PowerSourceMonitor.parse(descriptions: [description(
            state: kIOPSBatteryPowerValue, current: 64, maximum: 0)], at: moment, boundary: nil)
        let empty = PowerSourceMonitor.parse(descriptions: [], at: moment, boundary: nil)
        var problems: [String] = []
        expect(battery.source == .battery && battery.percentage == 78,
               "IOPS battery description was misclassified", &problems)
        expect(plugged.source == .external && plugged.charging == .notCharging,
               "plugged-not-charging description was misclassified", &problems)
        expect(charging.source == .external && charging.charging == .charging,
               "actively charging description was misclassified", &problems)
        expect(ups.source == .ups, "UPS description was misclassified", &problems)
        expect(desktop.source == .external && desktop.percentage == nil,
               "no-internal-battery external source invented a percentage", &problems)
        expect(invalid.percentage == nil,
               "invalid IOPS capacity denominator produced a percentage", &problems)
        expect(empty.source == .unknown && empty.percentage == nil,
               "empty IOPS description fabricated a source", &problems)
        return problems
    }

    private static func powerSummaries() -> [String] {
        let start = Date(timeIntervalSince1970: 1_788_600_000)
        let battery = [
            PowerObservation(timestamp: start, source: .battery, percentage: 78,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .battery,
                             percentage: 64, charging: .notCharging, boundary: .stretchEnded)
        ]
        let charging = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .charging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 81, charging: .charging, boundary: .stretchEnded)
        ]
        let pluggedIn = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 64, charging: .notCharging, boundary: .stretchEnded)
        ]
        let chargingTransition = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(900), source: .external,
                             percentage: 64, charging: .charging, boundary: .sourceChanged),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 81, charging: .charging, boundary: .stretchEnded)
        ]
        let interval = DateInterval(start: start, duration: 1_800)
        var problems: [String] = []
        expect(PowerContextSummary.make(observations: battery, interval: interval)?.headline
               == "Battery · 78% → 64%", "battery sequence was not rendered literally", &problems)
        expect(PowerContextSummary.make(observations: charging, interval: interval)?.headline
               == "Plugged in, charging · 64% → 81%",
               "actively charging evidence was not stated", &problems)
        expect(PowerContextSummary.make(observations: pluggedIn, interval: interval)?.headline
               == "Plugged in · 64% → 64%",
               "external power without charging was labelled as actively charging", &problems)
        let transition = PowerContextSummary.make(observations: chargingTransition, interval: interval)
        expect(transition?.headline == "Power changed",
               "a charging-state transition was flattened into one state", &problems)
        expect(transition?.detail?.contains("15m — Plugged in, charging") == true,
               "charging transition detail lacked ordered relative time and state", &problems)
        expect((transition?.detail ?? "").contains("session energy") == false,
               "power detail implied session energy attribution", &problems)
        return problems
    }

    private static func partialPowerEvidence() -> [String] {
        let start = Date(timeIntervalSince1970: 1_788_700_000)
        let invalid = PowerObservation.normalised(timestamp: start, source: .battery,
            currentCapacity: 64, maximumCapacity: 0, charging: .unknown,
            boundary: .stretchStarted)
        let nonFinite = PowerObservation.normalised(timestamp: start, source: .battery,
            currentCapacity: .infinity, maximumCapacity: 100, charging: .unknown)
        let observations = [
            invalid,
            PowerObservation(timestamp: start.addingTimeInterval(300), source: .unknown,
                             percentage: nil, charging: .unknown, boundary: .coverageResumed),
            PowerObservation(timestamp: start.addingTimeInterval(600), source: .ups,
                             percentage: nil, charging: .notCharging, boundary: .sourceChanged)
        ]
        let summary = PowerContextSummary.make(
            observations: observations, interval: DateInterval(start: start, duration: 900))
        var problems: [String] = []
        expect(invalid.percentage == nil && nonFinite.percentage == nil,
               "invalid capacity produced an invented percentage", &problems)
        expect(summary?.headline == "Power changed",
               "mixed or partial sources claimed one continuous source", &problems)
        expect(summary?.detail?.contains("coverage resumed") == true,
               "resume gap was not qualified in expanded detail", &problems)
        return problems
    }

    private static func oldSessionHasNoPowerFallback() -> [String] {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_600_000_000), duration: 600)
        return PowerContextSummary.make(observations: [], interval: interval) == nil
            ? [] : ["an old session without metadata displayed a current-system power fallback"]
    }
}
