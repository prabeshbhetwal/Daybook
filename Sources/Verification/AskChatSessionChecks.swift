import Foundation

/// Which session an Ask answer belongs to, and which day it is read on: what a
/// session dropped on the second day is told about the first, the day an
/// answer that finishes after midnight reads "yesterday" against, and what a
/// failed answer leaves behind for the one after it. None starts a
/// `LanguageModelSession`: the model's `responder` seam stands in for it.
enum AskChatSessionChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("On the second day Stop and a full context carry nothing from the first", secondDayCarriesNothingFromFirst),
        ("An answer finishing after midnight reads yesterday as of the day it was asked", yesterdayIsReadAtAskTime),
        ("A failed answer drops its session, so its late lookups are not counted in the next", failureDropsSession),
    ]

    private typealias Chat = AskChatChecks
    private typealias Gate = AskThreadChecks.Gate

    private static func secondDayCarriesNothingFromFirst() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return Chat.with { f, model, problems in
            let hold = Gate()
            var carriedAtAsk: [[AskTurn]] = []
            var fullOnce = true
            model.responder = { [unowned model] question, show in
                carriedAtAsk.append(model.carried)
                if question == "full", fullOnce {
                    fullOnce = false
                    throw AskChatEndingChecks.fullContext
                }
                show("Answer to \(question).")
                if question == "held" { await withCheckedContinuation { hold.release = $0 } }
            }
            Chat.ask(model, "Q1")
            Chat.ask(model, "Q2")
            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!

            model.ask("held")
            Chat.wait { hold.release != nil }
            model.stop()
            expect(model.carried.isEmpty,
                   "Stop on the second day carried \(model.carried.map(\.question)) from the first", &problems)
            Chat.ask(model, "A")
            expect(carriedAtAsk.last?.isEmpty == true,
                   "the next question was asked carrying \(carriedAtAsk.last?.map(\.question) ?? [])", &problems)

            // A full context on the second day carries the second day's answers, and only those.
            Chat.ask(model, "full")
            let today = model.turns.filter { $0.question == "A" }
            expect(!today.isEmpty && carriedAtAsk.last == today,
                   "the retry carried \(carriedAtAsk.last?.map(\.question) ?? []), not just A", &problems)
            expect(model.turns.map(\.question) == ["Q1", "Q2", "held", "A", "full"],
                   "the transcript on screen changed: \(model.turns.map(\.question))", &problems)
        }
    }

    private static func yesterdayIsReadAtAskTime() -> [String] {
        Chat.with { f, model, problems in
            let hold = Gate()
            model.responder = { [unowned model] _, show in
                _ = model.lookup(name: "focusTotals", arguments: ["range": "yesterday"], generation: model.generation)
                show("Yesterday you focused 1h 30m.")
                await withCheckedContinuation { hold.release = $0 }
            }
            model.ask("What about yesterday?")
            Chat.wait { hold.release != nil }
            let yesterday = f.calendar.date(byAdding: .day, value: -1, to: f.calendar.startOfDay(for: f.clock.value))!

            // The lookup was made on one day and the answer finishes on the next.
            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!
            hold.release?.resume()
            Chat.wait { !model.isAnswering }
            let first = model.turns[0].sources.first
            expect(first?.link.target == .day(yesterday) && first?.mention != nil,
                   "the first source is \(String(describing: first)), not yesterday named in the answer", &problems)
        }
    }

    private static func failureDropsSession() -> [String] {
        Chat.with { _, model, problems in
            let hold = Gate()
            model.responder = { [unowned model] question, show in
                if question == "first" {
                    hold.generation = model.generation
                    throw CocoaError(.fileReadNoSuchFile)
                }
                // What a tool of the failed run does once the next answer is under way.
                _ = model.lookup(name: "bestHours", arguments: ["range": "today"], generation: hold.generation)
                _ = model.lookup(name: "focusTotals", arguments: Chat.weekTotals, generation: model.generation)
                show("Fresh words.")
            }
            Chat.ask(model, "first")
            let generation = model.generation
            expect(hold.generation + 1 == generation && model.sessionDay == nil,
                   "the failed answer kept its session: generation \(generation), built under \(hold.generation)",
                   &problems)
            Chat.ask(model, "next")
            expect(model.turns.last?.provenance == ["focus totals (this week)"],
                   "the next answer rests on \(String(describing: model.turns.last?.provenance))", &problems)
        }
    }
}
