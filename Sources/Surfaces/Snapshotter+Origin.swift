import SwiftUI

/// How a session began, for review: five rows (a rule's, the person's, one carried on after an away answer,
/// the app's own with a name it chose, and one whose label the evidence contradicts), the report that adds
/// the contradiction line and the report that offers a category remembered from before. The sessions come
/// the way the app makes them, from the engine, an away answer and a stored shape, never from hand-made text.
extension Snapshotter {
    static func originMarks() -> AnyView {
        let fixture = FixtureFactory.originStore()
        let view = HStack(alignment: .top, spacing: Tokens.Space.xl) {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                ForEach(fixture.sessions) { session in
                    SessionEntryCard(session: session, apps: [], isOpen: false, clock: nil, onToggle: {},
                                     origin: fixture.store.originText(for: session))
                }
            }
            .frame(width: 620.zoomed)
            VStack(spacing: Tokens.Space.xl) {
                SessionReportCard(store: fixture.store, session: fixture.contradicted, onClose: {})
                SessionReportCard(store: fixture.store, session: fixture.suggested, onClose: {})
            }
            .frame(width: 760.zoomed, height: 940.zoomed)
        }
        .padding(Tokens.Space.xl)
        .background(Tokens.Colour.ground)
        return AnyView(view)
    }
}

extension FixtureFactory {
    /// A morning of finished sessions in `Snapshotter.originMarks`' order; the last two are also its reports.
    @MainActor static func originStore() -> (store: SessionStore, sessions: [DaySession],
                                            contradicted: DaySession, suggested: DaySession) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let clock = TestClock(today.addingTimeInterval(8 * 3_600))
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        let persistence = PersistenceStore(defaults: fixtureDefaults("origin"))
        let ruleID = UUID()
        persistence.activityRules = [ActivityRule(id: ruleID, name: "Morning coding", workType: .deepWork,
                                                  bundleIDs: ["com.apple.dt.Xcode"])]
        let engine = SessionEngine(store: persistence, archive: archive, ownBundleID: FocusConstants.bundleIdentifier,
                                   schedulesDwell: false, now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })

        func end(after minutes: TimeInterval) {
            clock.advance(minutes * 60)
            _ = engine.stop()
            clock.advance(15 * 60)
        }
        _ = engine.startAutomatically(action: ActivityAutomaticAction(
            ruleID: ruleID, ruleName: "Morning coding", workType: .deepWork,
            evidence: DateInterval(start: clock.value.addingTimeInterval(-180), end: clock.value),
            reason: "Coding evidence", ruleVersion: 1, generation: 1, expectedRecordID: nil))
        end(after: 45)
        engine.start(workType: .deepWork, intent: "Plan the week")
        end(after: 30)
        engine.start(workType: .deepWork, intent: "Write the report")
        clock.advance(15 * 60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(22 * 60)
        engine.transition(on: .awayEnded)
        engine.transition(on: .decision(.mergeTime))
        end(after: 20)
        engine.start(workType: .deepWork, intent: "Browsing", isAuto: true, nameByApp: true)
        end(after: 40)
        engine.start(workType: .deepWork, intent: "Draft the proposal")
        end(after: 60)

        // The last two sessions' evidence: mostly reading for the app's own, 29% coding and 61% media for the
        // person's, whose label the report then holds against it.
        func keep(_ index: Int, credited: [AppPurpose: TimeInterval]) -> SessionActivityShape? {
            guard archive.records.indices.contains(index) else { return nil }
            let record = archive.records[index]
            let shape = ActivitySnapshotChecks.shape(
                .activity(.research), credited: Dictionary(uniqueKeysWithValues: credited.map { ($0.key.rawValue, $0.value) }),
                over: DateInterval(start: record.start, end: record.end))
            store.metadataArchive.saveActivityShape(shape, for: record.id)
            return shape
        }
        let learned = keep(archive.records.count - 2, credited: [.research: 2_400])
        _ = keep(archive.records.count - 1, credited: [.coding: 1_044, .media: 2_196, .utility: 360])
        if let kind = learned?.fingerprint {
            _ = CorrectionsStore(directory: archive.dataDirectoryURL)
                .record(fingerprint: kind, chosen: WorkType.learning.rawValue, vetoed: nil, at: clock.value)
        }

        let sessions = SessionDigest.entries(records: archive.records, running: nil, now: clock.value, day: today)
            .compactMap { entry -> DaySession? in
                if case .session(let session) = entry { return session }
                return nil
            }
        return (store, sessions, sessions[sessions.count - 1], sessions[sessions.count - 2])
    }
}
