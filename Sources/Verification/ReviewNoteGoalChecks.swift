import Foundation

/// A day's facts and the Yesterday figures line state the daily goal and weigh
/// the day against it, so a new goal changes both. The evidence a note on
/// screen is checked against, and the cause of Today's offers, had left the
/// goal out: a note kept the old goal's wording, and the figures line the old
/// "goal met". Uses the Ask fixture: Tuesday has 1h 30m of Parser with 1h of
/// credit, the clock is on Wed 15 Nov at 9:13.
enum ReviewNoteGoalChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The evidence a note is checked against moves with the daily goal and not when the goal is set to what it was",
         evidenceMovesWithGoal),
        ("A note written for one goal is forgotten as stale once the goal changes", noteForgottenOnNewGoal),
        ("Today's offers are rebuilt when the goal changes or yesterday is corrected, and not otherwise", offersRebuilt),
    ]

    private typealias Checks = ReviewNoteWriterChecks

    private static func evidenceMovesWithGoal() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.engine.store.dailyGoal = 3_600
            let before = f.store.noteEvidence
            f.engine.store.dailyGoal = 3_600
            expect(f.store.noteEvidence == before, "setting the goal to what it was moved the evidence", &problems)
            f.engine.store.dailyGoal = 5_400
            expect(f.store.noteEvidence != before, "a new goal left the evidence as it was: \(f.store.noteEvidence)", &problems)
        }
    }

    private static func noteForgottenOnNewGoal() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            f.engine.store.dailyGoal = 3_600
            writer.responder = model.answer(Checks.plain)
            let tuesday = Checks.day(f, back: 1)
            writer.request(tuesday, requested: true)
            expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .written(Checks.plain),
                   "the note is \(String(describing: writer.state(for: tuesday)))", &problems)
            writer.forgetIfStale(tuesday)
            expect(writer.state(for: tuesday) == .written(Checks.plain), "an unchanged goal forgot the note", &problems)
            f.engine.store.dailyGoal = 5_400
            writer.forgetIfStale(tuesday)
            expect(writer.state(for: tuesday) == nil,
                   "a new goal left the note as \(String(describing: writer.state(for: tuesday)))", &problems)
            writer.request(tuesday, requested: true)
            expect(Checks.settle(writer, tuesday) && model.calls == 2
                   && model.facts.last?.lines.contains("Daily goal: 1h 30m, met: no") == true,
                   "the note was not written again for the new goal after \(model.calls) calls", &problems)
        }
    }

    private static func offersRebuilt() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            func cause() -> TodayNoteOffers.Cause { MainActor.assumeIsolated { TodayNoteOffers.cause(store: f.store, usable: true) } }
            func offers() -> TodayNoteOffers { MainActor.assumeIsolated { TodayNoteOffers(store: f.store, usable: true) } }
            f.engine.store.dailyGoal = 3_600
            let before = cause()
            let line = offers().yesterdayFigures
            expect(cause() == before, "a store that did not change gave a different cause", &problems)
            expect(line == "1h 30m focus · goal met · 1 session", "yesterday's line at a 1h goal is “\(line)”", &problems)

            f.engine.store.dailyGoal = 5_400
            let newGoal = cause()
            expect(newGoal != before, "a new goal left the cause as it was", &problems)
            expect(offers().yesterdayFigures == "1h 30m focus · goal missed · 1 session",
                   "yesterday's line at a 1h 30m goal is “\(offers().yesterdayFigures)”", &problems)

            // Yesterday corrected: renamed here, as a correction moves the same revisions.
            guard let parser = Checks.session(on: Checks.day(f, back: 1), f) else {
                problems.append("yesterday has no session to correct")
                return
            }
            expect(f.store.renameSession(parser, to: "Lexer"), "the rename was refused", &problems)
            expect(cause() != newGoal, "a correction to yesterday left the cause as it was", &problems)
        }
    }
}
