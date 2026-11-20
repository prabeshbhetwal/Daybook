import Foundation

/// A category set not to count toward focus (Phase C, C11) is still a category of ordinary sessions: they can be
/// continued, listed, kept as a choice and merged like any other, and only the focus figures leave them out. Each
/// check here would fail if its site asked "does it count?" where it should ask "is it a break?". The Core-level
/// sites are checked here; the ones that need a store are in `NonCountingStoreChecks`.
enum NonCountingCoreChecks: CheckSuite {
    typealias Fixture = NonCountingFixture
    private static var reading: WorkType { Fixture.reading }

    static let tests: [(String, () -> [String])] = [
        ("A session in a category set not to count can be continued, and is listed among the recent threads",
         continuingAndThreads),
        ("A category set not to count is kept as a quick start and as a learned choice, and splits and merges",
         quickStartsAndMerging),
        ("The day's totals and streaks follow a category's setting the moment the catalogue changes",
         totalsFollowTheCatalogue),
        ("Only a category that counts toward focus is offered for a goal, though one that does not is still startable",
         goalsOfferCountingOnly),
    ]

    private static func stretch(_ name: String, _ type: WorkType, from start: Date, minutes: Double = 60,
                                thread: UUID = UUID()) -> SessionRecord {
        SessionRecord(name: name, workType: type, start: start,
                      end: start.addingTimeInterval(minutes * 60), workSeconds: minutes * 60, threadID: thread)
    }

    private static func continuingAndThreads() -> [String] {
        var problems: [String] = []
        Fixture.withNotCounted {
            let record = stretch("Novel", reading, from: Fixture.Base.at(0, 11))
            let rest = stretch("Lunch", .breakTime, from: Fixture.Base.at(0, 12), minutes: 15)
            let after = record.end.addingTimeInterval(600)
            expect(ContinuationPolicy.isEligible(record, records: [record, rest], active: nil, now: after),
                   "a Reading session could not be continued", &problems)
            expect(!ContinuationPolicy.isEligible(rest, records: [record, rest], active: nil, now: after),
                   "a break could be continued", &problems)
            let index = ContinuationPolicy.Index(records: [record, rest])
            expect(index.latestByThread[record.threadID]?.id == record.id
                   && index.latestByThread[rest.threadID] == nil,
                   "the continuation index lists \(index.latestByThread.count) threads, not just Reading's", &problems)
            let key = ContinuationPolicy.activityKey(name: record.name, workType: reading)
            expect(index.latestByActivity[key]?.id == record.id, "the continuation index lost Reading's activity",
                   &problems)

            let clock = TestClock(after)
            let archive = SelfTest.makeArchive(clock, records: [record, rest], calendar: Fixture.Base.calendar)
            let stats = ThreadStats(sessions: archive, calendar: Fixture.Base.calendar, now: { clock.value })
            expect(stats.threads(on: after, running: nil).map(\.threadID) == [record.threadID],
                   "today's threads read \(stats.threads(on: after, running: nil).map(\.name)), not Novel alone",
                   &problems)
            expect(stats.continuationThreads(running: nil).map(\.threadID) == [record.threadID],
                   "the archive-wide threads read \(stats.continuationThreads(running: nil).map(\.name)), not Novel alone",
                   &problems)
        }
        return problems
    }

    private static func quickStartsAndMerging() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-noncounting-core-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no in-memory preferences"] }
        defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
        let persistence = PersistenceStore(defaults: defaults)
        persistence.workTypeDefinitions = [Fixture.notCounted()]
        expect(!reading.countsAsFocus, "Reading still counted toward focus", &problems)

        let novel = QuickStart(id: "novel", name: "Novel", workType: reading)
        let rest = QuickStart(id: "lunch", name: "Lunch", workType: .breakTime)
        expect(ActivityChoices.merging([novel, rest], []).map(\.name) == ["Novel"],
               "the quick starts read \(ActivityChoices.merging([novel, rest], []).map(\.name)), not Novel alone",
               &problems)
        expect(SavedActivities.normalised([SavedActivity(name: "Novel", workType: reading)]).count == 1,
               "a Reading activity could not be pinned", &problems)

        persistence.rememberCategoryChoice(reading, for: "test.reader")
        persistence.rememberCategoryChoice(.breakTime, for: "test.reader")
        expect(persistence.categoryChoices["test.reader"] == [reading.rawValue],
               "the learned choices read \(persistence.categoryChoices["test.reader"] ?? []), not Reading alone",
               &problems)

        let head = stretch("Novel", reading, from: Fixture.Base.at(0, 11), minutes: 30)
        let tail = stretch("Novel", reading, from: Fixture.Base.at(0, 11, 30), minutes: 30)
        let joined = SessionRecord.merged(head: head, tail: tail)
        expect(joined?.end == tail.end && joined?.workSeconds == 3_600 && joined?.workType == reading,
               "two Reading halves merged to \(String(describing: joined?.workSeconds)) seconds", &problems)
        expect(SessionRecord.merged(head: head, tail: stretch("Lunch", .breakTime, from: tail.start)) == nil,
               "a break was merged into a session", &problems)
        let rest30 = stretch("Lunch", .breakTime, from: Fixture.Base.at(0, 12), minutes: 30)
        expect(head.canSplit(at: Fixture.Base.at(0, 11, 15)) && !rest30.canSplit(at: Fixture.Base.at(0, 12, 15)),
               "a Reading session could not be split, or a break could", &problems)
        return problems
    }

    /// The archive keeps the daily totals and both streaks until a record changes. Whether a record counts is
    /// read from the catalogue, so a change there must drop them as a record write does.
    private static func totalsFollowTheCatalogue() -> [String] {
        var problems: [String] = []
        defer { WorkTypeCatalog.shared.apply(customisations: []) }
        let clock = TestClock(Fixture.Base.at(0, 19))
        let long = stretch("Novel", reading, from: Fixture.Base.at(0, 10), minutes: 120)
        let archive = SelfTest.makeArchive(clock, records: [long], calendar: Fixture.Base.calendar)
        archive.streakMinimum = 3_600
        func figures() -> String {
            "\(archive.currentStreak()) current, \(archive.bestStreak()) best, "
                + "\(archive.weekBars().last?.minutes ?? -1) minutes"
        }
        expect(figures() == "1 current, 1 best, 120 minutes", "with Reading counting the day read \(figures())", &problems)
        WorkTypeCatalog.shared.apply(customisations: [Fixture.notCounted()])
        expect(figures() == "0 current, 0 best, 0 minutes",
               "after Reading was set not to count, with no record written, the day read \(figures())", &problems)
        WorkTypeCatalog.shared.apply(customisations: [])
        expect(figures() == "1 current, 1 best, 120 minutes",
               "after Reading counted again the day read \(figures())", &problems)
        return problems
    }

    private static func goalsOfferCountingOnly() -> [String] {
        var problems: [String] = []
        Fixture.withNotCounted {
            expect(WorkType.startable.contains(reading), "Reading was not startable", &problems)
            expect(!WorkType.goalable.contains(reading), "Reading, which does not count, was offered for a goal",
                   &problems)
            expect(WorkType.goalable.contains(.deepWork) && !WorkType.goalable.contains(.breakTime),
                   "the goals offered were \(WorkType.goalable.map(\.rawValue))", &problems)
        }
        expect(WorkType.goalable.contains(.learning) && WorkType.goalable == WorkType.startable,
               "with every category counting, the goals offered were \(WorkType.goalable.map(\.rawValue))", &problems)
        return problems
    }
}
