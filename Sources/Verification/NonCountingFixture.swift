import Foundation

/// An archive, an engine and a store in which "Reading" is a category set not to count toward focus. Reading's
/// session is an ordinary one that adds no focus: every site that asks "is this a break?" must find it startable,
/// continuable and searchable, and every figure that asks "does this count?" must find it adds nothing.
final class NonCountingFixture {
    typealias Base = FocusPropertyFixture
    static var reading: WorkType { Base.reading }

    /// Reading, set not to count toward focus.
    static func notCounted() -> WorkTypeDefinition { Base.readingDefinition { $0.countsTowardFocus = false } }

    /// Runs `body` with the shared catalogue holding Reading as not counting, then puts it back as shipped.
    static func withNotCounted<T>(_ body: () -> T) -> T { Base.withCatalogue([notCounted()], body) }

    /// Today: an hour of Deep work from 9:00, an hour of Reading called "Novel" from 11:00, a short legacy Break
    /// called "Lunch" from 12:00. The clock stands at 12:20.
    let deep: SessionRecord
    let novel: SessionRecord
    let lunch: SessionRecord
    let clock = TestClock(Base.at(0, 12, 20))
    let suite = "fc-selftest-noncounting-\(UUID().uuidString)"
    let archive: SessionArchive
    let engine: SessionEngine
    let store: SessionStore
    /// Every session spanning the working day, so credit is the focus work and nothing else.
    let usage = [AppUsageSession(bundleID: "test.noncounting", appName: "Fixture", start: Base.at(0, 8),
                                 end: Base.at(0, 18))]

    private static func record(_ name: String, _ type: WorkType, hour: Int, minutes: Int) -> SessionRecord {
        let start = Base.at(0, hour)
        return SessionRecord(name: name, workType: type, start: start,
                             end: start.addingTimeInterval(Double(minutes) * 60), workSeconds: Double(minutes) * 60)
    }

    /// Nil when there are no in-memory preferences or Reading did not take the setting. `extra` joins the archive.
    init?(extra: [SessionRecord] = []) {
        deep = Self.record("Parser", .deepWork, hour: 9, minutes: 60)
        novel = Self.record("Novel", Base.reading, hour: 11, minutes: 60)
        lunch = Self.record("Lunch", .breakTime, hour: 12, minutes: 15)
        guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
        let persistence = PersistenceStore(defaults: defaults)
        // Through the store, so a later store on the same preferences does not put the catalogue back.
        persistence.workTypeDefinitions = [Self.notCounted()]
        let clock = self.clock
        archive = SelfTest.makeArchive(clock, records: [deep, novel, lunch] + extra, calendar: Base.calendar)
        engine = SessionEngine(store: persistence, archive: archive, ownBundleID: "fc.noncounting.test",
                               schedulesDwell: false, now: { clock.value })
        store = SessionStore(engine: engine, schedulesTicker: false, applicationIsRunning: { _ in false },
                             activateApplication: { _, _ in }, now: { clock.value })
        guard !Base.reading.countsAsFocus else { cleanUp(); return nil }
    }

    func cleanUp() {
        MemoryDefaults.remove(named: suite)
        WorkTypeCatalog.shared.apply(customisations: [])
    }
}
