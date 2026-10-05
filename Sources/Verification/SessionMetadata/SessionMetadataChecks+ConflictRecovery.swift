import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func sameRecordObservationConflictRecovery() -> [String] {
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
                let suite = "com.prabesh.daybook.metadata.append.conflict.\(conflict.label).\(UUID())"
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
            let exactSuite = "com.prabesh.daybook.metadata.append.exact.\(UUID())"
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
}
