import Combine
import Foundation

/// Asks Apple's on-device model about each ended automatic session whose evidence is unclear, once, and
/// files what it says (Phase C, rulings C2 to C9, C24, C25 and C29). It picks one of the person's categories
/// or proposes a short new label; the answer is cached by the kind of session, so the same pattern is not
/// asked twice, and an answer already in the file is used with no question. While "Let AI assign categories"
/// is off the answer is only a suggestion; on, it is written to the record as the AI's and the person keeps
/// or changes it. Nothing here runs on the 1 Hz ticker: a question starts when the sweep says a session
/// ended, and its timeout is a sleeping task. The model sees the question's facts and nothing else.
@MainActor final class CategoryAssistant: ObservableObject {
    /// Shadow mode's offers: what the model said for a record Daybook still has the category of. This run
    /// only; the answer itself stays in the label file, keyed by the kind of session.
    @Published private(set) var suggestions: [UUID: AIAnswer] = [:]
    @Published private(set) var isAsking = false
    let labels: AILabelStore
    /// How long to wait for the model; checks shorten it.
    var timeout: Duration = .seconds(10)
    /// Stands in for the model in checks: the question in, the model's choice out. It stands in for the model's
    /// availability, never for the Apple Intelligence switch (C22).
    var responder: (@MainActor (CategoryQuestion) async throws -> CategoryAnswerChoice)?
    /// Read when a session ends, so checks can drive them.
    var lowPower: () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    var thermalSerious: () -> Bool = { [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) }

    private weak var store: SessionStore?
    private let assigns: () -> Bool
    /// Ended sessions waiting their turn: one question is under way at a time.
    private var queue: [UUID] = []
    private var pumping = false
    /// Which question is under way, counted up whenever one starts or ends: a reply or a timer from an earlier
    /// one finds it is not current and does nothing.
    private var generation = 0
    private var asking: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    /// Whether shadow mode's offers were wanted when the last refresh looked: on-device AI on and assigning off.
    /// Nil before the first (`followSwitch`).
    private var offersWereWanted: Bool?

    init(store: SessionStore, labels: AILabelStore, assigns: @escaping () -> Bool = { false }) {
        self.store = store
        self.labels = labels
        self.assigns = assigns
        // The labels already made reach the catalogue at once, or a record carrying one would read "Other".
        WorkTypeCatalog.shared.install(aiLabels: labels.book.labels)
    }

    /// The person took or settled these records' offers: they are offered no longer.
    func withdraw(_ recordIDs: [UUID]) { recordIDs.forEach { suggestions[$0] = nil } }

    /// After a relaunch, shadow mode's offers come back from the label file with no question asked and nothing
    /// written or recorded: for each record the model answered whose category the person has not set since,
    /// still one Daybook would ask about (source `builtIn`, no correction now matching, no Undo holding it: C2,
    /// C24), the cached answer for its kind of session, while what it names is still there to use.
    func restoreSuggestions() {
        guard let store, store.appleIntelligenceEnabled, labels.failure == nil, !assigns() else { return }
        // The split heads once for the pass, not one archive scan per entry.
        let moment = store.now(), book = labels.book, heads = store.splitHeads()
        for entry in book.tally where entry.chosen == nil && suggestions[entry.recordID] == nil {
            guard let target = store.categoryAskTarget(for: entry.recordID, splitHeads: heads),
                  let cached = book.cachedAnswer(for: target.question.fingerprint,
                                                 offered: target.question.offered.map(\.rawValue), now: moment),
                  cached.id == entry.answerID,
                  let answer = stillUsable(cached, in: book, at: moment, target: target) else { continue }
            offer(answer, for: target.record)
        }
    }

    /// Called on each refresh: on-device AI turned on, or assigning turned off, since the last one brings back the
    /// offers that a launch in the other state could not; either turned the other way takes them away, so Use
    /// cannot take a shadow suggestion while assigning is on.
    func followSwitch() {
        let wanted = offersWanted
        if !wanted, !suggestions.isEmpty { suggestions = [:] }
        if wanted, offersWereWanted == false { restoreSuggestions() }
        offersWereWanted = wanted
    }

    /// Shadow mode's offers are wanted: on-device AI on and assigning off. Read again by Use and the report, so
    /// an offer made or kept since the switch turned is never taken.
    var offersWanted: Bool { store?.appleIntelligenceEnabled == true && !assigns() }

