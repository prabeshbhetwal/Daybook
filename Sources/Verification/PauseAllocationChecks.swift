import Foundation

enum PauseAllocationChecks {
    static let tests: [(String, () -> [String])] = [
        ("Pause spans attribute work to the intervals actually worked", recordAllocation),
        ("Records without pause spans keep their legacy allocation", legacyAllocation),
        ("Inconsistent pause spans fall back to legacy allocation", inconsistentAllocation),
        ("The running session attributes work around a cross-midnight pause", liveAllocation),
        ("Pause spans survive record coding and absent legacy keys", coding)
    ]

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private static func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                           hour: hour, minute: minute))!
    }

    private static func record(pausedSpans: [DateInterval]?) -> SessionRecord {
        let start = date(20, hour: 23)
        let end = date(21, hour: 8, minute: 30)
        return SessionRecord(name: "Cross-midnight work", workType: .deepWork,
                             start: start, end: end, workSeconds: 3_600,
                             pausedSpans: pausedSpans)
    }

    private static func recordAllocation() -> [String] {
        let pause = DateInterval(start: date(20, hour: 23, minute: 30), end: date(21, hour: 8))
        let value = record(pausedSpans: [pause])
        return allocationFailures(value, yesterday: 1_800, today: 1_800,
                                  label: "record allocation")
    }

    private static func legacyAllocation() -> [String] {
        let value = record(pausedSpans: nil)
        let span = value.end.timeIntervalSince(value.start)
        return allocationFailures(value,
                                  yesterday: 3_600 * (3_600 / span),
                                  today: 3_600 * (30_600 / span),
                                  label: "legacy allocation")
    }

    private static func inconsistentAllocation() -> [String] {
        let pause = DateInterval(start: date(20, hour: 23, minute: 30), end: date(21, hour: 7))
        let value = record(pausedSpans: [pause])
        let span = value.end.timeIntervalSince(value.start)
        return allocationFailures(value,
                                  yesterday: 3_600 * (3_600 / span),
                                  today: 3_600 * (30_600 / span),
                                  label: "inconsistent allocation")
    }

    private static func liveAllocation() -> [String] {
        final class Clock {
            var value: Date
            init(_ value: Date) { self.value = value }
        }
        let clock = Clock(date(20, hour: 23))
        let suite = "fc.pause.allocation.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-pause-allocation-\(UUID().uuidString)", isDirectory: true)
        guard let defaults = UserDefaults(suiteName: suite) else {
            return ["Could not create isolated pause-allocation preferences"]
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let engine = SessionEngine(store: PersistenceStore(defaults: defaults),
                                   archive: SessionArchive(directory: directory, now: { clock.value }),
                                   ownBundleID: "fc.pause.allocation", schedulesDwell: false,
                                   now: { clock.value })
        engine.transition(on: .launch)
        clock.value = date(20, hour: 23, minute: 30)
        engine.transition(on: .manualPause)
        clock.value = date(21, hour: 8)
        engine.transition(on: .manualResume)
        clock.value = date(21, hour: 8, minute: 30)
        let actual = engine.elapsedToday(calendar: calendar)
        return abs(actual - 1_800) <= 0.001 ? []
            : ["live allocation: expected 1800.0, got \(actual)"]
    }

    private static func coding() -> [String] {
        let pause = DateInterval(start: date(20, hour: 23, minute: 30), end: date(21, hour: 8))
        let value = record(pausedSpans: [pause])
        guard let encoded = try? JSONEncoder().encode(value),
              let decoded = try? JSONDecoder().decode(SessionRecord.self, from: encoded) else {
            return ["Could not encode and decode a record with pause spans"]
        }
        var failures: [String] = []
        if decoded.pausedSpans != [pause] {
            failures.append("Record coding did not retain pause spans")
        }
        guard var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else {
            return failures + ["Could not remove the pause-span key from record JSON"]
        }
        object.removeValue(forKey: "pausedSpans")
        guard let legacy = try? JSONSerialization.data(withJSONObject: object),
              let decodedLegacy = try? JSONDecoder().decode(SessionRecord.self, from: legacy) else {
            return failures + ["Record JSON without pause spans did not decode"]
        }
        if decodedLegacy.pausedSpans != nil {
            failures.append("Record JSON without pause spans did not decode as legacy data")
        }
        return failures
    }

    private static func allocationFailures(_ value: SessionRecord,
                                           yesterday: TimeInterval,
                                           today: TimeInterval,
                                           label: String) -> [String] {
        let yesterdayActual = value.workSeconds(on: date(20, hour: 12), calendar: calendar)
        let todayActual = value.workSeconds(on: date(21, hour: 12), calendar: calendar)
        var failures: [String] = []
        if abs(yesterdayActual - yesterday) > 0.001 {
            failures.append("\(label) yesterday: expected \(yesterday), got \(yesterdayActual)")
        }
        if abs(todayActual - today) > 0.001 {
            failures.append("\(label) today: expected \(today), got \(todayActual)")
        }
        return failures
    }
}
