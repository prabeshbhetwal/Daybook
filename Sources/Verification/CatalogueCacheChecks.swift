import Foundation

/// A past day read in Story, on the rail or in Insight is kept until the evidence behind it changes. Whether a
/// category counts toward focus is read from the catalogue, which an edit in Settings changes with no record
/// written, so each of those readings must also notice the catalogue changing; the archive's own totals already do
/// (`NonCountingCoreChecks`).
enum CatalogueCacheChecks: CheckSuite {
    typealias Base = FocusPropertyFixture

    static let tests: [(String, () -> [String])] = [
        ("A past day read before a category stops counting toward focus is read afresh by Story, the rail and Insight",
         pastDayFollowsTheCatalogue),
    ]

    private static func pastDayFollowsTheCatalogue() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Base.at(0, 19))
            let suite = "fc-selftest-cataloguecache-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            let persistence = PersistenceStore(defaults: defaults)
            defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
            // Through the store, as Settings applies it. One day back holds half an hour of Meetings and an hour of
            // Reading, and an app is in front all day, so the goal's credit is the focus work and nothing else.
            persistence.workTypeDefinitions = [Base.readingDefinition()]
            let yesterday = Base.day(-1)
            let usage = SelfTest.makeUsageArchive(clock, sessions: [
                AppUsageSession(bundleID: "test.cataloguecache", appName: "Fixture",
                                start: Base.at(-1, 8), end: Base.at(-1, 18))])
            let engine = SessionEngine(store: persistence,
                                       archive: SelfTest.makeArchive(clock, records: Base.records(),
                                                                     calendar: Base.calendar),
                                       ownBundleID: "fc.cataloguecache.test", schedulesDwell: false,
                                       now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: AppUsageTracker(archive: usage, ownBundleID: "fc.cataloguecache.test",
                                                  idle: .disabled, now: { clock.value }), usage: usage)

            func read(_ when: String, focus: TimeInterval, reading: TimeInterval) {
                SelfTest.expectClose(store.storyDayProjection(on: yesterday).focused, focus,
                                     "\(when), Story's focus for the day", &problems)
                SelfTest.expectClose(store.storyDayProjection(on: yesterday).goalCredit, focus,
                                     "\(when), Story's goal credit for the day", &problems)
                SelfTest.expectClose(store.storyRailDay(on: yesterday).goal.achieved, focus,
                                     "\(when), the rail's goal credit for the day", &problems)
                SelfTest.expectClose(store.storyRailDay(on: yesterday).creditByCategory[Base.reading.rawValue] ?? 0,
                                     reading, "\(when), the rail's credit for Reading", &problems)
                SelfTest.expectClose(store.insightReading(scope: .day, anchoredAt: yesterday, limit: 1)
                                        .periods.first?.focused ?? -1, focus,
                                     "\(when), Insight's focus for the day", &problems)
            }
            read("with Reading counting", focus: 5_400, reading: 3_600)
            let before = store.evidenceRevision
            persistence.workTypeDefinitions = [Base.readingDefinition { $0.countsTowardFocus = false }]
            expect(store.evidenceRevision != before, "the evidence did not change with the catalogue", &problems)
            // The rest of History reads a changed catalogue as a change to any day, not a patch of the live tail.
            expect(!before.sameArchive(as: store.evidenceRevision),
                   "a change to the catalogue was read as app use alone", &problems)
            read("once Reading no longer counts", focus: 1_800, reading: 0)
            return problems
        }
    }
}
