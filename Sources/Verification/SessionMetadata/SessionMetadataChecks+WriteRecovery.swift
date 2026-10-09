import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func failedOrdinaryPowerWriteRecovery() -> [String] {
        struct StoredPendingObservation: Codable, Equatable {
            let recordID: UUID
            let observation: PowerObservation
            let lastError: String?
        }

        return MainActor.assumeIsolated {
            let folder = directory()
            let suite = "com.prabesh.daybook.metadata.append.retry.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                MemoryDefaults.remove(named: suite)
            }
            guard let defaults = MemoryDefaults.suite(named: suite) else {
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

            let clock = TestClock(Date(timeIntervalSince1970: 1_788_690_000))
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
                MemoryDefaults.remove(named: retentionSuite)
            }
            if let retentionDefaults = MemoryDefaults.suite(named: retentionSuite) {
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
}
