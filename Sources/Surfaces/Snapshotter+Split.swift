import SwiftUI

/// "Split here?" and "Merge Back" for review: the report of a session of the person's that held a film after
/// its work (the offer asks for the second part's category), and the report of the tail of an automatic
/// session that split itself (Merge Back). The sessions come the way the app makes them, from the engine and
/// its own split, never from hand-made text.
extension Snapshotter {
    static func splitOffers() -> AnyView {
        let fixture = FixtureFactory.splitStore()
        let view = HStack(alignment: .top, spacing: Tokens.Space.xl) {
            SessionReportCard(store: fixture.store, session: fixture.offered, onClose: {})
            SessionReportCard(store: fixture.store, session: fixture.tail, onClose: {})
        }
        .frame(width: 1_560.zoomed, height: 760.zoomed)
        .padding(Tokens.Space.xl)
        .background(Tokens.Colour.ground)
        return AnyView(view)
    }
}

extension FixtureFactory {
    @MainActor static func splitStore() -> (store: SessionStore, offered: DaySession, tail: DaySession) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let clock = TestClock(today.addingTimeInterval(8 * 3_600))
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        let engine = SessionEngine(store: PersistenceStore(defaults: fixtureDefaults("split")), archive: archive,
                                   ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false, now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })

        func end(after minutes: TimeInterval) {
            clock.advance(minutes * 60)
            _ = engine.stop()
            clock.advance(15 * 60)
        }
        // Written by the person: fifty minutes, the last twenty of it a film.
        engine.start(workType: .deepWork, intent: "Write the report")
        end(after: 50)
        if let record = archive.records.last { SplitOfferChecks.keepShape(record, in: store, cutAfter: 1_800) }
        // Started by Daybook, and split by Daybook when its work moved on: the tail offers Merge Back.
        engine.start(workType: .deepWork, intent: "Coding", isAuto: true, nameByApp: true)
        end(after: 55)
        if let record = archive.records.last {
            _ = store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(1_800),
                                   tail: SplitTail(name: "Design", workType: .deepWork, source: .builtIn, nameByApp: true,
                                                   detectedApp: "com.figma.Desktop"))
        }

        let sessions = SessionDigest.entries(records: archive.records, running: nil, now: clock.value, day: today)
            .compactMap { entry -> DaySession? in
                if case .session(let session) = entry { return session }
                return nil
            }
        return (store, sessions.first { $0.name == "Write the report" } ?? sessions[0],
                sessions.first { $0.name == "Design" } ?? sessions[sessions.count - 1])
    }
}
