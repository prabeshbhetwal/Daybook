import Foundation

/// A sheet left open across midnight is never opened again, so `prepare()`
/// does not run: a question asked then must drop the session built under
/// yesterday's date itself, or the model keeps telling the date it was told.
enum AskMidnightAskChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Asking after midnight, with the sheet never reopened, starts a session under today's date",
         askingRetiresStaleSession),
    ]

    private static func askingRetiresStaleSession() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return AskThreadChecks.withModel { f, model, problems in
            model.responder = { _, show in show("About two and a half hours.") }
            model.ask("How long this week?")
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            let built = f.calendar.startOfDay(for: f.clock.value)
            let generation = model.generation
            expect(model.sessionDay == built, "the thread's day is \(String(describing: model.sessionDay))", &problems)

            // Past midnight, with no `prepare()` since the first answer.
            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!
            model.ask("And today?")
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            expect(model.generation == generation + 1,
                   "the session built for \(built) was kept for a question asked the next day", &problems)
            let today = f.calendar.startOfDay(for: f.clock.value)
            expect(model.sessionDay == today, "the next session is for \(String(describing: model.sessionDay)), "
                   + "not today (\(today))", &problems)
        }
    }
}
