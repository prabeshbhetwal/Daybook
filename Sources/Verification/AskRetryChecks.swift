import Foundation

/// "Try Again" on a failed or stopped Ask turn: it is offered on the last turn
/// only, asks the question the turn stored as a new turn at the end of the
/// chat, and only when no answer is in progress. Model level only; the button's
/// enabling is `canAsk && !isAnswering`.
enum AskRetryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A failed or stopped last Ask turn can be asked again with the same question, and not while another answer runs",
         retryAsksTheStoredQuestion),
    ]

    private static func retryAsksTheStoredQuestion() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return AskModelChecks.withFixture { f, problems in
            let model = AskModel(store: f.store)
            var asked: [String] = []
            var failNext = true
            var hang = false
            model.responder = { question, show in
                asked.append(question)
                if hang { try await Task.sleep(nanoseconds: 60_000_000_000) }
                if failNext { failNext = false; throw CocoaError(.fileReadNoSuchFile) }
                show("You focused for 1h.")
            }
            @MainActor func settle() { InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5) }

            model.ask("How long this week?")
            settle()
            guard model.turns.count == 1, case .failed = model.turns[0].state else {
                problems.append("the first question did not fail: \(model.turns)")
                return
            }

            // The last turn offers it; an empty chat and a stranger's id do not.
            expect(model.offersTryAgain(model.turns[0].id), "the failed last turn offered no Try Again", &problems)
            expect(!model.offersTryAgain(UUID()), "an unknown turn offered Try Again", &problems)

            // A failed turn is asked again with the same words, in a new last turn.
            model.tryAgain(model.turns[0].id)
            settle()
            expect(asked == ["How long this week?", "How long this week?"], "the model was asked \(asked)", &problems)
            expect(model.turns.count == 2 && model.turns[1].question == "How long this week?"
                   && model.turns[1].state == .answered && model.turns[1].answer == "You focused for 1h.",
                   "the retry left \(model.turns)", &problems)
            if case .failed = model.turns[0].state {} else {
                problems.append("the turn that was retried changed: \(model.turns[0])")
            }

            // The failed turn is no longer last, so it offers nothing and a retry
            // aimed at it does not ask the question a second time.
            expect(!model.offersTryAgain(model.turns[0].id), "an earlier failed turn still offered Try Again", &problems)
            model.tryAgain(model.turns[0].id)
            settle()
            expect(model.turns.count == 2 && asked.count == 2,
                   "an earlier failed turn was retried: \(model.turns.count) turns, asked \(asked)", &problems)

            // An answered turn offers no retry.
            expect(!model.offersTryAgain(model.turns[1].id), "an answered turn offered Try Again", &problems)
            model.tryAgain(model.turns[1].id)
            expect(model.turns.count == 2 && !model.isAnswering, "an answered turn was retried: \(model.turns)", &problems)

            // While an answer runs, a retry of an earlier failed turn is refused.
            hang = true
            model.ask("Second question")
            InstalledAppCatalog.turnRunLoop(until: { asked.count == 3 }, timeout: 5)
            expect(model.isAnswering && model.turns.count == 3, "the slow answer did not start: \(model.turns)", &problems)
            model.tryAgain(model.turns[0].id)
            expect(model.turns.count == 3 && asked.count == 3,
                   "a retry started while answering: \(model.turns.count) turns, asked \(asked)", &problems)

            // A stopped turn can be asked again once the answer is over.
            model.stop()
            expect(model.turns[2].state == .stopped, "Stop left \(model.turns[2].state)", &problems)
            expect(model.offersTryAgain(model.turns[2].id), "the stopped last turn offered no Try Again", &problems)
            hang = false
            model.tryAgain(model.turns[2].id)
            settle()
            expect(model.turns.count == 4 && model.turns[3].question == "Second question"
                   && model.turns[3].state == .answered && asked.last == "Second question",
                   "the stopped turn's retry left \(model.turns.map(\.question)), asked \(asked)", &problems)
        }
    }
}
