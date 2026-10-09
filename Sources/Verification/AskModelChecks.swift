import Foundation
import FoundationModels

/// Ask Daybook's model layer without a model: the words shown when it cannot
/// answer, the tools it is handed and the lookups they make. None of these
/// starts a `LanguageModelSession`; its answers are not repeatable, and a
/// runner with Apple Intelligence off has none to give.
enum AskModelChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask says plainly why it cannot answer, for every availability and error", noticesCoverEveryCase),
        ("Each Ask tool returns the lookup it names, and bad arguments fall back", toolsMatchLookups),
        ("Ask's Used line lists each lookup in order, and a new question clears it", provenanceRecordsLookups),
        ("A blank Ask question is ignored", blankQuestionIsIgnored),
        ("Opening Ask twice builds its model once", askModelIsBuiltOnce),
    ]

    /// One value a main-actor task fills in while the check turns the run loop.
    private final class Outcome {
        var text: String?
    }

    private static func notice(_ text: String, opensSettings: Bool = false) -> AskNotice {
        AskNotice(text: text, opensSettings: opensSettings)
    }

    /// The Ask fixture with the body on the main actor, where `AskModel` lives.
    private static func withFixture(_ body: @MainActor (AskLookupChecks.Fixture, inout [String]) -> Void) -> [String] {
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
        let full = notice("Started a new thread — the last one was full.")
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
        let full = notice("Started a new thread — the last one was full.")
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

    // MARK: - Tools

    private static func toolsMatchLookups() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return toolChecks()
    }

    /// Each tool is called as the model would call it, on the main actor, and
    /// must hand back exactly what the store's lookup says for the request
    /// the arguments name. The run loop is turned to let the call land.
    @available(macOS 26, *)
    private static func toolChecks() -> [String] {
        withFixture { f, problems in
            let model = AskModel(store: f.store)
            let totals = FocusTotalsTool(model: model), hours = BestHoursTool(model: model)
            let find = FindSessionsTool(model: model), apps = AppTimeTool(model: model)
            let cases: [(String, AskRequest, @MainActor () async -> String)] = [
                ("focusTotals", .focusTotals(.thisWeek, words: nil),
                 { await totals.call(arguments: .init(range: "this week", words: nil)) }),
                ("focusTotals with words", .focusTotals(.lastMonth, words: "thesis"),
                 { await totals.call(arguments: .init(range: "last month", words: "thesis")) }),
                ("focusTotals with an unknown range", .focusTotals(.thisWeek, words: nil),
                 { await totals.call(arguments: .init(range: "nonsense", words: nil)) }),
                ("focusTotals with empty words", .focusTotals(.thisWeek, words: nil),
                 { await totals.call(arguments: .init(range: "this week", words: "")) }),
                ("bestHours", .bestHours(.last30Days),
                 { await hours.call(arguments: .init(range: "last 30 days")) }),
                ("findSessions", .findSessions(words: "thesis", .allTime),
                 { await find.call(arguments: .init(words: "thesis", range: "all time")) }),
                ("appTime", .appTime(.thisWeek, app: "safari"),
                 { await apps.call(arguments: .init(range: "this week", app: "safari")) }),
                ("appTime with an empty app", .appTime(.today, app: nil),
                 { await apps.call(arguments: .init(range: "today", app: "")) }),
            ]
            for (label, request, call) in cases {
                let outcome = Outcome()
                Task { @MainActor in outcome.text = await call() }
                InstalledAppCatalog.turnRunLoop(until: { outcome.text != nil }, timeout: 5)
                let want = f.store.askLookup(request)
                expect(outcome.text == want, "\(label) returned “\(outcome.text ?? "nothing")”, not “\(want)”",
                       &problems)
            }
            let used = "Used: " + cases.map { $0.1.provenance }.joined(separator: " · ")
            expect(model.used == used, "the tools recorded “\(model.used)”, not “\(used)”", &problems)
        }
    }

    // MARK: - The model's own state

    private static func provenanceRecordsLookups() -> [String] {
        withFixture { f, problems in
            let model = AskModel(store: f.store)
            let totals = AskRequest.focusTotals(.thisWeek, words: nil)
            expect(model.lookup(totals) == f.store.askLookup(totals), "lookup differs from the store's", &problems)
            expect(model.used == "Used: focus totals (this week)", "Used reads “\(model.used)”", &problems)
            _ = model.lookup(.bestHours(.last30Days))
            let both = "Used: focus totals (this week) · best hours (last 30 days)"
            expect(model.used == both, "Used reads “\(model.used)”, not “\(both)”", &problems)

            model.present(answer: "About two and a half hours.", used: "Used: focus totals (this week)")
            expect(model.answer == "About two and a half hours." && model.used == "Used: focus totals (this week)",
                   "present(answer:used:) did not show what it was given", &problems)
            model.newQuestion()
            expect(model.used.isEmpty && model.answer.isEmpty && model.question.isEmpty && model.notice == nil,
                   "a new question left “\(model.used)”, “\(model.answer)”, “\(model.question)” behind", &problems)
        }
    }

    private static func blankQuestionIsIgnored() -> [String] {
        withFixture { f, problems in
            let model = AskModel(store: f.store)
            model.ask("   \n ")
            expect(!model.isAnswering, "a blank question started an answer", &problems)
            expect(model.answer.isEmpty && model.question.isEmpty && model.notice == nil,
                   "a blank question changed what the sheet shows", &problems)
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
}
