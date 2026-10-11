import Foundation
import FoundationModels

/// Working out one answer, and the ways it ends. Every answer has a gate of
/// its own, and a gate that is closed is the whole of how an answer that is
/// over stays over: its stream, its progress and its lookups all check the gate
/// before they touch a turn, so nothing from a stopped, ended or replaced
/// answer can land in the one that followed it.
extension AskModel {
    /// A gate for the lookups of one answer. With no handlers, and closed, it
    /// reads the store and records nothing.
    func makeGate(onProgress: @escaping (String) -> Void = { _ in }, onEnd: @escaping () -> Void = {}) -> AskGate {
        AskGate(store: store, period: { [weak self] in self?.range($0) }, onProgress: onProgress, onEnd: onEnd)
    }

    /// Greedy: the same question over the same history gets the same tools
    /// and the same answer. Sampled, one question picked a different tool
    /// from run to run, sometimes the wrong one (probe, 2026-10-10). The
    /// macOS 27 SDK renames the argument and deprecates the old name.
    @available(macOS 26, *)
    private static var options: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }

    // MARK: - Starting

    /// Starts working out `question` for the turn `id`, under a gate of its own.
    /// `retrying`: this is the second try, after the context was full.
    @available(macOS 26, *)
    func begin(_ id: UUID, question: String, retrying: Bool) {
        stampSessionDay()
        let gate = makeGate(
            onProgress: { [weak self] line in self?.update(id) { $0.state = .lookingUp(line) } },
            // The gate calls this on the eighth lookup, while it is open.
            onEnd: { [weak self] in self?.end(.failed(AskModel.keptLooking)) })
        self.gate = gate
        answering = Task { [weak self] in
            await self?.respond(to: question, turn: id, gate: gate, retrying: retrying)
        }
    }

    @available(macOS 26, *)
    private func respond(to text: String, turn id: UUID, gate: AskGate, retrying: Bool) async {
        // Stopped between asking and starting: the model is not asked at all.
        guard gate.isOpen else { return }
        var failure: Error?
        let show: (String) -> Void = { [weak self] partial in
            guard gate.isOpen, !partial.isEmpty else { return }
            self?.update(id) { $0.answer = partial; $0.state = .answering }
        }
        do {
            if let responder {
                try await responder(text, show)
            } else {
                for try await snapshot in liveSession().streamResponse(to: text, options: Self.options) {
                    if Task.isCancelled { break }
                    show(snapshot.content)
                }
            }
        } catch {
            failure = error
        }
        // Stopped, ended or replaced while it ran: that already settled the turn.
        guard gate.isOpen else { return }
        if let failure {
            fail(failure, turn: id, question: text, retrying: retrying)
        } else {
            complete(id, gate: gate)
        }
    }

    // MARK: - Ending

    /// The send button while answering. The turn keeps what had streamed.
    func stop() {
        end(.stopped)
    }

    /// Shuts the gate and cancels the task of the answer in progress. Whatever
    /// either still does after this is ignored.
    func closeRun() {
        gate?.isOpen = false
        gate = nil
        answering?.cancel()
        answering = nil
    }

    /// Ends the answer in progress as `state`. A failed turn shows its notice
    /// and no half-answer; a stopped one keeps its text. Neither has sources.
    /// However it ends, the session is dropped and the last two finished turns
    /// of today are carried into the next, so a lookup the answer had begun
    /// cannot land in an answer of the session that follows.
    func end(_ state: AskTurnState) {
        guard isAnswering, let id = turns.last?.id else { return }
        let provenance = gate?.provenance ?? []
        closeRun()
        update(id) {
            if case .failed = state { $0.answer = "" }
            $0.state = state
            $0.provenance = provenance
        }
        dropSession(carrying: true)
    }

    /// The model finished: the sources are picked from the answer as it stands,
    /// read against the day it was asked on.
    private func complete(_ id: UUID, gate: AskGate) {
        update(id) {
            $0.state = .answered
            $0.provenance = gate.provenance
            $0.sources = AskSourcePicker.sources(answer: $0.answer, lookups: gate.lookups,
                                                 calendar: gate.calendar, now: gate.asked)
        }
        closeRun()
    }

    @available(macOS 26, *)
    private func fail(_ error: Error, turn id: UUID, question: String, retrying: Bool) {
        guard Self.isContextFull(error) else {
            end(.failed(Self.notice(for: error)))
            return
        }
        if retrying { end(.failed(Self.contextFull)) } else { retry(id, question: question) }
    }

    /// The context is full: a fresh session, told the last two finished turns,
    /// is asked the same question once more, without telling the reader.
    @available(macOS 26, *)
    private func retry(_ id: UUID, question: String) {
        closeRun()
        dropSession(carrying: true)
        update(id) {
            $0.answer = ""
            $0.provenance = []
            $0.state = .lookingUp(nil)
        }
        begin(id, question: question, retrying: true)
    }
}