    /// Nothing asked, nothing waiting.
    var isIdle: Bool { !isAsking && queue.isEmpty && !pumping }

    /// The Apple Intelligence switch is on, the model is ready (a responder stands in for it), the label file
    /// can take what it answers, and the Mac is neither in Low Power Mode nor under thermal pressure (C4).
    private var gatesOpen: Bool {
        guard let store, store.appleIntelligenceEnabled, labels.failure == nil,
              responder != nil || ModelGate.modelAvailable else { return false }
        return !lowPower() && !thermalSerious()
    }

    /// A session ended. Asked about when the gates are open now; one that ends while they are shut is never
    /// asked later (C4).
    func sessionEnded(_ recordID: UUID) {
        guard gatesOpen, !queue.contains(recordID) else { return }
        queue.append(recordID)
        pump()
    }

    /// Takes the next waiting session: what the book already knows is used at once, anything else is asked.
    private func pump() {
        guard !pumping, !isAsking else { return }
        pumping = true
        defer { pumping = false }
        while !isAsking, !queue.isEmpty {
            let id = queue.removeFirst()
            guard gatesOpen, let store, let target = store.categoryAskTarget(for: id) else { continue }
            let moment = store.now()
            let fingerprint = target.question.fingerprint, book = labels.book
            // A label made for this kind of session is given back by code, not by the model (C9).
            if let label = book.reusableLabel(for: fingerprint, now: moment) {
                deliver(.label(label.id), target, assigning: assigns())
            } else if let cached = book.cachedAnswer(for: fingerprint, offered: target.question.offered.map(\.rawValue), now: moment),
                      let answer = stillUsable(cached, in: book, at: moment, target: target) {
                deliver(answer, target, assigning: assigns())
            } else {
                ask(target)
            }
        }
    }

    /// What a cached answer comes to now, or nil when it must be asked afresh. It is used only while what it
    /// names is still there to use: a label that has since lapsed is not given back, and a proposal whose id a
    /// label already holds is not made twice. A proposal is otherwise checked again as a fresh reply for its
    /// name would be, by the same rule: a name a category, a removed name or a live label now holds is that
    /// category or label, not a second one (a rename keeps the id, so the cache's key does not change with it).
    /// The report's offer is checked by it too (`offeredAIAnswer`), so Use never takes what a relaunch would drop.
    func stillUsable(_ answer: AIAnswer, in book: AILabelBook, at moment: Date, target: CategoryAskTarget) -> AIAnswer? {
        switch answer {
        case .none: return AIAnswer.none
        case .pick(let id): return target.question.offered.contains { $0.rawValue == id } ? answer : nil
        case .label(let id): return book.liveLabels(now: moment).contains { $0.id == id } ? answer : nil
        case .proposed(let id, let name):
            // Its id may since be a label's: never made a second time. A category the person kept from it (a twin
            // session's Use, or a Keep before a relaunch) is offered as that category while it is still offered.
            guard !book.labels.contains(where: { $0.id == id }) else { return nil }
            if WorkTypeCatalog.shared.allDefinitions.contains(where: { $0.id == id }) {
                return target.question.offered.contains { $0.rawValue == id } ? .pick(id) : nil
            }
            let again = resolved("new", name, target, book, at: moment, newID: { id })
            return again == AIAnswer.none ? nil : again
        }
    }

    /// A reply, fresh or cached, checked against what exists now: the one rule for both (C28).
    private func resolved(_ choice: String, _ label: String, _ target: CategoryAskTarget, _ book: AILabelBook,
                          at moment: Date, newID: () -> String) -> AIAnswer {
        AIAnswerResolver.resolve(
            choice: choice, label: label, offered: target.startable, unofferedNames: target.unofferedNames,
            unkeptLabels: book.liveLabels(now: moment), removedNames: book.removedNames, newID: newID)
    }

    // MARK: - Asking

    private func ask(_ target: CategoryAskTarget) {
        isAsking = true
        generation &+= 1
        let mine = generation, assigning = assigns()
        asking = Task { [weak self] in await self?.finish(mine, target, assigning: assigning) }
        // A sleeping timer, not a race: the model may ignore cancellation, and a group would wait for it.
        timer = Task { [weak self, wait = timeout] in
            try? await Task.sleep(for: wait)
            self?.timedOut(mine)
        }
    }

    /// Stops waiting for question `id`, unless another has begun since.
    private func end(_ id: Int) {
        guard id == generation, isAsking else { return }
        generation &+= 1
        isAsking = false
        asking?.cancel()
        timer?.cancel()
    }

