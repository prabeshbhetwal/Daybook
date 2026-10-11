import Foundation

/// What the note writer does with a note that fails: it is shown as a failure
/// and not asked for again until its facts change, a person's failure line
/// survives automatic requests, and a note with nothing in it counts as a
/// failure. Shares the stand-in model and fixture helpers of
/// `ReviewNoteWriterChecks`.
enum ReviewNoteWriterFailureChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A failed note is not asked for again until its facts change", failureNotRetried),
        ("An automatic request never hides the failure a person asked to see", askedFailureStays),
        ("A note with a blank story or pattern is a failure", blankIsFailure),
    ]

    private typealias Checks = ReviewNoteWriterChecks
    private static let plain = Checks.plain

    private static let invented = WrittenNote(story: "You focused 9h 59m.", pattern: "Nothing else.", tip: nil)

    private static func failureNotRetried() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.answer(invented)
            let tuesday = Checks.day(f, back: 1)
            writer.request(tuesday, requested: false)
            expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .failed(requested: false),
                   "the first note is \(String(describing: writer.state(for: tuesday)))", &problems)
            writer.request(tuesday, requested: false)
            expect(writer.state(for: tuesday) == .failed(requested: false),
                   "asking again for the same facts shows \(String(describing: writer.state(for: tuesday)))", &problems)
            InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.1)
            expect(model.calls == 1, "the model was asked \(model.calls) times for facts that had failed", &problems)

            // Changed facts are a new note: they are asked for, and can succeed.
            writer.responder = model.answer(plain)
            guard let parser = Checks.session(on: tuesday, f) else { problems.append("Tuesday has no session to rename"); return }
            expect(f.store.renameSession(parser, to: "Lexer"), "the rename was refused", &problems)
            writer.request(tuesday, requested: false)
            expect(writer.state(for: tuesday) == .writing, "renamed facts show \(String(describing: writer.state(for: tuesday)))", &problems)
            expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .written(plain) && model.calls == 2,
                   "after the rename the note is \(String(describing: writer.state(for: tuesday))) after \(model.calls) calls", &problems)
        }
    }

    private static func askedFailureStays() -> [String] {
        Checks.withWriter { f, writer, model, problems in
            writer.responder = model.answer(invented)
            let tuesday = Checks.day(f, back: 1)
            writer.request(tuesday, requested: true)
            expect(Checks.settle(writer, tuesday), "the requested note never settled", &problems)
            writer.request(tuesday, requested: false)
            expect(writer.state(for: tuesday) == .failed(requested: true),
                   "an automatic request left \(String(describing: writer.state(for: tuesday))) where the person's failure was", &problems)
            // A day with no facts fails without the model, and the same holds.
            let empty = Checks.day(f, back: -4)
            writer.request(empty, requested: true)
            writer.request(empty, requested: false)
            expect(writer.state(for: empty) == .failed(requested: true),
                   "an automatic request left \(String(describing: writer.state(for: empty))) on a day with no sessions", &problems)
            expect(model.calls == 1, "the model was asked \(model.calls) times", &problems)
        }
    }

    private static func blankIsFailure() -> [String] {
        Checks.withWriter { f, _, model, problems in
            let tuesday = Checks.day(f, back: 1)
            let blanks = [("", "Focus began after lunch."), ("You worked on Parser.", "  \n"), (" ", "")]
            for (story, pattern) in blanks {
                let writer = NoteWriter(store: f.store)
                writer.responder = model.answer(WrittenNote(story: story, pattern: pattern, tip: "Start early."))
                writer.request(tuesday, requested: false)
                expect(Checks.settle(writer, tuesday), "the note for “\(story)” and “\(pattern)” never settled", &problems)
                expect(writer.state(for: tuesday) == .failed(requested: false),
                       "the story “\(story)” with the pattern “\(pattern)” left \(String(describing: writer.state(for: tuesday)))", &problems)
            }
        }
    }
}
