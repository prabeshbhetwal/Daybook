import Foundation

/// "Change how this counts" on a recorded break: the sessions it offers to
/// count the break into.
enum BreakCountingChecks {
    static let tests: [(String, () -> [String])] = [
        ("A break offers only its own day's sessions, nearest first, each with its time", sameDayTargets)
    ]

    private static func sameDayTargets() -> [String] {
        MainActor.assumeIsolated {
            let calendar = Calendar.current
            let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
            func at(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
                calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: day)!
            }
            let coding = UUID(), browsing = UUID()
            let morning = SessionRecord(name: "Coding", workType: .deepWork, start: at(9, 0), end: at(10, 0),
                                        workSeconds: 3_600, threadID: coding)
            let afternoon = SessionRecord(name: "Coding", workType: .deepWork, start: at(13, 0), end: at(14, 0),
                                          workSeconds: 3_600, threadID: coding)
            let before = SessionRecord(name: "Browsing", workType: .deepWork, start: at(14, 24), end: at(15, 11),
                                       workSeconds: 2_820, threadID: browsing)
            let driving = SessionRecord(name: "Driving", workType: .breakTime, start: at(15, 11), end: at(15, 36),
                                        workSeconds: 1_500)
            let yesterday = SessionRecord(name: "Coding", workType: .deepWork, start: at(9, 0, dayOffset: -1),
                                          end: at(10, 0, dayOffset: -1), workSeconds: 3_600)

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fc-break-counting-\(UUID())")
            let suite = "fc.break-counting.\(UUID())"
            defer {
                UserDefaults.standard.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: directory)
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode([yesterday, morning, afternoon, before, driving]),
                  (try? data.write(to: directory.appendingPathComponent("sessions.json"))) != nil,
                  let defaults = UserDefaults(suiteName: suite) else { return ["could not write the fixture archive"] }
            let archive = SessionArchive(directory: directory, now: { at(18, 0) })
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "fc.break-counting.test", schedulesDwell: false, now: { at(18, 0) })
            let store = SessionStore(engine: engine, schedulesTicker: false,
                                     applicationIsRunning: { _ in false }, activateApplication: { _, _ in },
                                     now: { at(18, 0) })
            let rest = RestEntry(id: driving.id, name: driving.name, start: driving.start, end: driving.end)

            var failures: [String] = []
            let targets = store.legacyFocusTargets(for: rest)
            if targets.map(\.id) != [before.id, afternoon.id] {
                failures.append("offered \(targets.map { "\($0.name) \($0.start)" }), not Browsing then the afternoon's Coding")
            }
            let labels = targets.map(SessionStore.legacyFocusTargetLabel)
            if Set(labels).count != labels.count || !(labels.first?.hasPrefix("Browsing · Deep work · 2:24") ?? false) {
                failures.append("labels did not tell sessions apart by time: \(labels)")
            }
            return failures
        }
    }
}
