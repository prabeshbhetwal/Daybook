import Foundation

/// Splitting and joining sessions through the store: one correction each, nothing moved in any total, and
/// Undo in the order things were done (spec section 4, plan Task 5).
enum SplitStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A split, a join and each Undo leave the day's total, the goal and the streak exactly where they were",
         totalsNeverMove),
        ("A split is one correction that Undo takes back whole, and the tail alone offers Merge Back",
         splitIsOneUndoEntry),
        ("Merging back is one correction too, and Undo gives the two halves back with their link", mergeIsOneUndoEntry),
        ("Merge Back is refused once either half was renamed or recategorised, and Undo then runs newest first",
         editsBlockMergeAndUndoRunsInOrder),
    ]

    struct Rig {
        let store: SessionStore
        let clock: TestClock
        let directory: URL
        let suite: String
    }

    /// A store over `directory`; given the same directory, suite and clock again it is the same history
    /// after a relaunch.
    @MainActor
    static func rig(directory: URL = SelfTest.scratchDirectory(), suite: String? = nil, clock: TestClock? = nil,
                    writeOverride: (([SessionRecord]) -> String?)? = nil,
                    journal: (() -> String?)? = nil) -> Rig {
        let suite = suite ?? "fc-selftest-split-\(UUID().uuidString)"
        let clock = clock ?? TestClock(SelfTest.anchoredNow())
        let archive = SessionArchive(directory: directory, now: { clock.value }, writeOverride: writeOverride)
        let engine = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: suite) ?? .standard),
                                   archive: archive, ownBundleID: "com.test", schedulesDwell: false,
                                   correctionWriteOverride: journal, now: { clock.value })
        return Rig(store: SessionStore(engine: engine, now: { clock.value }), clock: clock, directory: directory,
                   suite: suite)
    }

    /// Two hours ago to one hour ago today: 3000 counted seconds with ten paused minutes in the second quarter.
    @MainActor
    static func ended(_ rig: Rig, origin: SessionOrigin = .automatic) -> SessionRecord {
        let start = rig.clock.value.addingTimeInterval(-7_200)
        return SessionRecord(name: "Report", workType: .deepWork, start: start, end: start.addingTimeInterval(3_600),
                             workSeconds: 3_000, detectedApp: "com.apple.dt.Xcode", threadID: UUID(),
                             isAuto: origin != .manual,
                             pausedSpans: [DateInterval(start: start.addingTimeInterval(1_200), duration: 600)],
                             plannedLength: nil, origin: origin,
                             originRuleID: origin == .rule ? UUID() : nil, originRuleName: origin == .rule ? "Morning writing" : nil,
                             categorySource: origin == .automatic ? .builtIn : origin == .rule ? .rule : .user,
                             nameByApp: origin == .automatic)
    }

    /// Yesterday's two hours, so a streak and a best streak have something to say.
    @MainActor
    static func yesterday(_ rig: Rig) -> SessionRecord {
        let start = rig.clock.value.addingTimeInterval(-86_400 - 7_200)
        return SessionRecord(name: "Earlier", workType: .deepWork, start: start, end: start.addingTimeInterval(7_200),
                             workSeconds: 7_200, threadID: UUID(), isAuto: false, origin: .manual, categorySource: .user)
    }

    @MainActor
    static func seed(_ rig: Rig, _ records: [SessionRecord]) {
        for record in records { _ = rig.store.engine.archive.append(record) }
        rig.store.refresh()
    }

    static func choice(_ type: WorkType = .deepWork, source: DecisionSource = .correction) -> SplitTail {
        SplitTail(name: "Video", workType: type, source: source, nameByApp: true)
    }

    @MainActor
    static func halves(of record: SessionRecord, in store: SessionStore) -> (head: SessionRecord, tail: SessionRecord)? {
        let records = store.engine.archive.records
        guard let head = records.first(where: { $0.id == record.id }),
              let tail = records.first(where: { $0.id != record.id && $0.start == head.end && $0.end == record.end })
        else { return nil }
        return (head, tail)
    }

    @MainActor
    static func row(_ record: SessionRecord) -> DaySession { ActivitySnapshotChecks.daySession([record]) }

    /// Everything a person reads a day's work from, so a split that moved a second shows.
    struct Figures: Equatable {
        let today: TimeInterval
        let goal: GoalProgress?
        let streak: Int
        let best: Int
        let days: [TimeInterval]
    }

    @MainActor
    static func figures(_ store: SessionStore, _ clock: TestClock, withGoal: Bool = true) -> Figures {
        Figures(today: store.todayTotal, goal: withGoal ? store.goal : nil,
                streak: store.streak, best: store.streakBest,
                days: (0..<3).map { store.engine.archive.workSeconds(on: clock.value.addingTimeInterval(-86_400 * Double($0))) })
    }

    private static func totalsNeverMove() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for category in [WorkType.deepWork, .learning] {
                let rig = rig()
                defer { MemoryDefaults.remove(named: rig.suite) }
                let record = ended(rig)
                seed(rig, [yesterday(rig), record])
                let store = rig.store
                // A tail filed elsewhere moves time between categories, so the goal is read only when it stays.
                let withGoal = category == .deepWork
                let before = figures(store, rig.clock, withGoal: withGoal)
                expect(before.today > 0 && before.streak > 0, "the fixture shows no work to hold still", &problems)
                let cut = record.start.addingTimeInterval(2_400)
                guard store.splitSession(recordID: record.id, at: cut, tail: choice(category)),
                      let split = halves(of: record, in: store) else {
                    problems.append("the split was refused: \(store.correctionError ?? "no reason")"); continue
                }
                expect(split.head.workSeconds + split.tail.workSeconds == record.workSeconds,
                       "the halves hold \(split.head.workSeconds + split.tail.workSeconds), not \(record.workSeconds)", &problems)
                expect(figures(store, rig.clock, withGoal: withGoal) == before, "a split moved a figure", &problems)
                expect(store.mergeBack(tailID: split.tail.id), "merge back after \(category) was refused: \(store.correctionError ?? "")", &problems)
                expect(figures(store, rig.clock, withGoal: withGoal) == before, "a merge moved a figure", &problems)
                expect(store.undoLastCorrection(), "undo of the merge failed: \(store.correctionError ?? "")", &problems)
                expect(figures(store, rig.clock, withGoal: withGoal) == before, "undoing the merge moved a figure", &problems)
                expect(store.undoLastCorrection(), "undo of the split failed: \(store.correctionError ?? "")", &problems)
                expect(figures(store, rig.clock, withGoal: withGoal) == before, "undoing the split moved a figure", &problems)
                expect(store.engine.archive.records.contains(record) && store.engine.archive.records.count == 2,
                       "the archive is not what it began as", &problems)
            }
            problems += crossesMidnight()
            return problems
        }
    }

    /// A session over midnight is two days' work: the cut may fall on either side without moving either day.
    @MainActor
    private static func crossesMidnight() -> [String] {
        var problems: [String] = []
        let rig = rig()
        defer { MemoryDefaults.remove(named: rig.suite) }
        let midnight = Calendar.current.startOfDay(for: rig.clock.value.addingTimeInterval(-3 * 86_400))
        let record = SessionRecord(name: "Night shift", workType: .deepWork, start: midnight.addingTimeInterval(-1_800),
                                   end: midnight.addingTimeInterval(5_400), workSeconds: 6_000, threadID: UUID(),
                                   isAuto: false, pausedSpans: [DateInterval(start: midnight.addingTimeInterval(2_400),
                                                                              end: midnight.addingTimeInterval(3_600))],
                                   origin: .manual, categorySource: .user)
        seed(rig, [record])
        let days = [midnight.addingTimeInterval(-3_600), midnight.addingTimeInterval(3_600)]
        let before = days.map { rig.store.engine.archive.workSeconds(on: $0) }
        expect(before.allSatisfy { $0 > 0 }, "the fixture does not cross midnight: \(before)", &problems)
        for cut in [midnight.addingTimeInterval(-600), midnight.addingTimeInterval(1_200), midnight.addingTimeInterval(4_000)] {
            guard rig.store.splitSession(recordID: record.id, at: cut, tail: choice(.deepWork, source: .user)) else {
                problems.append("a cut at \(cut) was refused: \(rig.store.correctionError ?? "")"); continue
            }
            let after = days.map { rig.store.engine.archive.workSeconds(on: $0) }
            expect(zip(before, after).allSatisfy { abs($0 - $1) < 1e-6 }, "a cut at \(cut) moved the days: \(before) to \(after)", &problems)
            expect(rig.store.undoLastCorrection(), "undo of a cut at \(cut) failed", &problems)
        }
        return problems
    }

    private static func splitIsOneUndoEntry() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let record = ended(rig)
            seed(rig, [record])
            let store = rig.store
            expect(store.corrections.isEmpty && !store.canUndoCorrection, "the fixture began with a correction", &problems)
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: choice()),
                  let (head, tail) = halves(of: record, in: store) else { return ["the split was refused"] }
            expect(store.corrections.count == 1 && store.lastCorrection?.restructure == .split,
                   "a split is not one correction: \(store.corrections.map(\.correction))", &problems)
            expect(store.canUndoCorrection && store.editUndoKind == .split("Report"),
                   "Edit > Undo says \(String(describing: store.editUndoKind))", &problems)
            expect(store.canMergeBack(recordID: tail.id) && !store.canMergeBack(recordID: head.id),
                   "Merge Back is offered on the wrong half", &problems)
            expect(store.sessionMetadata(for: tail.id)?.splitFrom?.head == head.id, "the tail carries no link", &problems)
            expect(tail.origin == .automatic && tail.categorySource == .correction && tail.threadID != head.threadID,
                   "the tail's provenance is wrong: \(tail)", &problems)
            expect(store.undoLastCorrection(), "Undo was refused: \(store.correctionError ?? "")", &problems)
            expect(store.engine.archive.records == [record], "Undo did not give back the one record", &problems)
            expect(store.corrections.isEmpty && store.sessionMetadata(for: tail.id)?.splitFrom == nil
                   && !store.canMergeBack(recordID: tail.id), "Undo left its link or its entry behind", &problems)
            return problems
        }
    }

    private static func mergeIsOneUndoEntry() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let record = ended(rig)
            seed(rig, [record])
            let store = rig.store
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: choice()),
                  let (head, tail) = halves(of: record, in: store) else { return ["the split was refused"] }
            expect(store.mergeBack(tailID: tail.id), "Merge Back was refused: \(store.correctionError ?? "")", &problems)
            expect(store.engine.archive.records == [record], "the merge did not give back the one record", &problems)
            expect(store.corrections.count == 2 && store.lastCorrection?.restructure == .merge
                   && store.editUndoKind == .merge("Report"), "a merge is not one more correction", &problems)
            expect(store.undoLastCorrection(), "Undo of the merge was refused: \(store.correctionError ?? "")", &problems)
            expect(Set(store.engine.archive.records.map(\.id)) == [head.id, tail.id]
                   && store.engine.archive.records.contains(head) && store.engine.archive.records.contains(tail),
                   "Undo did not give the two halves back as they were", &problems)
            expect(store.canMergeBack(recordID: tail.id), "the halves lost their link in the round trip", &problems)
            expect(store.undoLastCorrection() && store.engine.archive.records == [record],
                   "the second Undo did not give back the one record", &problems)
            return problems
        }
    }

    private static func editsBlockMergeAndUndoRunsInOrder() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let record = ended(rig)
            seed(rig, [record])
            let store = rig.store
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: choice()),
                  let (head, tail) = halves(of: record, in: store), let splitID = store.lastCorrection?.id
            else { return ["the split was refused"] }
            // Renaming the tail, then the head, then recategorising each: every one ends the offer.
            let edits: [(String, () -> Bool)] = [
                ("rename of the tail", { store.renameSession(row(tail), to: "Clips") }),
                ("rename of the head", { store.renameSession(row(head), to: "Draft") }),
                ("category of the tail", { store.setWorkType(.learning, for: row(tail)) }),
                ("category of the head", { store.setWorkType(.learning, for: row(head)) }),
            ]
            for (label, edit) in edits {
                expect(edit(), "the \(label) was refused: \(store.correctionError ?? "")", &problems)
                expect(!store.canMergeBack(recordID: tail.id), "Merge Back stayed after the \(label)", &problems)
                let kept = store.engine.archive.records
                expect(!store.mergeBack(tailID: tail.id) && store.engine.archive.records == kept,
                       "a merge went ahead after the \(label)", &problems)
                expect(!store.undoCorrection(expectedID: splitID) && store.engine.archive.records == kept,
                       "the older split was undone under the \(label)", &problems)
                expect(store.undoLastCorrection() && store.canMergeBack(recordID: tail.id),
                       "undoing the \(label) did not bring Merge Back back", &problems)
            }
            expect(store.undoLastCorrection() && store.engine.archive.records == [record],
                   "the last Undo did not give back the one record: \(store.engine.archive.records.count) left", &problems)
            return problems
        }
    }
}
