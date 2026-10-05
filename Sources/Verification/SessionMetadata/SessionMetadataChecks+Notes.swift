import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func notePersistsByRecordID() -> [String] {
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

    static func failedWriteIsNonMutating() -> [String] {
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

    static func directoryPortability() -> [String] {
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

    static func stableStretchIdentity() -> [String] {
        let folder = directory(), suite = "com.prabesh.daybook.metadata.identity.\(UUID())"
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

    static func pendingIdentityMigration() -> [String] {
        let folder = directory(), suite = "com.prabesh.daybook.metadata.pending.\(UUID())"
        defer {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.removePersistentDomain(forName: suite)
            UserDefaults.standard.removePersistentDomain(forName: suite + ".reload")
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

    static func draftFailureAndDismissal() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.draft.\(UUID())"
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

    static func retentionAndCorrectionCoexistence() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.retention.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_595_000))
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
}
