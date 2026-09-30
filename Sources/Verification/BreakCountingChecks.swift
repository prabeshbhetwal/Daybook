import Foundation

/// What the story's menus offer: the sessions a recorded break can be
/// counted into, and the recent names beside the activity field.
enum BreakCountingChecks {
    static let tests: [(String, () -> [String])] = [
        ("A break offers only its own day's sessions, nearest first, each with its time", sameDayTargets),
        ("Recent activities are names a person typed, never a rule's or a category's", typedRecentsOnly)
    ]

    private static func typedRecentsOnly() -> [String] {
        MainActor.assumeIsolated {
            let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 18))!
            func record(_ name: String, auto: Bool, hoursAgo: Double) -> SessionRecord {
                let end = now.addingTimeInterval(-hoursAgo * 3_600)
                return SessionRecord(name: name, workType: .deepWork, start: end.addingTimeInterval(-1_800),
                                     end: end, workSeconds: 1_800, isAuto: auto)
            }
            let records = [record("Coding", auto: true, hoursAgo: 1),
                           record(WorkType.deepWork.displayName, auto: false, hoursAgo: 2),
                           record("Parser refactor", auto: false, hoursAgo: 3)]
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fc-recents-\(UUID())")
            let suite = "fc.recents.\(UUID())"
            defer {
                UserDefaults.standard.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: directory)
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(records),
                  (try? data.write(to: directory.appendingPathComponent("sessions.json"))) != nil,
                  let defaults = UserDefaults(suiteName: suite) else { return ["could not write the fixture archive"] }
            let persistence = PersistenceStore(defaults: defaults)
            // A category's name submitted from the field before this rule.
            persistence.rememberActivity(name: WorkType.deepWork.displayName, workType: .deepWork)
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { now }),
                                       ownBundleID: "fc.recents.test", schedulesDwell: false, now: { now })
            let store = SessionStore(engine: engine, schedulesTicker: false,
                                     applicationIsRunning: { _ in false }, activateApplication: { _, _ in },
                                     now: { now })
            store.refresh()
            let names = store.recentActivities.map(\.name)
            return names == ["Parser refactor"] ? [] : ["recent activities read \(names), not only the typed Parser refactor"]
        }
    }

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
