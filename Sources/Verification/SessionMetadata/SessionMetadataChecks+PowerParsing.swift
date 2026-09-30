import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func groupedPowerCoverageHardening() -> [String] {
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
            expect(partial?.headline == "Using battery · 78%" && partial?.symbolName == "battery.75percent",
                   "partial grouped evidence lost its factual battery source", &problems)
            expect(partial?.detail?.contains("1 of 2 stretches") == true,
                   "partial grouped evidence did not disclose missing stretch coverage", &problems)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(900),
                source: .battery, percentage: 64, charging: .notCharging,
                boundary: .stretchEnded), for: second)
            partial = store.powerSummary(for: [first, second],
                interval: DateInterval(start: start, duration: 1_200))
            expect(partial?.headline == "Using battery · 78% → 64%"
                   && partial?.symbolName == "battery.75percent",
                   "complete multi-stretch evidence replaced the factual source with a generic headline", &problems)
            expect(partial?.detail?.contains("gaps between stretches are not power coverage") == true,
                   "multi-stretch evidence omitted its coverage-gap qualification", &problems)
            return problems
        }
    }

    struct DuplicateDocument: Codable {
        let version: Int
        let entries: [SessionMetadata]
    }

    static func duplicateMetadataHardening() -> [String] {
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

    static func powerDescriptionParser() -> [String] {
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

        // The charger: read from the battery's registry entry, kept only on
        // external power, and never a zero.
        let chargingWith = PowerSourceMonitor.parse(descriptions: [description(
            state: kIOPSACPowerValue, current: 81, charging: true)], at: moment, boundary: nil,
            adapterWatts: 96)
        let batteryWith = PowerSourceMonitor.parse(descriptions: [description(
            state: kIOPSBatteryPowerValue, current: 78)], at: moment, boundary: nil, adapterWatts: 96)
        expect(chargingWith.adapterWatts == 96, "the charger rating was dropped on external power", &problems)
        expect(batteryWith.adapterWatts == nil, "a stale charger rating was kept on battery", &problems)
        expect(PowerSourceMonitor.adapterWatts(registry: ["AdapterDetails": ["Watts": 96, "Name": "96W USB-C Power Adapter"]]) == 96,
               "a rated adapter was not read from AdapterDetails", &problems)
        expect(PowerSourceMonitor.adapterWatts(registry: ["AdapterDetails": ["Watts": NSNumber(value: 140)]]) == 140,
               "an NSNumber wattage was not read", &problems)
        // Verbatim from an unplugged MacBook: the dictionary stays, the key goes.
        expect(PowerSourceMonitor.adapterWatts(registry: ["AdapterDetails": ["FamilyCode": 0]]) == nil,
               "an unplugged AdapterDetails produced a charger", &problems)
        expect(PowerSourceMonitor.adapterWatts(registry: ["AdapterDetails": ["Watts": 0]]) == nil
               && PowerSourceMonitor.adapterWatts(registry: [:]) == nil,
               "a zero or missing adapter produced a charger", &problems)
        // A sidecar written before the field existed.
        let legacy = Data("""
        {"id":"6F2A1E48-3C34-4B0C-9A4B-0F3D5B1B6C10","timestamp":0,"source":"external","percentage":64,"charging":"charging"}
        """.utf8)
        let decoded = try? JSONDecoder().decode(PowerObservation.self, from: legacy)
        expect(decoded != nil && decoded?.adapterWatts == nil && decoded?.source == .external,
               "a pre-charger sidecar observation no longer decodes", &problems)
        return problems
    }
}
