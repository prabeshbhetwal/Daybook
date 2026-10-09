import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func tickBoundaryTagging() -> [String] {
        let moment = Date(timeIntervalSince1970: 1_788_665_000)
        func sample(_ source: PowerSourceKind, _ percentage: Double, _ charging: PowerChargingState) -> PowerObservation {
            PowerObservation(timestamp: moment, source: source, percentage: percentage, charging: charging)
        }
        var problems: [String] = []
        expect(PowerSourceMonitor.boundary(for: sample(.battery, 64, .notCharging), after: nil) == nil,
               "a first notification claimed a change from nothing", &problems)
        expect(PowerSourceMonitor.boundary(for: sample(.battery, 63, .notCharging),
                                           after: sample(.battery, 64, .notCharging)) == nil,
               "a battery level step was tagged as a source change", &problems)
        expect(PowerSourceMonitor.boundary(for: sample(.external, 63, .notCharging),
                                           after: sample(.battery, 63, .notCharging)) == .sourceChanged,
               "plugging in was not tagged as a source change", &problems)
        expect(PowerSourceMonitor.boundary(for: sample(.external, 63, .charging),
                                           after: sample(.external, 63, .notCharging)) == .sourceChanged,
               "charging beginning was not tagged as a change", &problems)
        return problems
    }

    /// Readings while idle go to the day's log, not to a record; readings
    /// while running go to the record, not to the day. Each session boundary
    /// seeds the quiet side, and a quiet block reads its span.
    static func ambientPowerBetweenSessions() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.ambient.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                MemoryDefaults.remove(named: suite)
            }
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_680_000))
            let idleStart = clock.value
            let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                sample: PowerObservation(timestamp: clock.value, source: .battery,
                    percentage: 70, charging: .notCharging))
            let (store, engine, metadata, monitor) = fixture
            var problems: [String] = []

            store.refresh()
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .battery,
                percentage: 70, charging: .notCharging))
            expect(store.ambientPower.observations.count == 1 && metadata.allMetadata.isEmpty,
                   "an idle reading was dropped or attached to a record", &problems)

            clock.advance(600)
            monitor.sample = PowerObservation(timestamp: clock.value, source: .battery,
                                              percentage: 68, charging: .notCharging)
            engine.start(workType: .deepWork, intent: "Between")
            store.refresh()
            let recordID = engine.activeRecordID
            let sessionStart = clock.value
            expect(metadata.metadata(for: recordID)?.power.first?.boundary == .stretchStarted,
                   "the stretch did not get its own start reading", &problems)
            expect(store.ambientPower.observations.count == 2
                   && store.ambientPower.observations.last?.timestamp == sessionStart,
                   "the quiet block ending at the start was not given a last reading", &problems)
            let before = store.ambientPowerSummary(within: DateInterval(start: idleStart, end: sessionStart))
            expect(before?.headline == "Using battery · 70% → 68%",
                   "the quiet block before the session read \(before?.headline ?? "nothing")", &problems)

            clock.advance(600)
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .battery,
                percentage: 66, charging: .notCharging))
            expect(store.ambientPower.observations.count == 2
                   && metadata.metadata(for: recordID)?.power.contains(where: { $0.percentage == 66 }) == true,
                   "a running reading went to the day instead of the record", &problems)

            clock.advance(600)
            monitor.sample = PowerObservation(timestamp: clock.value, source: .external,
                                              percentage: 66, charging: .charging, adapterWatts: 96)
            _ = engine.stop(endingAt: clock.value)
            store.refresh()
            let sessionEnd = clock.value
            expect(store.ambientPower.observations.count == 3
                   && store.ambientPower.observations.last?.timestamp == sessionEnd,
                   "going idle did not give the next quiet block a first reading", &problems)
            clock.advance(300)
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .external,
                percentage: 67, charging: .charging, adapterWatts: 96))
            let after = store.ambientPowerSummary(within: DateInterval(start: sessionEnd, end: clock.value))
            expect(after?.headline == "Plugged in, charging · 96 W · 66% → 67%",
                   "the quiet block after the session read \(after?.headline ?? "nothing")", &problems)
            expect(store.ambientPowerSummary(within: DateInterval(start: sessionStart, end: sessionEnd))?
                    .headline != "Using battery · 66% → 66%"
                   || metadata.metadata(for: recordID)?.power.isEmpty == false,
                   "a session span was read from the day's log", &problems)

            // Kept by date, reloaded whole, and never lost to a failed write.
            let reloaded = AmbientPowerLog(directory: folder)
            expect(reloaded.observations.count == store.ambientPower.observations.count,
                   "the day's log did not survive a reload", &problems)
            let stale = PowerObservation(timestamp: clock.value.addingTimeInterval(-31 * 24 * 3_600),
                                         source: .battery, percentage: 50, charging: .notCharging)
            store.ambientPower.append(stale, now: clock.value)
            expect(!store.ambientPower.observations.contains(where: { $0.id == stale.id }),
                   "a reading older than the retention window was kept", &problems)
            let blocked = AmbientPowerLog(directory: folder, writeOverride: { _ in "blocked" })
            let held = PowerObservation(timestamp: clock.value, source: .battery, percentage: 60, charging: .notCharging)
            if case .saved = blocked.append(held, now: clock.value) {
                problems.append("a blocked write reported success")
            }
            expect(blocked.lastError == "blocked" && blocked.observations.contains(where: { $0.id == held.id }),
                   "a reading was lost to a failed write", &problems)
            return problems
        }
    }

    static func duplicateSidecarsFailClosed() -> [String] {
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
}
