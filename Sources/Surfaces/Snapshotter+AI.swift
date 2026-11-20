import SwiftUI

/// Apple Intelligence's part for review (Phase C, rulings C8, C13, C17 and C20): three automatic session rows,
/// two with the AI mark, and the reports of an AI pick, a label the AI made and a shadow suggestion. The
/// sessions come from the engine; what the AI said of each is handed to the report as the value
/// `SessionStore.aiReport` returns, since a real answer needs the model.
extension SnapshotScenario {
    var aiReviewTitle: String { "Story — the AI mark on rows, and a report's pick, label and suggestion" }
}

extension Snapshotter {
    static func aiFilings() -> AnyView {
        let fixture = FixtureFactory.aiStore()
        let films = WorkType(rawValue: fixture.label.id)
        let reports = [
            AISessionReport(filing: .pick(.deepWork), showsMark: true),
            AISessionReport(filing: .label(films), mergeTargets: WorkType.startable, showsMark: true),
            AISessionReport(suggestion: .newCategory(name: "Writing")),
        ]
        let shown = [fixture.sessions[0], fixture.sessions[1].recategorised(as: films), fixture.sessions[2]]
        let view = VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, session in
                    SessionEntryCard(session: session, apps: [], isOpen: false, clock: nil, onToggle: {},
                                     origin: fixture.store.originText(for: session), aiMark: reports[index].showsMark)
                }
            }
            .frame(width: 620.zoomed)
            HStack(alignment: .top, spacing: Tokens.Space.xl) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, session in
                    SessionReportCard(store: fixture.store, session: session, onClose: {}, ai: reports[index])
                        .frame(width: 600.zoomed, height: 620.zoomed)
                }
            }
        }
        .padding(Tokens.Space.xl)
        .background(Tokens.Colour.ground)
        return AnyView(view)
    }
}

extension FixtureFactory {
    /// Three finished automatic sessions and an unkept label, "Films", in the catalogue. The label stays
    /// installed for the rest of the run, so this scenario is the matrix's last.
    @MainActor static func aiStore() -> (store: SessionStore, sessions: [DaySession], label: AILabel) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let clock = TestClock(today.addingTimeInterval(8 * 3_600))
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        let engine = SessionEngine(store: PersistenceStore(defaults: fixtureDefaults("ai")), archive: archive,
                                   ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false, now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        let label = AILabel(id: "ai.\(UUID().uuidString)", name: "Films", symbolName: "film", hue: .purple,
                            countsTowardFocus: false, fingerprints: [], created: clock.value, lastUsed: clock.value,
                            archived: false)
        WorkTypeCatalog.shared.install(aiLabels: [label])
        for (name, minutes) in [("Parser", 45.0), ("Saturday matinee", 90), ("Chapter two", 40)] {
            engine.start(workType: .deepWork, intent: name, isAuto: true)
            clock.advance(minutes * 60)
            _ = engine.stop()
            clock.advance(15 * 60)
        }
        let sessions = SessionDigest.entries(records: archive.records, running: nil, now: clock.value, day: today)
            .compactMap { entry -> DaySession? in
                if case .session(let session) = entry { return session }
                return nil
            }
        return (store, sessions, label)
    }

    /// Settings' AI row usable, with a tally line: twenty choices, seventeen of them the AI's.
    @MainActor static func giveAICategories(to model: SettingsModel) {
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let labels = AILabelStore(directory: directory)
        var book = AILabelBook()
        book.tally = (0..<20).map { index in
            TallyEntry(recordID: UUID(), answerID: WorkType.deepWork.rawValue,
                       chosen: index < 17 ? WorkType.deepWork.rawValue : WorkType.learning.rawValue)
        }
        _ = labels.save(book, at: Date())
        model.aiCategories = AICategorySource(setting: AIAssignSetting(defaults: fixtureDefaults("ai-categories")),
                                              labels: labels, modelAvailable: { true })
    }
}
