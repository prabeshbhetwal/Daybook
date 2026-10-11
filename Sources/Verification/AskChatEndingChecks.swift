import Foundation
import FoundationModels

/// The ways an Ask answer ends besides finishing or Stop: a full context,
/// which is retried once in a fresh session carrying the last two answers,
/// and the eighth lookup, which ends it with a notice.
enum AskChatEndingChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A full context is retried once, in a fresh session carrying the last two answers",
         contextFullCarriesTwoAndRetries),
        ("A second full context shows the notice after exactly two tries", secondFullContextShowsNotice),
        ("The sixth lookup is told the limit and the eighth ends the answer with a notice",
         eighthLookupEndsWithNotice),
    ]

    private typealias Chat = AskChatChecks
    private typealias Gate = AskThreadChecks.Gate

    @available(macOS 26, *)
    static var fullContext: LanguageModelSession.GenerationError {
        .exceededContextWindowSize(.init(debugDescription: "probe"))
    }

    private static func contextFullCarriesTwoAndRetries() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return Chat.with { _, model, problems in
            var asked: [String] = []
            var carriedAtAsk: [[AskTurn]] = []
            var failures = 0
            model.responder = { [unowned model] question, show in
                asked.append(question)
                carriedAtAsk.append(model.carried)
                if question == "Q4", failures == 0 {
                    failures += 1
                    show("Half an answer")
                    throw fullContext
                }
                show("Answer to \(question).")
            }
            for question in ["Q1", "Q2", "Q3"] { Chat.ask(model, question) }
            let generation = model.generation
            Chat.ask(model, "Q4")

            expect(asked == ["Q1", "Q2", "Q3", "Q4", "Q4"], "the model was asked \(asked)", &problems)
            let carried = Array(model.turns[1...2])
            expect(carriedAtAsk.last == carried && carriedAtAsk.dropLast().allSatisfy(\.isEmpty),
                   "the retry carried \(carriedAtAsk.last?.map(\.question) ?? []), not Q2 and Q3", &problems)
            expect(model.generation == generation + 1, "the full session was not dropped", &problems)
            expect(model.turns.count == 4 && model.turns[3].state == .answered
                   && model.turns[3].answer == "Answer to Q4.",
                   "the retried turn reads \(String(describing: model.turns.last))", &problems)

            let today = "Wednesday 15 November 2023"
            let text = AskModel.instructions(today: today, carrying: carried)
            expect(text.hasPrefix(versionOne(today: today)), "the instructions no longer begin as before", &problems)
            for turn in carried {
                expect(text.contains("Earlier in this chat the user asked “\(turn.question)” and you answered “\(turn.answer)”."),
                       "the instructions leave out \(turn.question)", &problems)
            }
            expect(!text.contains("Q1") && !text.contains("Q4"), "the instructions carry more than two turns", &problems)
            expect(AskModel.instructions(today: today) == versionOne(today: today),
                   "with nothing carried the instructions differ from version one's", &problems)
        }
    }

    private static func secondFullContextShowsNotice() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return Chat.with { _, model, problems in
            var calls = 0
            model.responder = { _, _ in
                calls += 1
                throw fullContext
            }
            Chat.ask(model, "A very long question")
            expect(calls == 2, "the model was asked \(calls) times, not twice", &problems)
            expect(model.turns.count == 1 && model.turns[0].state == .failed(AskModel.contextFull),
                   "the turn is \(String(describing: model.turns.first?.state))", &problems)
            expect(model.sessionDay == nil && !model.isAnswering, "a full session was kept", &problems)
        }
    }

    // MARK: - The cap

    private static func eighthLookupEndsWithNotice() -> [String] {
        Chat.with { _, model, problems in
            let hold = Gate()
            model.responder = { [unowned model] _, show in
                let began = model.generation
                for _ in 1...9 {
                    hold.texts.append(model.lookup(name: "focusTotals", arguments: Chat.weekTotals,
                                                   generation: model.generation))
                }
                // The tool of the session the answer began under, landing last.
                hold.texts.append(model.lookup(name: "focusTotals", arguments: Chat.weekTotals, generation: began))
                show("Never shown.")
                hold.landed = true
            }
            model.ask("Eight")
            Chat.wait { hold.landed }
            Chat.settle()
            let turn = model.turns[0]
            expect(turn.state == .failed(AskModel.keptLooking) && turn.answer.isEmpty && !model.isAnswering,
                   "the eighth lookup left the turn \(turn.state) reading “\(turn.answer)”", &problems)
            expect(turn.provenance == Array(repeating: "focus totals (this week)", count: AskGate.lookupLimit),
                   "lookups after the fifth were recorded: \(turn.provenance)", &problems)
            let limited = hold.texts[5..<8].map { $0 == AskFacts.lookupLimitReached }
            expect(limited == [true, true, true], "the sixth to eighth lookups were not told the limit", &problems)
            expect(hold.texts[8...].allSatisfy { !$0.isEmpty && $0 != AskFacts.lookupLimitReached },
                   "a lookup after the end was not answered from the store", &problems)
        }
        + Chat.with { _, model, problems in
            let hold = Gate()
            model.responder = { [unowned model] _, show in
                for _ in 1...6 {
                    hold.texts.append(model.lookup(name: "focusTotals", arguments: Chat.weekTotals,
                                                   generation: model.generation))
                }
                show("Done.")
            }
            Chat.ask(model, "Six")
            expect(hold.texts.last == AskFacts.lookupLimitReached && hold.texts.dropLast().allSatisfy { $0 != AskFacts.lookupLimitReached },
                   "only the sixth lookup should be told the limit", &problems)
            expect(model.turns[0].state == .answered && model.turns[0].answer == "Done."
                   && model.turns[0].provenance.count == AskGate.lookupLimit,
                   "the sixth lookup left the turn \(model.turns[0])", &problems)
        }
    }


    /// Version one's instructions, as the model had them with nothing carried.
    private static func versionOne(today: String) -> String {
        "You answer questions about the user's own focus history in Daybook. Today is \(today). "
            + "Look figures up with the tools and answer only from what they return. "
            + "Give the tools the period as the question says it, such as this week, monday, august, "
            + "3 october or 2025, and let the tools work out the dates. "
            + "When the question names no period, use all time; questions about habits, such as "
            + "when do I focus best, cover all time. "
            + "To compare two periods, use compareFocus with each period as the question says it. "
            + "If a tool says a date does not exist, tell the user so. "
            + "Answer what was asked: a question about a day is answered with a day, not a week or a month. "
            + "Copy durations, dates, times and names exactly as the tools give them. "
            + "Never add, subtract, average or compare numbers yourself; the tools give totals, averages, "
            + "the longest session and the difference between two periods. "
            + "Speak of days and periods that are over in the past tense. "
            + "If the tools find nothing, say so plainly. Answer in one to three sentences."
    }
}