    /// Nothing is written, offered or cached for a question that was not answered in time.
    private func timedOut(_ id: Int) {
        guard id == generation, isAsking else { return }
        end(id)
        pump()
    }

    private func finish(_ id: Int, _ target: CategoryAskTarget, assigning: Bool) async {
        let reply: Result<CategoryAnswerChoice, Error>
        do { reply = .success(try await asked(target.question)) } catch { reply = .failure(error) }
        guard id == generation else { return }
        end(id)
        if case .success(let choice) = reply { accept(choice, target, assigning: assigning) }
        pump()
    }

    private func asked(_ question: CategoryQuestion) async throws -> CategoryAnswerChoice {
        if let responder { return try await responder(question) }
        guard #available(macOS 26, *) else { throw CocoaError(.featureUnsupported) }
        return try await CategoryModel.ask(question)
    }

    /// An answer arrived in time. Everything is checked again before anything is kept (C24): the switch, that
    /// the record is exactly as it ended with no correction now matching, and the category list: a number or a
    /// name means what it did only against the list it was asked with, so a list changed since drops the reply,
    /// and a name is read against the categories as they stand now. Written only when assigning was on both
    /// when asked and now; a switch turned meanwhile leaves the answer on offer, shown once offers are wanted.
    private func accept(_ choice: CategoryAnswerChoice, _ asked: CategoryAskTarget, assigning: Bool) {
        guard let store, store.appleIntelligenceEnabled, store.categoryAskIsCurrent(asked),
              let target = store.categoryAskTarget(for: asked.record.id),
              target.question.offered == asked.question.offered else { return }
        let moment = store.now(), book = labels.book
        deliver(resolved(choice.choice, choice.label, target, book, at: moment,
                         newID: { "ai." + UUID().uuidString.lowercased() }), target, assigning: assigning && assigns())
    }

    // MARK: - What becomes of an answer

    /// Keeps the answer (cached, and in the tally unless none) and, with `assigning`, writes it. A proposal
    /// is made a label only at the limits' leave and only with assigning on (C9); at a limit nothing is
    /// written and the category the session ended with stands (C12).
    private func deliver(_ answer: AIAnswer, _ target: CategoryAskTarget, assigning: Bool) {
        guard let store else { return }
        let moment = store.now(), fingerprint = target.question.fingerprint
        var book = labels.book
        book.recordAnswer(answer, recordID: target.record.id, fingerprint: fingerprint,
                          offered: target.question.offered.map(\.rawValue), now: moment)
        guard assigning else {
            // Offered only once on disk: Use would otherwise take an answer the tally never held.
            if keep(book, at: moment) { offer(answer, for: target.record) }
            return
        }
        suggestions[target.record.id] = nil
        switch answer {
        case .none:
            keep(book, at: moment)
        case .pick(let id):
            // Written only once the answer is on disk, or a relaunch would find the AI's mark with nothing behind it.
            if keep(book, at: moment) { write(WorkType(rawValue: id), to: target) }
        case .label(let id):
            book.markUsed(labelID: id, fingerprint: fingerprint, now: moment)
            if keep(book, at: moment) { write(WorkType(rawValue: id), to: target) }
        case .proposed(let id, let name):
            let made = book.addUnkeptLabel(id: id, name: name, dominant: target.dominant, fingerprint: fingerprint, now: moment)
            // The label is on disk before any record carries it, or a relaunch would read the record as "Other".
            guard keep(book, at: moment), made != nil else { return }
            WorkTypeCatalog.shared.install(aiLabels: labels.book.labels)
            write(WorkType(rawValue: id), to: target)
        }
    }

    /// Shadow mode: the answer on offer, unless it names the category the record already has.
    private func offer(_ answer: AIAnswer, for record: SessionRecord) {
        switch answer {
        case .pick(let id) where id == record.workType.rawValue: return
        case .none: return
        default: suggestions[record.id] = answer
        }
    }

    /// A pick that is the category the record already has is not written: nothing is assigned.
    private func write(_ type: WorkType, to target: CategoryAskTarget) {
        guard type != target.record.workType else { return }
        store?.writeAICategory(type, to: target)
    }

    @discardableResult
    private func keep(_ book: AILabelBook, at moment: Date) -> Bool {
        guard let why = labels.save(book, at: moment) else { return true }
        Diagnostics.log("ai-labels.json not saved: \(why)")
        return false
    }
}
