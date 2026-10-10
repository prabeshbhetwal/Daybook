import Foundation

/// An Ask thread outlives each answer: a lookup that lands after New question
/// must not write into the next answer, the previous answer leaves the screen
/// while a new one is worked out, and a thread kept past midnight is told
/// today's date again. None starts a `LanguageModelSession`: the model's
/// `responder` seam stands in for the model.
enum AskThreadChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A lookup landing after New question is not listed under the next answer", staleLookupIsNotRecorded),
        ("Asking clears the previous answer while the new one is worked out", askingClearsPreviousAnswer),
        ("Opening Ask on a new day drops the old session and keeps the answer shown", staleDayDropsSession),
    ]

    /// A responder that waits until the check releases it.
    private final class Gate {
        var release: CheckedContinuation<Void, Never>?
        var generation = 0
        var landed = false
    }

    /// The Ask fixture with an Ask model, on the main actor where it lives.
    static func withModel(_ body: @MainActor (AskLookupChecks.Fixture, AskModel, inout [String]) -> Void)
        -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated { body(f, AskModel(store: f.store), &problems) }
        }
    }

    private static func staleLookupIsNotRecorded() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return withModel { _, model, problems in
            let gate = Gate()
            model.responder = { [unowned model] question, _ in
                if question == "first" {
                    // What a tool captures when its session is built, used once the answer was abandoned.
                    gate.generation = model.generation
                    await withCheckedContinuation { gate.release = $0 }
                    _ = model.lookup(.bestHours(.today), generation: gate.generation)
                    gate.landed = true
                } else {
                    _ = model.lookup(.focusTotals(.thisWeek, words: nil), generation: model.generation)
                }
            }
            model.ask("first")
            InstalledAppCatalog.turnRunLoop(until: { gate.release != nil }, timeout: 5)
            model.newQuestion()
            model.ask("second")
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            gate.release?.resume()
            InstalledAppCatalog.turnRunLoop(until: { gate.landed }, timeout: 5)
            expect(gate.landed, "the abandoned answer's lookup never ran, so nothing was compared", &problems)
            expect(model.used == "Used: focus totals (this week)",
                   "the next answer's Used line reads “\(model.used)”", &problems)
        }
    }

    private static func askingClearsPreviousAnswer() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return withModel { _, model, problems in
            let gate = Gate()
            model.responder = { _, _ in await withCheckedContinuation { gate.release = $0 } }
            model.present(answer: "Earlier answer.", used: "Used: best hours (today)")
            model.ask("How long this week?")
            expect(model.isAnswering && model.answer.isEmpty,
                   "while the new answer is worked out the sheet shows “\(model.answer)”", &problems)
            InstalledAppCatalog.turnRunLoop(until: { gate.release != nil }, timeout: 5)
            gate.release?.resume()
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            expect(!model.isAnswering, "the answer never finished", &problems)
        }
    }

    private static func staleDayDropsSession() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return withModel { f, model, problems in
            let gate = Gate()
            model.responder = { [unowned model] question, show in
                _ = model.lookup(.focusTotals(.thisWeek, words: nil), generation: model.generation)
                show("About two and a half hours.")
                if question == "held" { await withCheckedContinuation { gate.release = $0 } }
            }
            // Where `prepare()` would start the model, the same step is taken without it.
            @MainActor func open() { if model.canAsk { model.retireStaleSession() } else { model.prepare() } }
            func midnight(after days: Int) -> Date {
                f.calendar.startOfDay(for: f.calendar.date(byAdding: .day, value: days, to: f.clock.value)!)
            }

            model.ask("How long this week?")
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            let built = f.calendar.startOfDay(for: f.clock.value)
            expect(model.sessionDay == built, "the thread's day is \(String(describing: model.sessionDay))", &problems)
            let generation = model.generation

            f.clock.advance(3 * 3_600)
            open()
            expect(model.sessionDay == built, "opening Ask later the same day dropped the session", &problems)

            // Asked on the first day, still being worked out when midnight passes.
            model.ask("held")
            InstalledAppCatalog.turnRunLoop(until: { gate.release != nil }, timeout: 5)
            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!
            open()
            expect(model.sessionDay == built, "opening Ask while an answer was in progress dropped the session",
                   &problems)
            gate.release?.resume()
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)

            let heldAnswer = (model.answer, model.used)
            open()
            expect(model.sessionDay == nil, "a session built for \(built) survived to \(midnight(after: 0))", &problems)
            expect(model.generation == generation + 1, "the dropped session's tools are still current", &problems)
            expect((model.answer, model.used) == heldAnswer, "dropping the session cleared what the sheet shows",
                   &problems)

            model.ask("again")
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            expect(model.sessionDay == midnight(after: 0), "the next session is for \(String(describing: model.sessionDay)), "
                   + "not today (\(midnight(after: 0)))", &problems)
        }
    }
}
