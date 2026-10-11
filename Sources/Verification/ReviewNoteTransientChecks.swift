import Foundation
import FoundationModels

/// What the note writer remembers when the model throws. A refusal, a held
/// guardrail, an unread language or a context that is too full would fail the
/// same way again, so those are remembered like a failed audit. Anything else
/// is the Mac's state: the live probe was refused from its eleventh note on,
/// under memory pressure, with "try again later", and the writer then never
/// asked for those periods again. Shares the stand-in model of
/// `ReviewNoteWriterChecks`, whose responder here throws.
enum ReviewNoteTransientChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A model error that is the Mac's state is not remembered, so the next request asks again", stateNotRemembered),
        ("A refusal, a held guardrail, an unread language or a full context is remembered like a failed audit", factsRemembered),
        ("A failure that was not remembered returns an on-request note to its link, and a remembered one stays", linkReturns),
    ]

    private typealias Checks = ReviewNoteWriterChecks

    private static func throwing(_ error: Error, _ model: Checks.Model) -> @MainActor (NoteFacts) async throws -> WrittenNote {
        { _ in
            model.calls += 1
            throw error
        }
    }

    /// Errors that say nothing about the facts: macOS 26's, an unknown one, and macOS 27's.
    @available(macOS 26, *)
    private static func stateErrors() -> [(String, Error)] {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "probe")
        var errors: [(String, Error)] = [
            ("rate limited", LanguageModelSession.GenerationError.rateLimited(context)),
            ("assets unavailable", LanguageModelSession.GenerationError.assetsUnavailable(context)),
            ("a Cocoa error", CocoaError(.fileReadNoSuchFile)),
            ("the live probe's refusal under memory pressure",
             NSError(domain: "FoundationModels.LanguageModelError", code: -1)),
        ]
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            errors.append(("timed out", LanguageModelError.timeout(.init(debugDescription: "probe"))))
        }
        #endif
        return errors
    }

    /// Errors the same facts would draw again.
    @available(macOS 26, *)
    private static func factsErrors() -> [(String, Error)] {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "probe")
        var errors: [(String, Error)] = [
            ("context exceeded", LanguageModelSession.GenerationError.exceededContextWindowSize(context)),
            ("guardrail", LanguageModelSession.GenerationError.guardrailViolation(context)),
            ("refusal", LanguageModelSession.GenerationError.refusal(.init(transcriptEntries: []), context)),
            ("unsupported language", LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)),
        ]
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            errors += [
                ("context exceeded (macOS 27)", LanguageModelError.contextSizeExceeded(
                    .init(contextSize: 4_096, tokenCount: 9_000, debugDescription: "probe"))),
                ("guardrail (macOS 27)", LanguageModelError.guardrailViolation(.init(debugDescription: "probe"))),
                ("refusal (macOS 27)", LanguageModelError.refusal(.init(explanation: "no", debugDescription: "probe"))),
                ("unsupported language (macOS 27)", LanguageModelError.unsupportedLanguageOrLocale(
                    .init(languageCode: .english, debugDescription: "probe"))),
            ]
        }
        #endif
        return errors
    }

    private static func stateNotRemembered() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return Checks.withWriter { f, _, model, problems in
            let tuesday = Checks.day(f, back: 1)
            for (name, error) in stateErrors() {
                let writer = NoteWriter(store: f.store)
                let before = model.calls
                writer.responder = throwing(error, model)
                writer.request(tuesday, requested: false)
                expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .failed(requested: false),
                       "\(name): the first request left \(String(describing: writer.state(for: tuesday)))", &problems)
                writer.request(tuesday, requested: false)
                expect(writer.state(for: tuesday) == .writing,
                       "\(name): asking again left \(String(describing: writer.state(for: tuesday))), not a new write", &problems)
                expect(Checks.settle(writer, tuesday) && model.calls - before == 2,
                       "\(name): the model was asked \(model.calls - before) times, not twice", &problems)
                // The Mac recovering is a note: the next request is served.
                writer.responder = model.answer(Checks.plain)
                writer.request(tuesday, requested: false)
                expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .written(Checks.plain),
                       "\(name): after the Mac recovered the note is \(String(describing: writer.state(for: tuesday)))", &problems)
            }
        }
    }

    private static func factsRemembered() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return Checks.withWriter { f, _, model, problems in
            let tuesday = Checks.day(f, back: 1)
            for (name, error) in factsErrors() {
                let writer = NoteWriter(store: f.store)
                let before = model.calls
                writer.responder = throwing(error, model)
                writer.request(tuesday, requested: false)
                expect(Checks.settle(writer, tuesday) && writer.state(for: tuesday) == .failed(requested: false),
                       "\(name): the first request left \(String(describing: writer.state(for: tuesday)))", &problems)
                writer.request(tuesday, requested: true)
                InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.05)
                expect(writer.state(for: tuesday) == .failed(requested: true) && model.calls - before == 1,
                       "\(name): asking again left \(String(describing: writer.state(for: tuesday))) after \(model.calls - before) calls", &problems)
            }
        }
    }

    private static func linkReturns() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return Checks.withWriter { f, _, model, problems in
            let tuesday = Checks.day(f, back: 1)
            // The Mac's state: the failure line shows, then the link is back when the view appears again.
            let busy = NoteWriter(store: f.store)
            busy.responder = throwing(NSError(domain: "FoundationModels.LanguageModelError", code: -1), model)
            busy.request(tuesday, requested: true)
            expect(Checks.settle(busy, tuesday) && busy.state(for: tuesday) == .failed(requested: true),
                   "a requested note the Mac could not write shows \(String(describing: busy.state(for: tuesday)))", &problems)
            busy.forgetIfStale(tuesday)
            expect(busy.state(for: tuesday) == nil,
                   "the failure stayed where a link should return: \(String(describing: busy.state(for: tuesday)))", &problems)

            // The facts: the failure stays, since asking again would fail again.
            let refused = NoteWriter(store: f.store)
            refused.responder = throwing(LanguageModelSession.GenerationError.guardrailViolation(
                .init(debugDescription: "probe")), model)
            refused.request(tuesday, requested: true)
            expect(Checks.settle(refused, tuesday), "the refused note never settled", &problems)
            refused.forgetIfStale(tuesday)
            expect(refused.state(for: tuesday) == .failed(requested: true),
                   "a refused note's failure was forgotten: \(String(describing: refused.state(for: tuesday)))", &problems)

            // No facts at all: no link either.
            let empty = Checks.day(f, back: -4)
            refused.request(empty, requested: true)
            refused.forgetIfStale(empty)
            expect(refused.state(for: empty) == .failed(requested: true),
                   "a day with no sessions was forgotten: \(String(describing: refused.state(for: empty)))", &problems)
        }
    }
}
