import Foundation

/// What a note's state in the writer answers to once it is published: a note
/// or failure shown for figures that have since changed is forgotten when its
/// view asks, and switching Apple Intelligence off stops every note being
/// written. Shares the stand-in model and fixture helpers of
/// `ReviewNoteWriterChecks`.
enum ReviewNoteWriterStateChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A note or failure shown for figures that have changed is forgotten, one for the same figures is kept",
         staleStateForgotten),
        ("A note being written is not forgotten when the figures change", writingKept),
        ("Cancelling every note stops the one being written and drops those waiting", cancelAllStops),
    ]

    private typealias Checks = ReviewNoteWriterChecks
    private static let plain = Checks.plain
    private static let invented = WrittenNote(story: "You focused 9h 59m.", pattern: "Nothing else.", tip: nil)

    @MainActor private static func wait(_ condition: () -> Bool) -> Bool {
        InstalledAppCatalog.turnRunLoop(until: condition, timeout: 5)
    }

    /// On-request notes: written on Tuesday, failed on Monday, then a session on
    /// the day is renamed, which changes the day's facts.
    private static func staleStateForgotten() -> [String] {
        Checks.withWriter { f, _, model, problems in
            let cases: [(back: Int, answer: WrittenNote, shown: NoteState)] = [
                (1, plain, .written(plain)), (2, invented, .failed(requested: true))]
            for (back, answer, shown) in cases {
                let writer = NoteWriter(store: f.store)
                writer.responder = model.answer(answer)
                let place = Checks.day(f, back: back)
                writer.request(place, requested: true)
                expect(Checks.settle(writer, place) && writer.state(for: place) == shown,
                       "the note asked for is \(String(describing: writer.state(for: place))), not \(shown)", &problems)
                writer.forgetIfStale(place)
                expect(writer.state(for: place) == shown,
                       "unchanged facts left \(String(describing: writer.state(for: place))), not \(shown)", &problems)
                guard let session = Checks.session(on: place, f) else { problems.append("the day has no session"); return }
                expect(f.store.renameSession(session, to: "Renamed \(back)"), "the rename was refused", &problems)
                writer.forgetIfStale(place)
                expect(writer.state(for: place) == nil,
                       "changed facts left \(String(describing: writer.state(for: place))) on screen", &problems)
            }
        }
    }

    private static func writingKept() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = Checks.day(f, back: 1)
            writer.request(tuesday, requested: true)
            expect(wait { model.entered == 1 }, "the model was never asked", &problems)
            guard let session = Checks.session(on: tuesday, f) else { problems.append("Tuesday has no session"); return }
            expect(f.store.renameSession(session, to: "Lexer"), "the rename was refused", &problems)
            writer.forgetIfStale(tuesday)
            expect(writer.state(for: tuesday) == .writing,
                   "a note being written shows \(String(describing: writer.state(for: tuesday)))", &problems)
            model.release()
            expect(Checks.settle(writer, tuesday), "the note never settled", &problems)
        }
    }

    private static func cancelAllStops() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = Checks.day(f, back: 1)
            let monday = Checks.day(f, back: 2)
            writer.request(tuesday, requested: true)
            expect(wait { model.entered == 1 }, "Tuesday's note was never asked for", &problems)
            writer.request(monday, requested: true)
            expect(wait { model.entered == 2 }, "Monday's note was never asked for", &problems)
            // Monday is being written and Tuesday waits behind it.
            writer.cancelAll()
            expect(writer.states.isEmpty, "after cancelling all, the writer shows \(writer.states)", &problems)
            model.release()
            expect(wait { model.returned == 1 }, "Tuesday's stopped call never returned", &problems)
            model.release()
            expect(wait { model.returned == 2 }, "Monday's stopped call never returned", &problems)
            InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.2)
            expect(writer.states.isEmpty, "the late answers left \(writer.states)", &problems)
            expect(model.calls == 2, "the model was asked \(model.calls) times: a waiting note was started again", &problems)
            // Nothing is left stuck: the next request is written.
            writer.responder = model.answer(plain)
            writer.request(monday, requested: true)
            expect(Checks.settle(writer, monday) && writer.state(for: monday) == .written(plain),
                   "a request after cancelling all shows \(String(describing: writer.state(for: monday)))", &problems)
        }
    }
}
