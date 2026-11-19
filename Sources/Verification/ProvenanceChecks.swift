import Foundation

/// A session records how it began and who chose its category and name, and an
/// older build reading the same file is unharmed. The engine half (starts,
/// claims, pauses, away answers, relaunch) is in `ProvenanceEngineChecks`.
enum ProvenanceChecks: CheckSuite {

    static let tests: [(String, () -> [String])] = [
        ("A record without provenance keys reads its origin and source from isAuto", legacyRecordsReadByIsAuto),
        ("An origin or source a later build adds is read as the app's, never the person's", unknownValuesReadAsTheApps),
        ("A full record round-trips, and an older build's decode of it keeps every total", oldDecoderKeepsTotals),
        ("The person's rename and category change mark a stored session as theirs, and Undo puts both back", personsEditsMarkProvenance),
    ]

    /// The decode every build before provenance used: these keys only.
    private struct LegacyRecord: Decodable {
        let id: UUID
        let name: String
        let workType: WorkType
        let workSeconds: Double
        let threadID: UUID?
        let isAuto: Bool?
    }

    private static func record(isAuto: Bool = false, workType: WorkType = .deepWork) -> SessionRecord {
        SessionRecord(name: "Parser", workType: workType, start: SelfTest.base,
                      end: SelfTest.base.addingTimeInterval(600), workSeconds: 600, isAuto: isAuto)
    }

    private static func object(of record: SessionRecord) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(record),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func decoded(_ json: [String: Any]) -> SessionRecord? {
        JSONSerialization.isValidJSONObject(json)
            ? (try? JSONSerialization.data(withJSONObject: json)).flatMap { try? JSONDecoder().decode(SessionRecord.self, from: $0) }
            : nil
    }

    private static func legacyRecordsReadByIsAuto() -> [String] {
        var problems: [String] = []
        let manual = object(of: record(isAuto: false))
        let automatic = object(of: record(isAuto: true))
        expect(manual["origin"] == nil && manual["categorySource"] == nil && manual["nameByApp"] == nil,
               "a record without provenance wrote keys: \(manual.keys.sorted())", &problems)
        let readManual = decoded(manual)
        let readAutomatic = decoded(automatic)
        expect(readManual?.effectiveOrigin == .manual, "legacy manual origin read \(String(describing: readManual?.effectiveOrigin))", &problems)
        expect(readManual?.effectiveCategorySource == .user, "legacy manual source read \(String(describing: readManual?.effectiveCategorySource))", &problems)
        expect(readAutomatic?.effectiveOrigin == .automatic, "legacy automatic origin read \(String(describing: readAutomatic?.effectiveOrigin))", &problems)
        expect(readAutomatic?.effectiveCategorySource == .builtIn, "legacy automatic source read \(String(describing: readAutomatic?.effectiveCategorySource))", &problems)
        expect(readAutomatic?.origin == nil && readAutomatic?.categorySource == nil && readAutomatic?.nameByApp == nil,
               "reading a legacy record must not invent stored provenance", &problems)
        return problems
    }

    private static func unknownValuesReadAsTheApps() -> [String] {
        var problems: [String] = []
        for isAuto in [false, true] {
            var json = object(of: record(isAuto: isAuto))
            json["origin"] = "somethingNewer"
            json["categorySource"] = "somethingNewer"
            let read = decoded(json)
            expect(read != nil, "an unknown raw value made the record unreadable (isAuto \(isAuto))", &problems)
            expect(read?.effectiveOrigin == .automatic, "unknown origin read \(String(describing: read?.effectiveOrigin))", &problems)
            expect(read?.effectiveCategorySource == .builtIn, "unknown source read \(String(describing: read?.effectiveCategorySource))", &problems)
        }
        return problems
    }

