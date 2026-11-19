import Foundation

/// The store around the corrections file: fed only by the person's own category changes, and offering
/// them back as a read, which changes no record until the person takes the offer.
enum CorrectionsStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Filing an ended session under another category is remembered and offered to the next one of its kind",
         filingIsRemembered),
        ("A suggestion changes no record until the person takes it, and then it is theirs", suggestionChangesNothing),
        ("Only a category Daybook chose is offered a replacement", onlyBuiltInIsOffered),
        ("A retired category, the category already filed and a running session are never suggested", noStaleOffer),
        ("Stretches of one kind count as one choice, and a session without a stored shape is not remembered",
         oneChoicePerKind),
    ]

    static let typical = CategoryCorrectionChecks.fingerprint()

    @MainActor
    static func make(journal: (() -> String?)? = nil) -> (store: SessionStore, clock: TestClock, suite: String) {
        let suite = "fc-selftest-corrections-\(UUID().uuidString)"
        let clock = TestClock(SelfTest.anchoredNow())
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
        let persistence = PersistenceStore(defaults: MemoryDefaults.suite(named: suite) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive, ownBundleID: "com.test",
                                   schedulesDwell: false, correctionWriteOverride: journal, now: { clock.value })
        return (SessionStore(engine: engine, now: { clock.value }), clock, suite)
    }

    /// An ended session of ten minutes with `shape` stored for its record, and the row a day shows for it.
    @MainActor
    static func ended(_ store: SessionStore, _ clock: TestClock, shape: ActivityFingerprint? = typical,
                              begin: (SessionEngine) -> Void) -> DaySession? {
        begin(store.engine)
        clock.advance(600)
        store.stop()
        clock.advance(1_800)
        guard let record = store.engine.archive.records.last else { return nil }
        keep(shape, for: record, in: store)
        return ActivitySnapshotChecks.daySession([record])
    }

    @MainActor
    static func automatic(_ name: String, _ type: WorkType = .deepWork) -> (SessionEngine) -> Void {
        { $0.start(workType: type, intent: name, isAuto: true, nameByApp: true) }
    }

    @MainActor
    static func keep(_ shape: ActivityFingerprint?, for record: SessionRecord, in store: SessionStore) {
        guard let shape else { return }
        let bounds = DateInterval(start: record.start, end: record.end)
        store.metadataArchive.saveActivityShape(
            SessionActivityShape(algorithmVersion: ActivityConstants.algorithmVersion, fidelity: .beats,
                                 bounds: bounds, countedSeconds: bounds.duration, signals: [], phases: [],
                                 depth: nil, label: .activity(.coding), credited: [AppPurpose.coding.rawValue: bounds.duration],
                                 fingerprint: shape, splitCandidates: []), for: record.id)
    }

    @MainActor
    static func stored(_ store: SessionStore) -> CategoryCorrections {
        CorrectionsStore(directory: store.engine.archive.dataDirectoryURL).corrections
    }

    @MainActor
    static func record(_ session: DaySession, in store: SessionStore) -> SessionRecord? {
        store.engine.archive.records.first { session.recordIDs.contains($0.id) }
    }

    private static func filingIsRemembered() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let first = ended(store, clock, begin: automatic("Parser")),
                  let second = ended(store, clock, begin: automatic("Router")) else { return ["no sessions were made"] }
            expect(store.correctionSuggestion(for: second) == nil, "a category was offered before any choice", &problems)
            expect(store.setWorkType(.learning, for: first),
                   "the category change was refused: \(store.correctionError ?? "no reason")", &problems)
            expect(store.correctionSuggestion(for: second) == .learning,
                   "the next session of its kind was not offered Learning", &problems)
            if let id = record(second, in: store)?.id {
                expect(store.correctionSuggestion(for: id) == .learning, "the record's own offer differs", &problems)
            }
            let entry = stored(store).entries.first
            expect(entry?.chosen == "learning" && entry?.vetoed == ["deepWork"] && entry?.count == 1,
                   "the file holds \(String(describing: entry))", &problems)
            expect(SessionReport.make(for: second, store: store).suggestion == .learning
                   && SessionReport.make(for: first, store: store).suggestion == nil,
                   "the report did not carry the offer for the next session and none for the one filed", &problems)
            expect(second.recategorised(as: second.workType) == second
                   && second.recategorised(as: .learning).workType == .learning,
                   "a session shown under its new category changed more than the category", &problems)
            return problems
        }
    }

    private static func suggestionChangesNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let first = ended(store, clock, begin: automatic("Parser")),
                  let second = ended(store, clock, begin: automatic("Router")) else { return ["no sessions were made"] }
            store.setWorkType(.learning, for: first)
            let before = store.engine.archive.records, revision = store.engine.archive.revision
            expect(store.correctionSuggestion(for: second) == .learning, "no offer to test", &problems)
            store.refresh()
            expect(store.engine.archive.records == before && store.engine.archive.revision == revision,
                   "an offer rewrote a stored record", &problems)
            expect(record(second, in: store)?.effectiveCategorySource == .builtIn,
                   "an offer changed where a category came from", &problems)
            expect(store.setWorkType(.learning, for: second), "taking the offer was refused", &problems)
            let taken = record(second, in: store)
            expect(taken?.workType == .learning && taken?.effectiveCategorySource == .user,
                   "a taken offer is \(String(describing: taken))", &problems)
            expect(stored(store).entries.first?.count == 2, "taking it was not counted", &problems)
            expect(store.correctionSuggestion(for: second) == nil, "an offer stayed on the person's own choice", &problems)
            return problems
        }
    }

    private static func onlyBuiltInIsOffered() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let first = ended(store, clock, begin: automatic("Parser")) else { return ["no session was made"] }
            store.setWorkType(.learning, for: first)
            let manual = ended(store, clock) { $0.start(workType: .deepWork, intent: "Mine") }
            let action = ActivityAutomaticAction(ruleID: UUID(), ruleName: "Coding", workType: .deepWork,
                                                 evidence: DateInterval(start: clock.value.addingTimeInterval(-300),
                                                                        end: clock.value),
                                                 reason: "Coding evidence", ruleVersion: 1, generation: 1,
                                                 expectedRecordID: nil)
            let ruled = ended(store, clock) { _ = $0.startAutomatically(action: action) }
            let sources = [manual, ruled].map { $0.flatMap { record($0, in: store)?.effectiveCategorySource } }
            expect(sources == [.user, .rule], "the fixtures carry sources \(sources)", &problems)
            for session in [manual, ruled].compactMap({ $0 }) {
                expect(store.correctionSuggestion(for: session) == nil,
                       "a category the person or a rule chose was offered a replacement", &problems)
            }
            return problems
        }
    }

    private static func noStaleOffer() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make()
            defer { MemoryDefaults.remove(named: suite) }
            // Written before the store first reads the file: a choice of a category since retired.
            _ = CorrectionsStore(directory: store.engine.archive.dataDirectoryURL)
                .record(fingerprint: typical, chosen: "custom.gone", vetoed: nil, at: clock.value)
            guard let gone = ended(store, clock, begin: automatic("Parser")) else { return ["no session was made"] }
            expect(store.correctionSuggestion(for: gone) == nil, "a retired category was offered", &problems)

            let (other, otherClock, otherSuite) = make()
            defer { MemoryDefaults.remove(named: otherSuite) }
            guard let filed = ended(other, otherClock, begin: automatic("Parser")),
                  let same = ended(other, otherClock, begin: automatic("Router", .learning)) else {
                return problems + ["no sessions were made"]
            }
            other.setWorkType(.learning, for: filed)
            expect(other.correctionSuggestion(for: same) == nil, "a session was offered the category it is in", &problems)
            guard let third = ended(other, otherClock, begin: automatic("Doctor")),
                  let reread = record(third, in: other) else { return problems + ["no third session"] }
            let running = ActivitySnapshotChecks.daySession([reread], running: true)
            expect(other.correctionSuggestion(for: third) == .learning && other.correctionSuggestion(for: running) == nil,
                   "a running session was offered a category", &problems)
            return problems
        }
    }

    private static func oneChoicePerKind() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make()
            defer { MemoryDefaults.remove(named: suite) }
            let thread = UUID(), start = clock.value
            let stretches = (0..<2).map { step -> SessionRecord in
                let begin = start.addingTimeInterval(TimeInterval(step) * 1_200)
                return SessionRecord(name: "Parser", workType: .deepWork, start: begin,
                                     end: begin.addingTimeInterval(600), workSeconds: 600, threadID: thread,
                                     isAuto: true, origin: .automatic, categorySource: .builtIn)
            }
            for stretch in stretches {
                _ = store.engine.archive.append(stretch)
                keep(typical, for: stretch, in: store)
            }
            let session = ActivitySnapshotChecks.daySession(stretches)
            expect(store.setWorkType(.learning, for: session), "the category change was refused", &problems)
            let entries = stored(store).entries
            expect(entries.count == 1 && entries.first?.count == 1,
                   "two stretches of one kind were counted as \(entries.map(\.count))", &problems)

            let (bare, bareClock, bareSuite) = make()
            defer { MemoryDefaults.remove(named: bareSuite) }
            guard let plain = ended(bare, bareClock, shape: nil, begin: automatic("Parser")) else {
                return problems + ["no session was made"]
            }
            expect(bare.setWorkType(.learning, for: plain), "the category change was refused", &problems)
            expect(stored(bare).entries.isEmpty
                   && !FileManager.default.fileExists(
                       atPath: bare.engine.archive.dataDirectoryURL.appendingPathComponent("corrections.json").path),
                   "a session with no stored shape was remembered", &problems)
            return problems
        }
    }
}
