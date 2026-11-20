import Foundation

/// The fixtures the category assistant's checks share: a store holding ended automatic sessions, each with
/// the shape it left, and an assistant whose model is a closure. Every check sets a responder: none may
/// reach the live model. Moments are offsets from `SelfTest.base`, so nothing depends on a time zone.
enum CategoryAssistantRig {
    typealias Fixture = NameSuggestionStoreChecks.Fixture

    /// One ended automatic session and what it was spent on. The default is unclear on purpose: media
    /// leads without being a focused purpose.
    struct Spec {
        var credited: [AppPurpose: TimeInterval] = [.media: 1_000, .coding: 600]
        var fingerprint: ActivityFingerprint = AIFixture.fingerprint(1)
        var counted: TimeInterval = 1_800
        var source: DecisionSource? = .builtIn
        var name = "Parser"
        /// Set alike on specs that are stretches of one session; nil gives each its own thread, as before.
        var threadID: UUID?

        init(seed: Int = 1) { fingerprint = AIFixture.fingerprint(seed) }
    }

    final class Calls { var questions: [CategoryQuestion] = [] }
    final class Mode { var assigns = false }
    /// What happens while the model is thinking: the person acts, a switch is turned. Set once the rig exists,
    /// as the reply closure is made before it.
    final class Hook { var run: @MainActor () -> Void = {} }

    @MainActor struct Rig {
        let f: Fixture
        let assistant: CategoryAssistant
        let calls: Calls
        let mode: Mode
        let records: [SessionRecord]

        var record: SessionRecord { records[0] }
        var directory: URL { f.engine.archive.dataDirectoryURL }
        /// The record as the archive holds it now.
        func stored(_ index: Int = 0) -> SessionRecord? { f.engine.archive.records.first { $0.id == records[index].id } }
        /// The record's session as its report has it: one stretch, as the archive holds it now.
        func session(_ index: Int = 0) -> DaySession {
            let r = stored(index) ?? records[index]
            return DaySession(id: r.id, threadID: r.threadID, name: r.name, workType: r.workType, start: r.start, end: r.end,
                              worked: r.workSeconds, stretches: 1, spans: [DateInterval(start: r.start, end: r.end)],
                              recordIDs: [r.id], isRunning: false)
        }
        /// Use on `session` as its report draws it now: false, as the card would show no Use, when nothing is offered.
        func use(_ session: DaySession) -> Bool {
            guard let shown = f.store.aiReport(for: session).suggestion else { return false }
            return f.store.useAISuggestion(shown, for: session)
        }
        /// What a relaunch would read from `ai-labels.json`.
        func reloaded() -> AILabelStore { AILabelStore(directory: directory) }

        /// The session ended: the assistant is told, and the run loop turns until it has nothing left to do
        /// (`wait` more seconds, for a reply that arrives after the assistant gave up on it).
        func ask(_ index: Int = 0, wait: TimeInterval = 0) { ask(id: records[index].id, wait: wait) }

        /// The same for a record the rig did not make: the half of a split, a stretch an answer counted in.
        func ask(id: UUID, wait: TimeInterval = 0) {
            assistant.sessionEnded(id)
            settle(wait)
        }

        func settle(_ wait: TimeInterval = 0) {
            _ = InstalledAppCatalog.turnRunLoop(until: { assistant.isIdle }, timeout: 5)
            if wait > 0 { _ = InstalledAppCatalog.turnRunLoop(until: { false }, timeout: wait) }
        }
    }

    static func shape(for record: SessionRecord, _ spec: Spec) -> SessionActivityShape {
        SessionActivityShape(
            algorithmVersion: ActivityConstants.algorithmVersion, fidelity: .beats,
            bounds: DateInterval(start: record.start, end: record.end), countedSeconds: spec.counted, signals: [],
            phases: [], depth: .deep, label: .mixed,
            credited: Dictionary(uniqueKeysWithValues: spec.credited.map { ($0.key.rawValue, $0.value) }),
            fingerprint: spec.fingerprint, splitCandidates: [])
    }

    /// A store over scratch folders with one ended automatic session per spec, an hour apart from
    /// `SelfTest.base`, a stored shape for each, and Apple Intelligence on. `reply` is given how many questions
    /// have been asked, this one included.
    static func withRig(
        _ specs: [Spec] = [Spec()], usage: [AppUsageSession] = [], journal: (() -> String?)? = nil,
        reply: @escaping @MainActor (Int, CategoryQuestion) async throws -> CategoryAnswerChoice
            = { _, _ in CategoryAnswerChoice(choice: "none", label: "") },
        prepare: (Fixture) -> Void = { _ in },
        _ body: @MainActor (Rig, inout [String]) -> Void
    ) -> [String] {
        let records = specs.enumerated().map { index, spec -> SessionRecord in
            let start = SelfTest.base.addingTimeInterval(TimeInterval(index) * 3_600)
            return SessionRecord(name: spec.name, workType: .deepWork, start: start,
                                 end: start.addingTimeInterval(1_800), workSeconds: 1_800, threadID: spec.threadID ?? UUID(), isAuto: true,
                                 origin: .automatic, categorySource: spec.source)
        }
        return NameSuggestionStoreChecks.withFixture(records: { _ in records }, usage: { _ in usage }, journal: journal) { f, _, problems in
            // The catalogue is process-wide: leave no label or category behind for the checks that follow.
            defer {
                WorkTypeCatalog.shared.install(aiLabels: [])
                WorkTypeCatalog.shared.apply(customisations: [])
            }
            f.persistence.useAppleIntelligence = true
            for (record, spec) in zip(records, specs) {
                guard f.metadata.saveActivityShape(shape(for: record, spec), for: record.id) == .saved else {
                    problems.append("no shape was saved for \(record.name)")
                    return
                }
            }
            prepare(f)
            // Every session ended some time ago.
            f.clock.advance(TimeInterval(specs.count + 1) * 3_600)
            let calls = Calls(), mode = Mode()
            let assistant = CategoryAssistant(store: f.store, labels: AILabelStore(directory: f.engine.archive.dataDirectoryURL),
                                              assigns: { mode.assigns })
            assistant.responder = { question in
                calls.questions.append(question)
                return try await reply(calls.questions.count, question)
            }
            body(Rig(f: f, assistant: assistant, calls: calls, mode: mode, records: records), &problems)
        }
    }

    /// The answer a model gives: "2" picks the second category, "new" with a label proposes one.
    static func answer(_ choice: String, _ label: String = "") -> CategoryAnswerChoice {
        CategoryAnswerChoice(choice: choice, label: label)
    }
}