    private static func oldDecoderKeepsTotals() -> [String] {
        var problems: [String] = []
        let rule = UUID()
        let full = SessionRecord(name: "Coding", workType: .deepWork, start: SelfTest.base,
                                 end: SelfTest.base.addingTimeInterval(900), workSeconds: 840, isAuto: true,
                                 origin: .rule, originRuleID: rule, originRuleName: "Coding rule",
                                 categorySource: .rule, nameByApp: false)
        let rest = SessionRecord(name: "Break", workType: .breakTime, start: SelfTest.base.addingTimeInterval(900),
                                 end: SelfTest.base.addingTimeInterval(1_200), workSeconds: 300)
        let records = [full, rest, record(isAuto: true, workType: .learning)]
        guard let data = try? JSONEncoder().encode(records) else { return ["could not encode records"] }
        let back = try? JSONDecoder().decode([SessionRecord].self, from: data)
        expect(back == records, "records with provenance did not round-trip", &problems)
        guard let old = try? JSONDecoder().decode([LegacyRecord].self, from: data) else {
            return problems + ["an older build's decode could not read a record with provenance keys"]
        }
        func focus(_ values: [(WorkType, Double)]) -> Double {
            values.filter { $0.0.countsAsFocus }.reduce(0) { $0 + $1.1 }
        }
        expect(focus(old.map { ($0.workType, $0.workSeconds) }) == focus(records.map { ($0.workType, $0.workSeconds) }),
               "an older build counts different focus seconds", &problems)
        expect(old.map(\.isAuto) == records.map { Optional($0.isAuto) }, "an older build reads different ownership", &problems)
        expect(old.map(\.id) == records.map(\.id), "an older build reads different ids", &problems)
        return problems
    }

    private static func personsEditsMarkProvenance() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(SelfTest.base.addingTimeInterval(7_200))
            let directory = SelfTest.scratchDirectory()
            let suite = "fc-selftest-provenance-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated preferences"] }
            defer { MemoryDefaults.remove(named: suite) }
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "com.test", schedulesDwell: false, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })

            let thread = UUID(), legacyThread = UUID()
            let start = SelfTest.base
            archive.append(SessionRecord(name: "Coding", workType: .deepWork, start: start,
                                         end: start.addingTimeInterval(600), workSeconds: 600,
                                         threadID: thread, isAuto: true, origin: .automatic,
                                         categorySource: .builtIn, nameByApp: true))
            archive.append(SessionRecord(name: "Old", workType: .deepWork, start: start.addingTimeInterval(700),
                                         end: start.addingTimeInterval(1_300), workSeconds: 600,
                                         threadID: legacyThread, isAuto: true))
            func row(_ id: UUID, _ name: String, at offset: TimeInterval) -> DaySession {
                DaySession(id: id, threadID: id, name: name, workType: .deepWork,
                           start: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset + 600),
                           worked: 600, stretches: 1,
                           spans: [DateInterval(start: start.addingTimeInterval(offset), duration: 600)], isRunning: false)
            }
            func stored(_ id: UUID) -> SessionRecord? { archive.records.first { $0.threadID == id } }

            expect(store.renameSession(row(thread, "Coding", at: 0), to: "Parser"), "the rename was refused", &problems)
            expect(stored(thread)?.nameByApp == false && stored(thread)?.categorySource == .builtIn
                   && stored(thread)?.origin == .automatic,
                   "a rename must clear only nameByApp, got \(String(describing: stored(thread)))", &problems)
            expect(store.undoLastCorrection(), "the rename was not undoable", &problems)
            expect(stored(thread)?.nameByApp == true && stored(thread)?.name == "Coding",
                   "Undo did not put back the app-chosen name flag", &problems)

            expect(store.setWorkType(.learning, for: row(thread, "Coding", at: 0)), "the category change was refused", &problems)
            expect(stored(thread)?.categorySource == .user && stored(thread)?.nameByApp == true
                   && stored(thread)?.origin == .automatic,
                   "a category change must set only the source to user, got \(String(describing: stored(thread)))", &problems)
            expect(store.undoLastCorrection(), "the category change was not undoable", &problems)
            expect(stored(thread)?.categorySource == .builtIn && stored(thread)?.workType == .deepWork,
                   "Undo did not put back the built-in source", &problems)

            expect(!store.setWorkType(.deepWork, for: row(thread, "Coding", at: 0)),
                   "choosing the category it already has must change nothing", &problems)
            expect(stored(thread)?.categorySource == .builtIn, "a no-op category change claimed the source", &problems)

            // A record that never said stays that way through a rename and its Undo.
            expect(store.renameSession(row(legacyThread, "Old", at: 700), to: "Older"), "the legacy rename was refused", &problems)
            expect(stored(legacyThread)?.nameByApp == nil && stored(legacyThread)?.categorySource == nil,
                   "a legacy record gained provenance from a rename", &problems)
            expect(store.undoLastCorrection(), "the legacy rename was not undoable", &problems)
            expect(stored(legacyThread)?.nameByApp == nil && stored(legacyThread)?.name == "Old",
                   "Undo left provenance on a legacy record", &problems)
            return problems
        }
    }
}
