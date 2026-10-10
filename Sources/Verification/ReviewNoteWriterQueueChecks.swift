import Foundation

/// A note set aside for a newer request: the writer writes one note at a
/// time, so a period opened while another is being written waits, and is
/// written once the newer one is done, unless its view has gone. Shares the
/// stand-in model and fixture helpers of `ReviewNoteWriterChecks`.
enum ReviewNoteWriterQueueChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A period set aside for a newer one is written when the newer one is done", setAsideIsWrittenLater),
        ("A period whose view went away while it waited is not written", leftViewIsNotWritten),
        ("Periods set aside are written newest first", newestFirst),
        ("Switching off while a period waits leaves it with no note and no state", switchOffDropsWaiting),
    ]

    private typealias Checks = ReviewNoteWriterChecks
    private static let plain = Checks.plain

    @MainActor private static func wait(_ condition: () -> Bool) -> Bool {
        InstalledAppCatalog.turnRunLoop(until: condition, timeout: 5)
    }

    private static func setAsideIsWrittenLater() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = Checks.day(f, back: 1)
            let monday = Checks.day(f, back: 2)
            writer.request(tuesday, requested: false)
            expect(wait { model.entered == 1 }, "Tuesday's note was never asked for", &problems)
            writer.request(monday, requested: false)
            expect(wait { model.entered == 2 }, "Monday's note was never asked for", &problems)
            expect(writer.state(for: tuesday) == .writing,
                   "Tuesday, set aside, shows \(String(describing: writer.state(for: tuesday)))", &problems)
            model.release()
            expect(wait { model.returned == 1 }, "Tuesday's stopped call never returned", &problems)
            model.release()
            expect(Checks.settle(writer, monday) && writer.state(for: monday) == .written(plain),
                   "Monday's note is \(String(describing: writer.state(for: monday)))", &problems)
            expect(wait { model.entered == 3 }, "Tuesday was not written once Monday's note was done", &problems)
            model.release()
            expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .written(plain),
                   "Tuesday's note is \(String(describing: writer.state(for: tuesday)))", &problems)
            expect(model.calls == 3, "the model was asked \(model.calls) times, not three", &problems)
        }
    }

    private static func leftViewIsNotWritten() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = Checks.day(f, back: 1)
            let monday = Checks.day(f, back: 2)
            writer.request(tuesday, requested: true)
            expect(wait { model.entered == 1 }, "Tuesday's note was never asked for", &problems)
            writer.request(monday, requested: true)
            expect(wait { model.entered == 2 }, "Monday's note was never asked for", &problems)
            writer.cancel(tuesday)
            expect(writer.state(for: tuesday) == nil,
                   "Tuesday, whose view went, shows \(String(describing: writer.state(for: tuesday)))", &problems)
            model.release()
            expect(wait { model.returned == 1 }, "Tuesday's stopped call never returned", &problems)
            model.release()
            expect(Checks.settle(writer, monday) && writer.state(for: monday) == .written(plain),
                   "Monday's note is \(String(describing: writer.state(for: monday)))", &problems)
            InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.2)
            expect(model.calls == 2 && writer.state(for: tuesday) == nil,
                   "after \(model.calls) calls Tuesday shows \(String(describing: writer.state(for: tuesday)))", &problems)
        }
    }

    private static func newestFirst() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = Checks.day(f, back: 1)
            let monday = Checks.day(f, back: 2)
            let october = Checks.day(f, back: 29)
            for (count, place) in [tuesday, monday, october].enumerated() {
                writer.request(place, requested: false)
                expect(wait { model.entered == count + 1 }, "the note for place \(count + 1) was never asked for", &problems)
            }
            // The first two calls were stopped; the third is the one being written.
            model.release()
            expect(wait { model.returned == 1 }, "Tuesday's stopped call never returned", &problems)
            model.release()
            expect(wait { model.returned == 2 }, "Monday's stopped call never returned", &problems)
            model.release()
            expect(wait { model.entered == 4 }, "nothing was written after October's note", &problems)
            expect(model.facts.count == 4 && model.facts[3] == f.store.noteFacts(for: monday),
                   "after October the model was asked for \(model.facts.last?.lines.first ?? "nothing"), not Monday", &problems)
            model.release()
            expect(wait { model.entered == 5 }, "nothing was written after Monday's note", &problems)
            expect(model.facts.count == 5 && model.facts[4] == f.store.noteFacts(for: tuesday),
                   "after Monday the model was asked for \(model.facts.last?.lines.first ?? "nothing"), not Tuesday", &problems)
            model.release()
            expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .written(plain),
                   "Tuesday's note is \(String(describing: writer.state(for: tuesday)))", &problems)
        }
    }

    private static func switchOffDropsWaiting() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = Checks.day(f, back: 1)
            let monday = Checks.day(f, back: 2)
            writer.request(tuesday, requested: true)
            expect(wait { model.entered == 1 }, "Tuesday's note was never asked for", &problems)
            writer.request(monday, requested: true)
            expect(wait { model.entered == 2 }, "Monday's note was never asked for", &problems)
            f.store.engine.store.useAppleIntelligence = false
            model.release()
            expect(wait { model.returned == 1 }, "Tuesday's stopped call never returned", &problems)
            model.release()
            expect(wait { model.returned == 2 }, "Monday's call never returned", &problems)
            InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.2)
            expect(writer.states.isEmpty, "a switched-off writer is left showing \(writer.states)", &problems)
            expect(model.calls == 2, "a switched-off writer asked the model \(model.calls) times", &problems)
        }
    }
}
