import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func failedPowerTransferRecovery() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.transfer.retry.\(UUID())"
            defer { try? FileManager.default.removeItem(at: folder); MemoryDefaults.remove(named: suite) }
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_660_000))
            let archive = SessionArchive(directory: folder, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: suite)!),
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
            let bytesBefore = sidecarBytes(in: folder)
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
            expect(sidecarBytes(in: folder) == bytesBefore
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

    static func orderedPowerTransferRecovery() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.transfer.order.\(UUID())"
            defer { try? FileManager.default.removeItem(at: folder); MemoryDefaults.remove(named: suite) }
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_670_000))
            let archive = SessionArchive(directory: folder, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: suite)!),
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

    static func coldLaunchTransferRecovery() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory()
            let suite = "com.prabesh.daybook.metadata.transfer.cold.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                MemoryDefaults.remove(named: suite)
            }
            guard let defaults = MemoryDefaults.suite(named: suite) else {
                return ["could not create cold-launch preferences"]
            }
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_680_000))
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
}
