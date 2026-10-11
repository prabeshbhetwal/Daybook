import Combine
import Foundation
import FoundationModels

/// Ask Daybook's model layer without a model: the words shown when it cannot
/// answer, the lookups it records and the chat's state. None of these
/// starts a `LanguageModelSession`; its answers are not repeatable, and a
/// runner with Apple Intelligence off has none to give. The tools it is handed
/// are `AskCatalogueChecks`'.
enum AskModelChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask says plainly why it cannot answer, for every availability and error", noticesCoverEveryCase),
        ("Ask's provenance lists each lookup of an answer in order, and a new chat empties the turns",
         provenanceRecordsLookups),
        ("A blank Ask question is ignored", blankQuestionIsIgnored),
        ("Opening Ask twice builds its model once", askModelIsBuiltOnce),
        ("A failed Ask answer changes only its own turn", failedAnswerChangesOnlyItsTurn),
        ("Whether Ask can answer is read when it opens, asks or starts over, and published only when it changes",
         availabilityIsPublishedState),
    ]

    private static func notice(_ text: String, opensSettings: Bool = false) -> AskNotice {
        AskNotice(text: text, opensSettings: opensSettings)
    }

    /// The Ask fixture with the body on the main actor, where `AskModel` lives.
    static func withFixture(_ body: @MainActor (AskLookupChecks.Fixture, inout [String]) -> Void) -> [String] {
        AskLookupChecks.withFixture { f, problems in MainActor.assumeIsolated { body(f, &problems) } }
    }

    // MARK: - Notices

    private static func noticesCoverEveryCase() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        var problems: [String] = []
        let availability: [(SystemLanguageModel.Availability, AskNotice?)] = [
            (.available, nil),
            (.unavailable(.deviceNotEligible), notice("This Mac can't run Apple's on-device model.")),
            (.unavailable(.appleIntelligenceNotEnabled),
             notice("Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri.",
                    opensSettings: true)),
            (.unavailable(.modelNotReady), notice("The on-device model is still downloading. Try again shortly.")),
        ]
        for (input, want) in availability {
            let got = AskModel.notice(for: input)
            expect(got == want, "\(input) gives \(String(describing: got)), not \(String(describing: want))", &problems)
        }

        let context = LanguageModelSession.GenerationError.Context(debugDescription: "probe")
        let full = AskModel.contextFull
        let refused = notice("Can't answer that one.")
        let language = notice("Ask doesn't understand this language yet.")
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        var errors: [(Error, AskNotice)] = [
            (LanguageModelSession.GenerationError.exceededContextWindowSize(context), full),
            (LanguageModelSession.GenerationError.guardrailViolation(context), refused),
            (LanguageModelSession.GenerationError.refusal(refusal, context), refused),
            (LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context), language),
        ]
        // Anything else is worded from the error itself.
        let others: [Error] = [LanguageModelSession.GenerationError.rateLimited(context),
                               LanguageModelSession.GenerationError.assetsUnavailable(context),
                               CocoaError(.fileReadNoSuchFile)]
        for error in others { errors.append((error, notice("Couldn't answer: \(error.localizedDescription)"))) }
        errors += newerErrors()
        for (index, (error, want)) in errors.enumerated() {
            let got = AskModel.notice(for: error)
            expect(got == want, "error \(index) (\(type(of: error))) gives \(got), not \(want)", &problems)
        }
        return problems
    }

    /// macOS 27 throws `LanguageModelError` where macOS 26 threw
    /// `GenerationError` (probed 2026-10-09: an over-long prompt on macOS 27.2
    /// throws `LanguageModelError.contextSizeExceeded`). The type exists only
    /// in the newer SDK, so these rows are compiled and run only there.
    @available(macOS 26, *)
    private static func newerErrors() -> [(Error, AskNotice)] {
        #if compiler(>=6.4)
        guard #available(macOS 27, *) else { return [] }
        let full = AskModel.contextFull
        let refused = notice("Can't answer that one.")
        let timeout = LanguageModelError.timeout(.init(debugDescription: "probe"))
        return [
            (LanguageModelError.contextSizeExceeded(.init(contextSize: 4_096, tokenCount: 9_000,
                                                          debugDescription: "probe")), full),
            (LanguageModelError.guardrailViolation(.init(debugDescription: "probe")), refused),
            (LanguageModelError.refusal(.init(explanation: "no", debugDescription: "probe")), refused),
            (LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .english, debugDescription: "probe")),
             notice("Ask doesn't understand this language yet.")),
            (timeout, notice("Couldn't answer: \(timeout.localizedDescription)")),
        ]
        #else
        return []
        #endif
    }

    // MARK: - The model's own state

    private static func provenanceRecordsLookups() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return withFixture { f, problems in
            let model = AskModel(store: f.store)
            let totals = AskRequest.focusTotals(.thisWeek, words: nil)
            var text = ""
            model.responder = { [unowned model] _, _ in
                text = model.lookup(name: "focusTotals", arguments: ["range": "this week"], generation: model.generation)
                _ = model.lookup(name: "bestHours", arguments: ["range": "last 30 days"], generation: model.generation)
            }
            model.ask("How long this week, and when do I focus best?")
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            expect(text == f.store.askLookup(totals), "lookup differs from the store's", &problems)
            let both = ["focus totals (this week)", "best hours (last 30 days)"]
            expect(model.turns.last?.provenance == both,
                   "the provenance reads \(String(describing: model.turns.last?.provenance)), not \(both)", &problems)

            let shown = [AskTurn(question: "When do I focus best?", answer: "About two and a half hours.",
                                 state: .answered, provenance: ["focus totals (this week)"])]
            model.present(turns: shown)
            expect(model.turns == shown, "present(turns:) did not show what it was given", &problems)
            model.newChat()
            expect(model.turns.isEmpty && model.notice == nil && !model.isAnswering,
                   "a new chat left \(model.turns) and \(String(describing: model.notice)) behind", &problems)
        }
    }

    private static func blankQuestionIsIgnored() -> [String] {
        withFixture { f, problems in
            let model = AskModel(store: f.store)
            model.ask("   \n ")
            expect(!model.isAnswering, "a blank question started an answer", &problems)
            expect(model.turns.isEmpty && model.notice == nil, "a blank question changed what the sheet shows", &problems)
        }
    }

    /// A view that asks Apple's model whether it is there each time it is drawn
    /// is drawn again for every tick of a running session. The answer is state
    /// the model keeps, so the views read a stored value.
    private static func availabilityIsPublishedState() -> [String] {
        withFixture { f, problems in
            let model = AskModel(store: f.store)
            model.responder = { _, show in show("Done.") }
            var seen: [Bool] = []
            let watch = model.$canAsk.sink { seen.append($0) }
            defer { watch.cancel() }
            expect(model.canAsk == ModelGate.modelAvailable, "Ask opened believing canAsk is \(model.canAsk)", &problems)
            model.prepare()
            model.ask("When do I focus best?")
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            model.newChat()
            expect(seen == [ModelGate.modelAvailable],
                   "canAsk published \(seen) while Apple's model did not change", &problems)
        }
    }

    private static func askModelIsBuiltOnce() -> [String] {
        withFixture { f, problems in
            let navigation = MainWindowModel(store: f.store)
            expect(navigation.askModel == nil, "the Ask model was built before it was asked for", &problems)
            navigation.openAsk()
            let first = navigation.askModel
            navigation.openAsk()
            expect(first != nil && first === navigation.askModel, "opening Ask twice built a second model", &problems)
        }
    }

    private static func failedAnswerChangesOnlyItsTurn() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return failureChecks()
    }

    /// A tool runs, then the response fails, as when the context overflows
    /// after a lookup. The turn that failed shows the notice, with no
    /// half-answer and no sources it never rested on; the turns before it are
    /// as they were.
    @available(macOS 26, *)
    private static func failureChecks() -> [String] {
        withFixture { f, problems in
            let context = LanguageModelSession.GenerationError.Context(debugDescription: "probe")
            let failures: [(label: String, error: Error, notice: String)] = [
                ("a failed request", CocoaError(.fileReadNoSuchFile), "Couldn't answer:"),
                ("a full context", LanguageModelSession.GenerationError.exceededContextWindowSize(context),
                 AskModel.contextFull.text),
            ]
            for (label, error, noticeText) in failures {
                let model = AskModel(store: f.store)
                model.responder = { [unowned model] _, show in
                    _ = model.lookup(name: "focusTotals", arguments: ["range": "this week"], generation: model.generation)
                    show("This week you focused for")
                    throw error
                }
                let earlier = AskTurn(question: "When do I focus best?", answer: "Earlier answer.", state: .answered,
                                      provenance: ["best hours (today)"])
                model.present(turns: [earlier])
                model.ask("How long this week?")
                expect(model.isAnswering, "\(label): the question did not start an answer", &problems)
                InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
                expect(!model.isAnswering, "\(label) left the sheet answering", &problems)
                expect(model.turns.count == 2 && model.turns[0] == earlier,
                       "after \(label) the earlier turn reads \(model.turns)", &problems)
                guard model.turns.count == 2 else { continue }
                let failed = model.turns[1]
                if case let .failed(shown) = failed.state {
                    expect(shown.text.hasPrefix(noticeText), "after \(label) the notice is “\(shown.text)”", &problems)
                } else {
                    problems.append("after \(label) the turn is \(failed.state), not failed")
                }
                expect(failed.answer.isEmpty && failed.sources.isEmpty,
                       "after \(label) the turn kept “\(failed.answer)” and \(failed.sources.count) sources", &problems)
            }
        }
    }
}
