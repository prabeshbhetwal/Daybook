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
        ("Session metadata: unique entries and equal-time observations load deterministically", duplicateMetadataHardening),
        ("Session metadata: public IOPS descriptions parse without live sampling", powerDescriptionParser),
        ("Session metadata: hardware samples use observation time without backfill", factualBoundarySampling),
        ("Session metadata: Away answer atomically reassigns post-return observations", awayObservationReassignment),
        ("Session metadata: ambiguous duplicate sidecars fail closed byte-for-byte", duplicateSidecarsFailClosed),
        ("Session metadata: failed power transfer retries exact ownership before boundaries", failedPowerTransferRecovery),
        ("Session metadata: pending power transfers complete in identity order", orderedPowerTransferRecovery),
        ("Session metadata: cold launch restores engine before durable transfer replay", coldLaunchTransferRecovery),
        ("Session metadata: failed ordinary power writes replay exact queued evidence", failedOrdinaryPowerWriteRecovery),
        ("Session metadata: same-record observation conflicts block queue replay", sameRecordObservationConflictRecovery),
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
            expect(metadata.metadata(for: recordID)?.power.contains(where: {
                $0.boundary == .stretchEnded
            }) == false,
                   "Away split manufactured an old predecessor end sample", &problems)
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
        let entries = [SessionMetadata(recordID: recordID, note: "Second")]
        let bytes = try? JSONEncoder().encode(DuplicateDocument(version: 1, entries: entries))
        try? bytes?.write(to: folder.appendingPathComponent("session-metadata.json"), options: .atomic)
        let archive = SessionMetadataArchive(directory: folder)
        var problems: [String] = []
        expect(archive.allMetadata.count == 1 && archive.metadata(for: recordID)?.note == "Second",
               "unique record did not load normally", &problems)
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

    private static func makePowerFixture(_ clock: Clock, folder: URL, suite: String,
                                         sample: PowerObservation) -> (SessionStore, SessionEngine,
                                            SessionMetadataArchive, FakePowerMonitor) {
        let archive = SessionArchive(directory: folder, now: { clock.value })
        let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
            archive: archive, ownBundleID: "com.example.metadata.boundary", schedulesDwell: false,
            now: { clock.value })
        let metadata = SessionMetadataArchive(directory: folder)
        let monitor = FakePowerMonitor(sample: sample)
        let store = SessionStore(engine: engine, schedulesTicker: false,
            metadataArchive: metadata, powerMonitor: monitor, now: { clock.value })
        return (store, engine, metadata, monitor)
    }

    private static func factualBoundarySampling() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []

            // Ordinary start/end are observed at the contemporaneous injected clock.
            do {
                let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.boundary.normal.\(UUID())"
                defer { try? FileManager.default.removeItem(at: folder); UserDefaults.standard.removePersistentDomain(forName: suite) }
                let clock = Clock(Date(timeIntervalSince1970: 1_788_610_000))
                let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                    sample: PowerObservation(timestamp: clock.value, source: .battery,
                        percentage: 78, charging: .notCharging))
                fixture.1.start(workType: .deepWork, intent: "Normal")
                fixture.0.refresh()
                let id = fixture.1.activeRecordID
                clock.advance(600)
                fixture.0.stop()
                let power = fixture.2.metadata(for: id)?.power ?? []
                expect(power.first?.timestamp == Date(timeIntervalSince1970: 1_788_610_000)
                       && power.first?.boundary == .stretchStarted,
                       "contemporaneous start was not sampled at the injected clock", &problems)
                expect(power.last?.timestamp == clock.value && power.last?.boundary == .stretchEnded,
                       "contemporaneous end was not sampled at the injected clock", &problems)
            }

            // A restored old stretch begins coverage now; it does not fabricate its old start.
            do {
                let folder = directory(), sourceSuite = "com.prabesh.focuscontinuity.metadata.boundary.restore.source.\(UUID())"
                let reloadSuite = sourceSuite + ".reload"
                defer {
                    try? FileManager.default.removeItem(at: folder)
                    UserDefaults.standard.removePersistentDomain(forName: sourceSuite)
                    UserDefaults.standard.removePersistentDomain(forName: reloadSuite)
                }
                let old = Date(timeIntervalSince1970: 1_788_620_000)
                let sourceClock = Clock(old)
                let source = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: sourceSuite)!),
                    archive: SessionArchive(directory: folder, now: { sourceClock.value }),
                    schedulesDwell: false, now: { sourceClock.value })
                source.start(workType: .deepWork, intent: "Restored")
                var snapshot = source.snapshot()
                let clock = Clock(old.addingTimeInterval(3_600))
                snapshot.savedAt = clock.value
                let fixture = makePowerFixture(clock, folder: folder, suite: reloadSuite,
                    sample: PowerObservation(timestamp: clock.value, source: .battery,
                        percentage: 72, charging: .notCharging))
                fixture.1.restore(from: snapshot)
                fixture.0.refresh()
                let power = fixture.2.metadata(for: fixture.1.activeRecordID)?.power ?? []
                expect(power.count == 1 && power[0].timestamp == clock.value
                       && power[0].boundary == .coverageResumed,
                       "restored session backfilled a historical start observation", &problems)
            }

            // Automatic backdating samples now as partial coverage, never at backdatedTo.
            do {
                let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.boundary.auto.\(UUID())"
                defer { try? FileManager.default.removeItem(at: folder); UserDefaults.standard.removePersistentDomain(forName: suite) }
                let clock = Clock(Date(timeIntervalSince1970: 1_788_630_000))
                let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                    sample: PowerObservation(timestamp: clock.value, source: .external,
                        percentage: 64, charging: .charging))
                let backdated = clock.value.addingTimeInterval(-900)
                fixture.0.startAutomatically(workType: .deepWork, name: "Automatic",
                                             backdatedTo: backdated, because: "Observed")
                let id = fixture.1.activeRecordID
                let power = fixture.2.metadata(for: id)?.power ?? []
                expect(power.count == 1 && power[0].timestamp == clock.value
                       && power[0].boundary == .coverageResumed,
                       "automatic backdate stamped current hardware at backdatedTo", &problems)

                // A detector ending late must not manufacture a sample at its old record end.
                clock.advance(600)
                let delayedEnd = clock.value.addingTimeInterval(-300)
                _ = fixture.1.stop(endingAt: delayedEnd)
                fixture.0.refresh()
                let ended = fixture.2.metadata(for: id)?.power ?? []
                expect(!ended.contains(where: { $0.boundary == .stretchEnded }),
                       "delayed automatic end manufactured a historical end sample", &problems)
                expect(ended.allSatisfy { $0.timestamp != delayedEnd },
                       "delayed automatic end stored the archived record timestamp as observation time", &problems)
            }
            return problems
        }
    }

    private static func awayObservationReassignment() -> [String] {
        MainActor.assumeIsolated {
            var allProblems: [String] = []
            let decisions: [(UserDecision, String)] = [
                (.continueSession, "Continue"), (.tookBreak, "Break"), (.resetTimer, "Reset")
            ]
            for (decision, label) in decisions {
                let folder = directory()
                let suite = "com.prabesh.focuscontinuity.metadata.boundary.away.\(label).\(UUID())"
                defer {
                    try? FileManager.default.removeItem(at: folder)
                    UserDefaults.standard.removePersistentDomain(forName: suite)
                }
                let clock = Clock(Date(timeIntervalSince1970: 1_788_640_000))
                let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                    sample: PowerObservation(timestamp: clock.value, source: .battery,
                        percentage: 78, charging: .notCharging))
                var problems: [String] = []
                fixture.1.start(workType: .deepWork, intent: "Away split")
                fixture.0.refresh()
                let predecessor = fixture.1.activeRecordID
                clock.advance(600)
                fixture.1.transition(on: .awayBegan(trigger: .screenLock))
                clock.advance(1_200)
                fixture.1.transition(on: .awayEnded)
                let returnedAt = clock.value
                fixture.3.handler?(PowerObservation(timestamp: returnedAt, source: .external,
                    percentage: 64, charging: .notCharging, boundary: .sourceChanged))
                expect(fixture.2.metadata(for: predecessor)?.power.contains(where: {
                    $0.timestamp == returnedAt && $0.boundary == .sourceChanged
                }) == true, "post-return event was not initially bound to the open predecessor", &problems)

                clock.advance(300)
                expect(fixture.0.resolve(decision), "Away split fixture could not save \(label)", &problems)
                let successor = fixture.1.activeRecordID
                let predecessorPower = fixture.2.metadata(for: predecessor)?.power ?? []
                let successorPower = fixture.2.metadata(for: successor)?.power ?? []
                expect(!predecessorPower.contains(where: { $0.timestamp >= returnedAt }),
                       "Away \(label) left post-return observations on the closed predecessor", &problems)
                expect(successorPower.contains(where: {
                    $0.timestamp == returnedAt && $0.boundary == .sourceChanged
                }), "Away \(label) did not atomically move post-return evidence", &problems)
                expect(successorPower.contains(where: {
                    $0.timestamp == clock.value && $0.boundary == .coverageResumed
                }), "Away \(label) successor did not begin partial coverage at answer time", &problems)
                expect(!predecessorPower.contains(where: { $0.boundary == .stretchEnded })
                       && !successorPower.contains(where: { $0.boundary == .stretchStarted }),
                       "Away \(label) fabricated historical boundaries", &problems)
                fixture.3.handler?(PowerObservation(timestamp: clock.value.addingTimeInterval(1),
                    source: .external, percentage: 63, charging: .notCharging,
                    boundary: .sourceChanged))
                expect(fixture.2.metadata(for: successor)?.power.last?.percentage == 63,
                       "post-\(label) callback attached to the stale predecessor", &problems)
                allProblems.append(contentsOf: problems)
            }
            return allProblems
        }
    }

    private static func duplicateSidecarsFailClosed() -> [String] {
        func isFailure(_ result: SessionMetadataWriteResult) -> Bool {
            if case .failed = result { return true }
            return false
        }
        var problems: [String] = []
        let recordID = UUID(), observationID = UUID()
        let moment = Date(timeIntervalSince1970: 1_788_650_000)
        let duplicateEntries = [SessionMetadata(recordID: recordID, note: "First"),
                                SessionMetadata(recordID: recordID, note: "Second")]
        let conflicting = SessionMetadata(recordID: UUID(), power: [
            PowerObservation(id: observationID, timestamp: moment, source: .battery,
                             percentage: 78, charging: .notCharging),
            PowerObservation(id: observationID, timestamp: moment, source: .external,
                             percentage: 64, charging: .charging)
        ])
        let shared = PowerObservation(id: UUID(), timestamp: moment, source: .battery,
                                      percentage: 70, charging: .notCharging)
        let crossOwner = [
            SessionMetadata(recordID: UUID(), power: [shared]),
            SessionMetadata(recordID: UUID(), power: [shared])
        ]

        let payloads: [(String, Data?)] = [
            ("versioned duplicate records", try? JSONEncoder().encode(
                DuplicateDocument(version: 1, entries: duplicateEntries))),
            ("unversioned duplicate records", try? JSONEncoder().encode(duplicateEntries)),
            ("conflicting duplicate observations", try? JSONEncoder().encode(
                DuplicateDocument(version: 1, entries: [conflicting]))),
            ("versioned cross-record observation owner", try? JSONEncoder().encode(
                DuplicateDocument(version: 1, entries: crossOwner))),
            ("unversioned cross-record observation owner", try? JSONEncoder().encode(crossOwner))
        ]
        for (label, payload) in payloads {
            let folder = directory(), file = folder.appendingPathComponent("session-metadata.json")
            defer { try? FileManager.default.removeItem(at: folder) }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let payload else { problems.append("could not encode \(label)"); continue }
            try? payload.write(to: file, options: .atomic)
            let archive = SessionMetadataArchive(directory: folder)
            let original = try? Data(contentsOf: file)
            let note = archive.saveNote("Mutation", for: recordID)
            let power = archive.appendPower(PowerObservation(timestamp: moment,
                source: .battery, percentage: 50, charging: .notCharging), for: recordID)
            let retention = archive.retain(recordIDs: [recordID])
            expect(isFailure(note) && isFailure(power) && isFailure(retention),
                   "\(label) did not fail every mutation closed", &problems)
            expect((try? Data(contentsOf: file)) == original,
                   "\(label) changed original sidecar bytes", &problems)
            expect(archive.allMetadata.isEmpty,
                   "\(label) published ambiguous cache evidence", &problems)
        }
        return problems
    }

    private static func failedPowerTransferRecovery() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.transfer.retry.\(UUID())"
            defer { try? FileManager.default.removeItem(at: folder); UserDefaults.standard.removePersistentDomain(forName: suite) }
            let clock = Clock(Date(timeIntervalSince1970: 1_788_660_000))
            let archive = SessionArchive(directory: folder, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: archive, schedulesDwell: false, now: { clock.value })
            var failNext = false
            let metadata = SessionMetadataArchive(directory: folder, writeOverride: { _ in
                if failNext { failNext = false; return "One-shot metadata transfer failure." }
                return nil
            })
            let monitor = FakePowerMonitor(sample: PowerObservation(timestamp: clock.value,
                source: .battery, percentage: 78, charging: .notCharging))
            var store: SessionStore? = SessionStore(engine: engine, schedulesTicker: false,
                metadataArchive: metadata, powerMonitor: monitor, now: { clock.value })
            let unrelatedEditor = UUID()
            store?.beginNoteEditing(for: unrelatedEditor)
            store?.setNoteDraft("Unrelated note draft", for: unrelatedEditor)
            engine.start(workType: .deepWork, intent: "Retry transfer")
            store?.refresh()
            let predecessor = engine.activeRecordID
            clock.advance(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(1_200)
            engine.transition(on: .awayEnded)
            let returnedAt = clock.value
            let originalEvent = PowerObservation(timestamp: returnedAt, source: .external,
                percentage: 64, charging: .notCharging, boundary: .sourceChanged)
            monitor.handler?(originalEvent)
            let bytesBefore = try? Data(contentsOf: folder.appendingPathComponent("session-metadata.json"))
            let cacheBefore = metadata.allMetadata
            clock.advance(300)
            failNext = true
            var problems: [String] = []
            expect(store?.resolve(.continueSession) == true,
                   "one-shot transfer fixture could not save Continue", &problems)
            let successor = engine.activeRecordID
            expect(store?.lastPowerRecordID == predecessor,
                   "failed transfer advanced predecessor bookkeeping", &problems)
            expect(store?.powerMetadataError == "One-shot metadata transfer failure.",
                   "failed transfer did not expose visible power metadata error", &problems)
            expect(engine.store.pendingPowerTransfers == [PendingPowerTransfer(
                sourceID: predecessor, destinationID: successor, factualBoundary: returnedAt)],
                   "failed transfer queue was not persisted exactly", &problems)
            expect(engine.store.pendingPowerMetadataError == "One-shot metadata transfer failure.",
                   "failed transfer error was not durable", &problems)
            expect(store?.powerMetadataError(for: predecessor) != nil
                   && store?.powerMetadataError(for: successor) != nil,
                   "failed transfer error was not record-scoped to both affected entries", &problems)
            expect(store?.powerMetadataError(for: [predecessor, successor])
                   == "One-shot metadata transfer failure.",
                   "affected Story entry IDs did not receive the rendered metadata error", &problems)
            expect(store?.powerMetadataError(for: unrelatedEditor) == nil
                   && store?.noteError(for: unrelatedEditor) == nil,
                   "power failure leaked into an unrelated note editor", &problems)
            expect((try? Data(contentsOf: folder.appendingPathComponent("session-metadata.json"))) == bytesBefore
                   && metadata.allMetadata == cacheBefore,
                   "failed transfer changed sidecar bytes or cache ownership", &problems)
            expect(metadata.metadata(for: successor)?.power.isEmpty != false,
                   "failed transfer published a successor boundary sample", &problems)

            let laterEvent = PowerObservation(timestamp: clock.value.addingTimeInterval(1),
                source: .external, percentage: 63, charging: .notCharging,
                boundary: .sourceChanged)
            monitor.handler?(laterEvent)
            store = nil
            // Simulate termination after the atomic sidecar commit but before
            // durable queue clearance. Relaunch replay must be idempotent.
            let committedBeforeClear = SessionMetadataArchive(directory: folder)
            expect(committedBeforeClear.reassignPower(from: predecessor, to: successor,
                atOrAfter: returnedAt) == .saved,
                   "could not simulate sidecar success before queue clearance", &problems)
            expect(!engine.store.pendingPowerTransfers.isEmpty,
                   "simulated pre-clear commit unexpectedly cleared durable recovery", &problems)
            let reloadedMetadata = SessionMetadataArchive(directory: folder)
            let reloadedMonitor = FakePowerMonitor(sample: PowerObservation(timestamp: clock.value,
                source: .external, percentage: 62, charging: .notCharging))
            let reloadedStore = SessionStore(engine: engine, schedulesTicker: false,
                metadataArchive: reloadedMetadata, powerMonitor: reloadedMonitor,
                now: { clock.value })
            reloadedStore.refresh()
            let sourcePower = reloadedMetadata.metadata(for: predecessor)?.power ?? []
            let destinationPower = reloadedMetadata.metadata(for: successor)?.power ?? []
            expect(reloadedStore.lastPowerRecordID == successor
                   && reloadedStore.powerMetadataError == nil,
                   "successful retry did not advance exact successor bookkeeping", &problems)
            expect(engine.store.pendingPowerTransfers.isEmpty
                   && engine.store.pendingPowerMetadataError == nil,
                   "successful relaunch retry did not clear durable queue/error", &problems)
            expect(reloadedStore.noteError(for: unrelatedEditor) == nil,
                   "durable recovery left a stale unrelated note error", &problems)
            expect(!sourcePower.contains(where: { $0.id == originalEvent.id }),
                   "successful retry left original event on predecessor", &problems)
            expect(destinationPower.filter { $0.id == originalEvent.id }.count == 1,
                   "successful retry did not move original event exactly once", &problems)
            expect(destinationPower.filter { $0.id == laterEvent.id }.count == 1,
                   "retry did not merge an already-successor-bound callback", &problems)
            expect(!destinationPower.contains(where: {
                $0.boundary == .stretchStarted || $0.boundary == .stretchEnded
            }), "retry fabricated successor boundary observations", &problems)
            return problems
        }
    }

    private static func orderedPowerTransferRecovery() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.focuscontinuity.metadata.transfer.order.\(UUID())"
            defer { try? FileManager.default.removeItem(at: folder); UserDefaults.standard.removePersistentDomain(forName: suite) }
            let clock = Clock(Date(timeIntervalSince1970: 1_788_670_000))
            let archive = SessionArchive(directory: folder, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: archive, schedulesDwell: false, now: { clock.value })
            var failNext = false
            let metadata = SessionMetadataArchive(directory: folder, writeOverride: { _ in
                if failNext { failNext = false; return "First transfer blocked." }
                return nil
            })
            let monitor = FakePowerMonitor(sample: PowerObservation(timestamp: clock.value,
                source: .battery, percentage: 78, charging: .notCharging))
            let store = SessionStore(engine: engine, schedulesTicker: false,
                metadataArchive: metadata, powerMonitor: monitor, now: { clock.value })
            engine.start(workType: .deepWork, intent: "First")
            store.refresh()
            let first = engine.activeRecordID
            clock.advance(600); engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(1_200); engine.transition(on: .awayEnded)
            let returnedAt = clock.value
            let firstEvent = PowerObservation(timestamp: returnedAt, source: .external,
                percentage: 65, charging: .notCharging, boundary: .sourceChanged)
            monitor.handler?(firstEvent)
            clock.advance(300); failNext = true
            _ = store.resolve(.continueSession)
            let second = engine.activeRecordID
            let secondEvent = PowerObservation(timestamp: clock.value.addingTimeInterval(1),
                source: .external, percentage: 64, charging: .notCharging,
                boundary: .sourceChanged)
            monitor.handler?(secondEvent)
            clock.advance(1)
            _ = engine.start(workType: .admin, intent: "Third")
            let third = engine.activeRecordID
            store.refresh()
            var problems: [String] = []
            expect(first != second && second != third && store.lastPowerRecordID == third,
                   "queued recovery collapsed or skipped a stretch identity", &problems)
            expect(metadata.metadata(for: second)?.power.contains(where: { $0.id == firstEvent.id }) == true,
                   "first transfer did not stop at its exact successor", &problems)
            expect(metadata.metadata(for: third)?.power.contains(where: { $0.id == secondEvent.id }) == true,
                   "second transfer did not progress successor evidence in order", &problems)
            expect(metadata.metadata(for: first)?.power.contains(where: { $0.id == firstEvent.id }) == false,
                   "ordered recovery left evidence on the first predecessor", &problems)
            return problems
        }
    }

    private static func coldLaunchTransferRecovery() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory()
            let suite = "com.prabesh.focuscontinuity.metadata.transfer.cold.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            guard let defaults = UserDefaults(suiteName: suite) else {
                return ["could not create cold-launch preferences"]
            }
            let clock = Clock(Date(timeIntervalSince1970: 1_788_680_000))
            var failNext = false
            var firstArchive: SessionArchive? = SessionArchive(directory: folder, now: { clock.value })
            var firstEngine: SessionEngine? = SessionEngine(
                store: PersistenceStore(defaults: defaults), archive: firstArchive,
                schedulesDwell: false, now: { clock.value })
            let firstMetadata = SessionMetadataArchive(directory: folder, writeOverride: { _ in
                if failNext { failNext = false; return "Cold-launch transfer failure." }
                return nil
            })
            let firstMonitor = FakePowerMonitor(sample: PowerObservation(timestamp: clock.value,
                source: .battery, percentage: 78, charging: .notCharging))
            var firstStore: SessionStore? = SessionStore(engine: firstEngine!, schedulesTicker: false,
                metadataArchive: firstMetadata, powerMonitor: firstMonitor, now: { clock.value })
            firstEngine!.start(workType: .deepWork, intent: "Cold launch")
            firstStore!.refresh()
            let predecessor = firstEngine!.activeRecordID
            clock.advance(600)
            firstEngine!.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(1_200)
            firstEngine!.transition(on: .awayEnded)
            let returnedAt = clock.value
            let event = PowerObservation(timestamp: returnedAt, source: .external,
                percentage: 64, charging: .notCharging, boundary: .sourceChanged)
            firstMonitor.handler?(event)
            clock.advance(300)
            failNext = true
            _ = firstStore!.resolve(.continueSession)
            let successor = firstEngine!.activeRecordID
            var problems: [String] = []
            expect(firstEngine!.store.pendingPowerTransfers.count == 1,
                   "first process did not persist failed transfer", &problems)
            expect(firstEngine!.snapshot().activeRecordID == successor,
                   "first process did not persist successor snapshot", &problems)
            firstStore = nil
            firstEngine = nil
            firstArchive = nil

            let freshArchive = SessionArchive(directory: folder, now: { clock.value })
            let freshEngine = SessionEngine(store: PersistenceStore(defaults: defaults),
                archive: freshArchive, schedulesDwell: false, now: { clock.value })
            expect(freshEngine.state == .idle,
                   "fresh cold-launch engine was not initially idle", &problems)
            expect(AppCoordinator.restorePersistedEngine(freshEngine, awayAtLaunch: false),
                   "production restore boundary did not load successor snapshot", &problems)
            expect(freshEngine.state == .running && freshEngine.activeRecordID == successor,
                   "restore boundary did not restore successor before store construction", &problems)

            let freshMetadata = SessionMetadataArchive(directory: folder)
            let freshMonitor = FakePowerMonitor(sample: PowerObservation(timestamp: clock.value,
                source: .external, percentage: 63, charging: .notCharging))
            let freshStore = SessionStore(engine: freshEngine, schedulesTicker: false,
                metadataArchive: freshMetadata, powerMonitor: freshMonitor, now: { clock.value })
            freshStore.refresh()
            expect(freshEngine.store.pendingPowerTransfers.isEmpty
                   && freshEngine.store.pendingPowerMetadataError == nil,
                   "cold-launch replay did not clear recovery after durable success", &problems)
            expect(freshMetadata.metadata(for: predecessor)?.power.contains(where: {
                $0.id == event.id
            }) == false && freshMetadata.metadata(for: successor)?.power.filter({
                $0.id == event.id
            }).count == 1,
                   "cold-launch replay did not move evidence exactly once", &problems)
            freshStore.refreshSessionMetadataRetention()
            expect(SessionMetadataArchive(directory: folder).metadata(for: successor) != nil,
                   "cold-launch retention pruned recovered active successor metadata", &problems)
            return problems
        }
    }

    private static func failedOrdinaryPowerWriteRecovery() -> [String] {
        struct StoredPendingObservation: Codable, Equatable {
            let recordID: UUID
            let observation: PowerObservation
            let lastError: String?
        }

        return MainActor.assumeIsolated {
            let folder = directory()
            let suite = "com.prabesh.focuscontinuity.metadata.append.retry.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            guard let defaults = UserDefaults(suiteName: suite) else {
                return ["could not create ordinary power recovery preferences"]
            }
            let pendingKey = "fc.pendingPowerObservations"
            func storedQueue() -> [StoredPendingObservation] {
                guard let data = defaults.data(forKey: pendingKey),
                      let queue = try? JSONDecoder().decode(
                        [StoredPendingObservation].self, from: data)
                else { return [] }
                return queue
            }

            let clock = Clock(Date(timeIntervalSince1970: 1_788_690_000))
            var failNext = false
            var firstArchive: SessionArchive? = SessionArchive(
                directory: folder, now: { clock.value })
            var firstEngine: SessionEngine? = SessionEngine(
                store: PersistenceStore(defaults: defaults), archive: firstArchive,
                schedulesDwell: false, now: { clock.value })
            let firstMetadata = SessionMetadataArchive(directory: folder, writeOverride: { _ in
                if failNext {
                    failNext = false
                    return "One-shot ordinary power failure."
                }
                return nil
            })
            let firstMonitor = FakePowerMonitor(sample: PowerObservation(
                timestamp: clock.value, source: .battery, percentage: 78,
                charging: .notCharging))
            var firstStore: SessionStore? = SessionStore(
                engine: firstEngine!, schedulesTicker: false,
                metadataArchive: firstMetadata, powerMonitor: firstMonitor,
                now: { clock.value })
            let unrelatedRecord = UUID()
            firstStore!.beginNoteEditing(for: unrelatedRecord)
            firstStore!.setNoteDraft("Unrelated note draft", for: unrelatedRecord)
            firstEngine!.start(workType: .deepWork, intent: "Ordinary recovery")
            firstStore!.refresh()
            let affectedRecord = firstEngine!.activeRecordID
            let file = folder.appendingPathComponent("session-metadata.json")
            let bytesBeforeFailure = try? Data(contentsOf: file)
            let cacheBeforeFailure = firstMetadata.allMetadata

            clock.advance(600)
            let failedObservation = PowerObservation(
                id: UUID(), timestamp: clock.value, source: .external,
                percentage: 64, charging: .notCharging, boundary: .sourceChanged)
            failNext = true
            firstMonitor.handler?(failedObservation)
            var problems: [String] = []
            expect((try? Data(contentsOf: file)) == bytesBeforeFailure
                   && firstMetadata.allMetadata == cacheBeforeFailure,
                   "failed ordinary append changed sidecar bytes or cache", &problems)
            expect(storedQueue() == [StoredPendingObservation(
                recordID: affectedRecord, observation: failedObservation,
                lastError: "One-shot ordinary power failure.")],
                   "failed ordinary append did not persist its exact record, sample and error",
                   &problems)
            expect(firstStore!.powerMetadataError(for: affectedRecord)
                   == "One-shot ordinary power failure.",
                   "affected Story record did not receive its ordinary power error", &problems)
            expect(firstStore!.powerMetadataError(for: unrelatedRecord) == nil
                   && firstStore!.noteError(for: unrelatedRecord) == nil,
                   "ordinary power failure contaminated an unrelated record or note editor",
                   &problems)

            clock.advance(30)
            let laterObservation = PowerObservation(
                id: UUID(), timestamp: clock.value, source: .battery,
                percentage: 63, charging: .notCharging, boundary: .sourceChanged)
            firstMonitor.handler?(laterObservation)
            expect((try? Data(contentsOf: file)) == bytesBeforeFailure
                   && firstMetadata.allMetadata == cacheBeforeFailure,
                   "a later distinct sample bypassed the blocked queue front", &problems)
            expect(storedQueue() == [
                StoredPendingObservation(recordID: affectedRecord,
                    observation: failedObservation,
                    lastError: "One-shot ordinary power failure."),
                StoredPendingObservation(recordID: affectedRecord,
                    observation: laterObservation, lastError: nil)
            ], "ordinary samples were not retained in exact arrival order", &problems)
            expect(firstStore!.powerMetadataError(for: affectedRecord)
                   == "One-shot ordinary power failure.",
                   "a different sample falsely cleared the failed observation error", &problems)
            firstStore!.refreshSessionMetadataRetention()
            expect(firstMetadata.metadata(for: affectedRecord) != nil,
                   "retention removed a record with pending power evidence", &problems)

            // Simulate process exit after the sidecar commit but before recovery
            // preferences are cleared. Replaying the same observation UUID must
            // remain an idempotent success rather than duplicate the evidence.
            expect(firstMetadata.appendPower(failedObservation, for: affectedRecord) == .saved,
                   "could not simulate an ordinary sidecar commit before queue clearance",
                   &problems)
            expect(storedQueue().count == 2,
                   "simulated pre-clear sidecar commit unexpectedly cleared recovery",
                   &problems)

            firstStore = nil
            firstEngine = nil
            firstArchive = nil

            let freshArchive = SessionArchive(directory: folder, now: { clock.value })
            let freshEngine = SessionEngine(store: PersistenceStore(defaults: defaults),
                archive: freshArchive, schedulesDwell: false, now: { clock.value })
            expect(AppCoordinator.restorePersistedEngine(freshEngine, awayAtLaunch: false),
                   "fresh engine could not restore before ordinary queue replay", &problems)
            expect(freshEngine.activeRecordID == affectedRecord,
                   "fresh engine restored a different record before ordinary queue replay",
                   &problems)
            let freshMetadata = SessionMetadataArchive(directory: folder)
            let freshMonitor = FakePowerMonitor(sample: PowerObservation(
                timestamp: clock.value, source: .battery, percentage: 62,
                charging: .notCharging))
            let freshStore = SessionStore(engine: freshEngine, schedulesTicker: false,
                metadataArchive: freshMetadata, powerMonitor: freshMonitor,
                now: { clock.value })
            let replayed = freshMetadata.metadata(for: affectedRecord)?.power ?? []
            let replayedIDs = replayed.map(\.id)
            expect(replayed.filter { $0 == failedObservation }.count == 1
                   && replayed.filter { $0 == laterObservation }.count == 1,
                   "fresh store did not replay both exact queued observations once", &problems)
            expect(replayedIDs.firstIndex(of: failedObservation.id)
                   .flatMap { first in replayedIDs.firstIndex(of: laterObservation.id).map {
                       first < $0
                   } } == true,
                   "fresh store replayed ordinary observations out of order", &problems)
            expect(storedQueue().isEmpty
                   && freshStore.powerMetadataError(for: affectedRecord) == nil,
                   "durable ordinary replay did not clear its queue and record error", &problems)
            freshStore.refreshSessionMetadataRetention()
            expect(SessionMetadataArchive(directory: folder)
                   .metadata(for: affectedRecord) != nil,
                   "retention removed the replayed active record", &problems)

            let cleanupStore = PersistenceStore(defaults: defaults)
            cleanupStore.pendingPowerObservations = [PendingPowerObservation(
                recordID: affectedRecord, observation: failedObservation,
                lastError: "Cleanup probe")]
            cleanupStore.pendingPowerTransfers = [PendingPowerTransfer(
                sourceID: affectedRecord, destinationID: unrelatedRecord,
                factualBoundary: failedObservation.timestamp)]
            cleanupStore.pendingPowerMetadataError = "Cleanup probe"
            cleanupStore.removeAll()
            expect(cleanupStore.pendingPowerObservations.isEmpty
                   && cleanupStore.pendingPowerTransfers.isEmpty
                   && cleanupStore.pendingPowerMetadataError == nil,
                   "removeAll left pending power recovery evidence in fixture preferences",
                   &problems)

            // A pending-only record is neither active nor archived. A failed
            // cold-launch replay must retain its existing metadata until the
            // queued observation can be durably appended.
            let retentionFolder = directory()
            let retentionSuite = suite + ".retention"
            defer {
                try? FileManager.default.removeItem(at: retentionFolder)
                UserDefaults.standard.removePersistentDomain(forName: retentionSuite)
            }
            if let retentionDefaults = UserDefaults(suiteName: retentionSuite) {
                let pendingOnlyRecord = UUID()
                let pendingOnlyObservation = PowerObservation(
                    id: UUID(), timestamp: clock.value, source: .ups,
                    percentage: 55, charging: .unknown, boundary: .sourceChanged)
                let seeded = SessionMetadataArchive(directory: retentionFolder)
                expect(seeded.saveNote("Retention sentinel", for: pendingOnlyRecord) == .saved,
                       "could not seed pending-only retention metadata", &problems)
                let recovery = PersistenceStore(defaults: retentionDefaults)
                recovery.pendingPowerObservations = [PendingPowerObservation(
                    recordID: pendingOnlyRecord, observation: pendingOnlyObservation,
                    lastError: "Blocked before launch")]
                let pendingID = pendingOnlyObservation.id.uuidString
                let blockedArchive = SessionMetadataArchive(
                    directory: retentionFolder, writeOverride: { data in
                        String(data: data, encoding: .utf8)?.contains(pendingID) == true
                            ? "Retention replay blocked." : nil
                    })
                let idleEngine = SessionEngine(store: recovery,
                    archive: SessionArchive(directory: retentionFolder,
                        now: { clock.value }),
                    schedulesDwell: false, now: { clock.value })
                let idleStore = SessionStore(engine: idleEngine, schedulesTicker: false,
                    metadataArchive: blockedArchive, now: { clock.value })
                expect(blockedArchive.metadata(for: pendingOnlyRecord)?.note
                       == "Retention sentinel"
                       && recovery.pendingPowerObservations.first?.recordID
                       == pendingOnlyRecord,
                       "cold-launch retention pruned a pending-only observation record",
                       &problems)
                expect(idleStore.powerMetadataError(for: pendingOnlyRecord)
                       == "Retention replay blocked.",
                       "pending-only cold-launch replay lost its record-scoped error",
                       &problems)
            } else {
                problems.append("could not create pending-only retention preferences")
            }
            return problems
        }
    }

    private static func sameRecordObservationConflictRecovery() -> [String] {
        MainActor.assumeIsolated {
            let moment = Date(timeIntervalSince1970: 1_788_695_000)
            let observationID = UUID()
            let original = PowerObservation(
                id: observationID, timestamp: moment, source: .battery,
                percentage: 78, charging: .notCharging, boundary: .stretchStarted)
            let conflicts: [(label: String, observation: PowerObservation)] = [
                ("timestamp", PowerObservation(
                    id: observationID, timestamp: moment.addingTimeInterval(1),
                    source: .battery, percentage: 78, charging: .notCharging,
                    boundary: .stretchStarted)),
                ("boundary", PowerObservation(
                    id: observationID, timestamp: moment, source: .battery,
                    percentage: 78, charging: .notCharging,
                    boundary: .coverageResumed)),
                ("payload", PowerObservation(
                    id: observationID, timestamp: moment, source: .external,
                    percentage: 81, charging: .charging, boundary: .stretchStarted))
            ]
            let expectedError = "That power observation already exists on this session record with different content."
            var allProblems: [String] = []

            for conflict in conflicts {
                let folder = directory()
                let suite = "com.prabesh.focuscontinuity.metadata.append.conflict.\(conflict.label).\(UUID())"
                defer {
                    try? FileManager.default.removeItem(at: folder)
                    UserDefaults.standard.removePersistentDomain(forName: suite)
                }
                guard let defaults = UserDefaults(suiteName: suite) else {
                    allProblems.append("could not create \(conflict.label) conflict preferences")
                    continue
                }
                let persistence = PersistenceStore(defaults: defaults)
                let sessionArchive = SessionArchive(directory: folder, now: { moment })
                let engine = SessionEngine(store: persistence, archive: sessionArchive,
                    schedulesDwell: false, now: { moment })
                engine.start(workType: .deepWork, intent: "Conflicting replay")
                let recordID = engine.activeRecordID
                let unrelatedRecord = UUID()
                let archive = SessionMetadataArchive(directory: folder)
                guard archive.appendPower(original, for: recordID) == .saved else {
                    allProblems.append("could not seed \(conflict.label) conflict sidecar")
                    continue
                }
                let file = folder.appendingPathComponent("session-metadata.json")
                let originalBytes = try? Data(contentsOf: file)
                let originalCache = archive.allMetadata
                let later = PowerObservation(
                    id: UUID(), timestamp: moment.addingTimeInterval(120), source: .ups,
                    percentage: 77, charging: .unknown, boundary: .sourceChanged)
                persistence.pendingPowerObservations = [
                    PendingPowerObservation(recordID: recordID,
                        observation: conflict.observation, lastError: nil),
                    PendingPowerObservation(recordID: recordID,
                        observation: later, lastError: nil)
                ]

                var store: SessionStore? = SessionStore(engine: engine,
                    schedulesTicker: false, metadataArchive: archive, now: { moment })
                func expectBlocked(_ phase: String, archive subject: SessionMetadataArchive,
                                   store subjectStore: SessionStore) {
                    let queue = persistence.pendingPowerObservations
                    expect((try? Data(contentsOf: file)) == originalBytes
                           && subject.allMetadata == originalCache,
                           "\(conflict.label) conflict changed sidecar bytes or cache \(phase)",
                           &allProblems)
                    expect(queue.count == 2
                           && queue[0] == PendingPowerObservation(recordID: recordID,
                               observation: conflict.observation, lastError: expectedError)
                           && queue[1] == PendingPowerObservation(recordID: recordID,
                               observation: later, lastError: nil),
                           "\(conflict.label) conflict did not retain the exact queue front, error and later sample \(phase)",
                           &allProblems)
                    expect(subjectStore.powerMetadataError(for: recordID) == expectedError
                           && subjectStore.powerMetadataError(for: unrelatedRecord) == nil,
                           "\(conflict.label) conflict error was not scoped to the exact record \(phase)",
                           &allProblems)
                    expect(subject.metadata(for: recordID)?.power == [original],
                           "\(conflict.label) conflict replaced evidence or let the later sample overtake \(phase)",
                           &allProblems)
                }
                expectBlocked("on first replay", archive: archive, store: store!)
                store!.refresh()
                expectBlocked("after refresh", archive: archive, store: store!)
                store = nil

                let freshSessionArchive = SessionArchive(directory: folder, now: { moment })
                let freshEngine = SessionEngine(store: PersistenceStore(defaults: defaults),
                    archive: freshSessionArchive, schedulesDwell: false, now: { moment })
                expect(AppCoordinator.restorePersistedEngine(freshEngine, awayAtLaunch: false),
                       "\(conflict.label) conflict could not restore before relaunch replay",
                       &allProblems)
                let freshArchive = SessionMetadataArchive(directory: folder)
                let freshStore = SessionStore(engine: freshEngine, schedulesTicker: false,
                    metadataArchive: freshArchive, now: { moment })
                expectBlocked("after relaunch", archive: freshArchive, store: freshStore)
            }

            let exactFolder = directory()
            let exactSuite = "com.prabesh.focuscontinuity.metadata.append.exact.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: exactFolder)
                UserDefaults.standard.removePersistentDomain(forName: exactSuite)
            }
            guard let exactDefaults = UserDefaults(suiteName: exactSuite) else {
                allProblems.append("could not create exact replay preferences")
                return allProblems
            }
            let exactPersistence = PersistenceStore(defaults: exactDefaults)
            let exactSessionArchive = SessionArchive(directory: exactFolder, now: { moment })
            let exactEngine = SessionEngine(store: exactPersistence,
                archive: exactSessionArchive, schedulesDwell: false, now: { moment })
            exactEngine.start(workType: .deepWork, intent: "Exact replay")
            let exactRecord = exactEngine.activeRecordID
            let seeded = SessionMetadataArchive(directory: exactFolder)
            guard seeded.appendPower(original, for: exactRecord) == .saved else {
                allProblems.append("could not seed exact replay sidecar")
                return allProblems
            }
            let exactArchive = SessionMetadataArchive(directory: exactFolder)
            let later = PowerObservation(
                id: UUID(), timestamp: moment.addingTimeInterval(120), source: .ups,
                percentage: 77, charging: .unknown, boundary: .sourceChanged)
            exactPersistence.pendingPowerObservations = [
                PendingPowerObservation(recordID: exactRecord,
                    observation: original, lastError: "Interrupted after sidecar commit."),
                PendingPowerObservation(recordID: exactRecord,
                    observation: later, lastError: nil)
            ]
            let exactStore = SessionStore(engine: exactEngine, schedulesTicker: false,
                metadataArchive: exactArchive, now: { moment })
            let replayed = exactArchive.metadata(for: exactRecord)?.power ?? []
            expect(exactPersistence.pendingPowerObservations.isEmpty
                   && exactStore.powerMetadataError(for: exactRecord) == nil,
                   "exact same-record replay did not clear its queue and prior error", &allProblems)
            expect(replayed.filter { $0 == original }.count == 1
                   && replayed.filter { $0 == later }.count == 1
                   && exactArchive.revision == 1,
                   "exact same-record replay duplicated evidence or committed more than the later sample",
                   &allProblems)
            exactStore.refresh()
            expect(exactArchive.metadata(for: exactRecord)?.power == replayed
                   && exactArchive.revision == 1,
                   "exact same-record replay was processed more than once", &allProblems)
            return allProblems
        }
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
        expect(transition?.detail?.contains("Charging started or stopped") == true,
               "a charging transition was not qualified beneath its headline", &problems)
        expect(transition?.detail?.contains("15m —") == false,
               "power detail enumerated observations instead of summarising them", &problems)
        expect((transition?.detail ?? "").contains("session energy") == false,
               "power detail implied session energy attribution", &problems)
        let postCommitBoundary = PowerContextSummary.make(observations: [
            PowerObservation(timestamp: start, source: .battery, percentage: 78,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: interval.end.addingTimeInterval(1), source: .battery,
                             percentage: 64, charging: .notCharging, boundary: .stretchEnded),
            PowerObservation(timestamp: interval.end.addingTimeInterval(1), source: .external,
                             percentage: 64, charging: .notCharging, boundary: .sourceChanged)
        ], interval: interval)
        expect(postCommitBoundary?.headline == "Battery · 78% → 64%",
               "summary grace admitted a post-interval source change", &problems)
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
        expect(summary?.detail?.contains("resumed part-way through") == true,
               "resume gap was not qualified beneath the headline", &problems)
        expect(summary?.detail?.contains("Battery level was not recorded") == true,
               "missing battery levels were not qualified", &problems)
        // The point of the change: a qualification, not a per-sample log.
        expect((summary?.detail ?? "").split(separator: "\n").count == 1,
               "power detail returned to one line per observation", &problems)
        return problems
    }

    private static func oldSessionHasNoPowerFallback() -> [String] {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_600_000_000), duration: 600)
        return PowerContextSummary.make(observations: [], interval: interval) == nil
            ? [] : ["an old session without metadata displayed a current-system power fallback"]
    }
}
