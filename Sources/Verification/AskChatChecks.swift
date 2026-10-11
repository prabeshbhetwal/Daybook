import Foundation
import FoundationModels

/// Ask as a conversation: a follow-up adds a turn, Stop ends an answer safely,
/// and an answer that has ended is never written to again by a lookup or a
/// stream that arrives late. None starts a `LanguageModelSession`: the model's
/// `responder` seam stands in for it. `AskChatEndingChecks` holds the other
/// ways an answer ends.
enum AskChatChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = ownTests + AskChatEndingChecks.tests + AskChatSessionChecks.tests

    private static let ownTests: [(String, () -> [String])] = [
        ("A follow-up question adds a turn and leaves the earlier one as it was", followUpAppends),
        ("A question asked while an answer is being worked out is ignored", askWhileAnsweringIsIgnored),
        ("An answer's sources are picked when it finishes, from what it names", sourcesPickedAtFinish),
        ("Stop keeps what had streamed, drops the session and carries the last two answers", stopKeepsTextAndCarries),
        ("A lookup and a stream landing after Stop write nothing into the next answer", lateLookupAfterStopIsNotCounted),
        ("A session dropped at midnight carries nothing", midnightCarriesNothing),
    ]

    typealias Gate = AskThreadChecks.Gate

    static func with(_ body: @MainActor (AskLookupChecks.Fixture, AskModel, inout [String]) -> Void) -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return AskThreadChecks.withModel(body)
    }

    @MainActor static func wait(_ condition: () -> Bool) {
        InstalledAppCatalog.turnRunLoop(until: condition, timeout: 5)
    }

    /// Asks and waits for the answer to end.
    @MainActor static func ask(_ model: AskModel, _ question: String) {
        model.ask(question)
        wait { !model.isAnswering }
    }

    /// Lets a stream or lookup that was held up land, and what follows it run.
    @MainActor static func settle() {
        InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.1)
    }

    static let weekTotals = ["range": "this week"]

    // MARK: - Turns

    private static func followUpAppends() -> [String] {
        with { _, model, problems in
            model.responder = { question, show in show(question == "A" ? "One." : "Two.") }
            ask(model, "A")
            let first = model.turns.first
            ask(model, "B")
            expect(model.turns.count == 2 && model.turns.first == first,
                   "the follow-up left the turns as \(model.turns)", &problems)
            expect(model.turns.map(\.question) == ["A", "B"] && model.turns.map(\.answer) == ["One.", "Two."],
                   "the turns read \(model.turns.map { ($0.question, $0.answer) })", &problems)
            expect(model.turns.allSatisfy { $0.state == .answered },
                   "the turns are \(model.turns.map(\.state))", &problems)
        }
    }

    private static func askWhileAnsweringIsIgnored() -> [String] {
        with { _, model, problems in
            let hold = Gate()
            var asked: [String] = []
            model.responder = { question, _ in
                asked.append(question)
                await withCheckedContinuation { hold.release = $0 }
            }
            model.ask("A")
            wait { hold.release != nil }
            model.ask("B")
            expect(model.turns.count == 1 && model.turns[0].question == "A",
                   "a question asked mid-answer gave \(model.turns.map(\.question))", &problems)
            hold.release?.resume()
            wait { !model.isAnswering }
            expect(asked == ["A"] && model.turns.count == 1, "the model was asked \(asked)", &problems)
        }
    }

    private static func sourcesPickedAtFinish() -> [String] {
        with { f, model, problems in
            let hold = Gate()
            model.responder = { [unowned model] _, show in
                _ = model.lookup(name: "focusTotals", arguments: weekTotals, generation: model.generation)
                show("Your best day was Tue 14 Nov.")
                await withCheckedContinuation { hold.release = $0 }
            }
            model.ask("What was my best day this week?")
            wait { hold.release != nil }
            expect(model.turns[0].state == .answering && model.turns[0].sources.isEmpty,
                   "while streaming the turn is \(model.turns[0].state) with \(model.turns[0].sources.count) sources",
                   &problems)
            hold.release?.resume()
            wait { !model.isAnswering }
            let turn = model.turns[0]
            let day = f.calendar.date(from: DateComponents(year: 2023, month: 11, day: 14))!
            expect(turn.state == .answered && turn.provenance == ["focus totals (this week)"],
                   "the turn is \(turn.state), resting on \(turn.provenance)", &problems)
            expect(turn.sources.first?.link.target == .day(day) && turn.sources.first?.mention != nil,
                   "the first source is \(String(describing: turn.sources.first))", &problems)
        }
    }

    // MARK: - Stop

    private static func stopKeepsTextAndCarries() -> [String] {
        with { _, model, problems in
            let hold = Gate()
            var carriedAtAsk: [[AskTurn]] = []
            model.responder = { [unowned model] question, show in
                carriedAtAsk.append(model.carried)
                show("Answer to \(question).")
                guard question == "held" else { return }
                _ = model.lookup(name: "focusTotals", arguments: weekTotals, generation: model.generation)
                show("Partly")
                await withCheckedContinuation { hold.release = $0 }
                hold.landed = true
            }
            ask(model, "Q1")
            ask(model, "Q2")
            let answered = model.turns
            model.ask("held")
            wait { hold.release != nil }
            let generation = model.generation
            model.stop()
            let stopped = model.turns[2]
            expect(!model.isAnswering && stopped.state == .stopped && stopped.answer == "Partly",
                   "Stop left the turn \(stopped.state) reading “\(stopped.answer)”", &problems)
            expect(stopped.sources.isEmpty, "a stopped answer lists \(stopped.sources.count) sources", &problems)
            expect(model.generation == generation + 1 && model.sessionDay == nil,
                   "Stop kept the session: generation \(model.generation), day \(String(describing: model.sessionDay))",
                   &problems)
            expect(model.carried == answered, "Stop carries \(model.carried.map(\.question)), not Q1 and Q2", &problems)

            // The stopped answer finishes late, and changes nothing.
            let after = model.turns
            hold.release?.resume()
            wait { hold.landed }
            settle()
            expect(model.turns == after, "an answer finishing after Stop changed the turns to \(model.turns)", &problems)

            ask(model, "next")
            expect(carriedAtAsk.last == answered, "the next question was asked carrying \(carriedAtAsk.last ?? [])",
                   &problems)
            expect(model.turns.count == 4 && model.turns[3].state == .answered, "the next answer is \(model.turns[3])",
                   &problems)
        }
    }

    private static func lateLookupAfterStopIsNotCounted() -> [String] {
        with { f, model, problems in
            let first = Gate(), next = Gate()
            model.responder = { [unowned model] question, show in
                if question == "first" {
                    first.generation = model.generation
                    await withCheckedContinuation { first.release = $0 }
                    // What the model's tool does once the answer it began is over.
                    first.texts.append(model.lookup(name: "bestHours", arguments: ["range": "today"],
                                                    generation: first.generation))
                    show("Stale words.")
                    first.landed = true
                } else {
                    _ = model.lookup(name: "focusTotals", arguments: weekTotals, generation: model.generation)
                    await withCheckedContinuation { next.release = $0 }
                    show("Fresh words.")
                }
            }
            model.ask("first")
            wait { first.release != nil }
            model.stop()
            model.ask("next")
            wait { next.release != nil }

            first.release?.resume()
            wait { first.landed }
            settle()
            let want = f.store.askLookup(.bestHours(.today))
            expect(first.texts == [want], "the late lookup returned \(first.texts), not the store's figure", &problems)
            expect(model.turns.last?.answer == "" && model.turns.last?.question == "next",
                   "a stream landing after Stop wrote “\(model.turns.last?.answer ?? "")” into the next turn", &problems)

            next.release?.resume()
            wait { !model.isAnswering }
            expect(model.turns.last?.provenance == ["focus totals (this week)"],
                   "the next answer rests on \(String(describing: model.turns.last?.provenance))", &problems)
            expect(model.turns.map(\.state) == [.stopped, .answered] && model.turns.last?.answer == "Fresh words.",
                   "the turns are \(model.turns.map { ($0.state, $0.answer) })", &problems)
        }
    }

    // MARK: - Midnight

    private static func midnightCarriesNothing() -> [String] {
        with { f, model, problems in
            let hold = Gate()
            model.responder = { question, show in
                show("Answer to \(question).")
                if question == "held" { await withCheckedContinuation { hold.release = $0 } }
            }
            ask(model, "Q1")
            ask(model, "Q2")
            model.ask("held")
            wait { hold.release != nil }
            model.stop()
            model.retireStaleSession()
            expect(model.carried.count == 2, "the same day dropped what Stop carried: \(model.carried.map(\.question))",
                   &problems)

            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!
            model.retireStaleSession()
            expect(model.carried.isEmpty, "turns from yesterday are carried into today: \(model.carried.map(\.question))",
                   &problems)
            expect(model.turns.count == 3, "the transcript on screen changed: \(model.turns.map(\.question))", &problems)
        }
    }
}
