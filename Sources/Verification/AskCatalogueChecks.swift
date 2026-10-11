import Foundation
import FoundationModels

/// Ask's catalogue of lookups and the one tool the on-device model reaches
/// them through. Version one had a tool type for each lookup; the model must
/// see exactly what it saw then (names, descriptions, parameter schemas and
/// order), or its answers drift, so the old shapes are kept here to compare.
enum AskCatalogueChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's catalogue holds version one's five lookups, in order, with the same descriptions",
         entriesMatchVersionOne),
        ("The dynamic tool's parameter schema is byte-identical to version one's", schemasMatchVersionOne),
        ("The catalogue reads the arguments as version one's tools did, and refuses a period that does not exist",
         argumentsReadAsVersionOne),
        ("The dynamic tool calls the lookup the model's arguments name", toolCallReturnsLookup),
    ]

    /// One value a main-actor task fills in while the check turns the run loop.
    private final class Outcome {
        var text: String?
    }

    private static func withFixture(_ body: @MainActor (AskLookupChecks.Fixture, inout [String]) -> Void) -> [String] {
        AskModelChecks.withFixture(body)
    }

    // MARK: - The catalogue

    private static func entriesMatchVersionOne() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        var problems: [String] = []
        let names = AskLookups.all.prefix(V1.tools.count).map(\.spec.name)
        let want = V1.tools.map(\.name)
        expect(names == want, "the catalogue starts with \(names), not \(want)", &problems)
        // What each lookup says beyond version one's, appended to its description.
        let added = ["appTime": " Also gives the hours of the day it was in front."]
        for (entry, old) in zip(AskLookups.all, V1.tools) {
            let description = old.description + (added[old.name] ?? "")
            expect(entry.spec.description == description,
                   "\(old.name) is described as “\(entry.spec.description)”, not “\(description)”", &problems)
            expect(AskLookups.named(old.name)?.spec == entry.spec, "named(\(old.name)) is not its own entry", &problems)
        }
        expect(AskLookups.named("nonsense") == nil, "an unknown name found an entry", &problems)
        return problems
    }

    /// `GenerationSchema` is `Codable`, so the schemas are compared by the
    /// JSON they encode to, with sorted keys: the properties with their
    /// descriptions, which are required, their order and the title.
    @available(macOS 26, *)
    private static func encoded(_ schema: GenerationSchema) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(schema)).flatMap { String(data: $0, encoding: .utf8) } ?? "unencodable"
    }

    /// What the model sends for a call: one string for each argument it gave.
    @available(macOS 26, *)
    private static func generated(_ arguments: [String: String]) -> GeneratedContent {
        GeneratedContent(properties: arguments.map { ($0.key, $0.value as any ConvertibleToGeneratedContent) },
                         uniquingKeysWith: { first, _ in first })
    }

    private static func schemasMatchVersionOne() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        var problems: [String] = []
        for (entry, old) in zip(AskLookups.all, V1.tools) {
            guard let schema = try? AskOnDeviceTool.schema(for: entry.spec) else {
                problems.append("\(old.name): the schema could not be built")
                continue
            }
            let got = encoded(schema), want = encoded(old.schema)
            expect(got == want, "\(old.name) has the schema \(got), not \(want)", &problems)
        }
        return problems
    }

    // MARK: - Reading the arguments

    private static func argumentsReadAsVersionOne() -> [String] {
        withFixture { f, problems in
            let model = AskModel(store: f.store)
            let cases: [(String, [String: String], AskRequest)] = [
                ("focusTotals", ["range": "this week"], .focusTotals(.thisWeek, words: nil)),
                ("focusTotals", ["range": "last month", "words": "thesis"], .focusTotals(.lastMonth, words: "thesis")),
                ("focusTotals", ["range": "2023-10"], .focusTotals(.month(year: 2023, month: 10), words: nil)),
                ("focusTotals", ["range": "this week", "words": ""], .focusTotals(.thisWeek, words: nil)),
                ("compareFocus", ["first": "this week", "second": "2023-10-17"],
                 .compare(.thisWeek, with: .day(year: 2023, month: 10, day: 17), words: nil)),
                ("focusTotals", ["range": "Monday"], .focusTotals(.day(year: 2023, month: 11, day: 13), words: nil)),
                ("bestHours", ["range": "last 30 days"], .bestHours(.last30Days)),
                ("bestHours", [:], .bestHours(.allTime)),
                ("findSessions", ["words": "thesis", "range": "all time"], .findSessions(words: "thesis", .allTime)),
                ("findSessions", ["range": "this week"], .findSessions(words: "", .thisWeek)),
                ("appTime", ["range": "this week", "app": "safari"], .appTime(.thisWeek, app: "safari")),
                ("appTime", ["range": "today", "app": ""], .appTime(.today, app: nil)),
            ]
            for (name, arguments, request) in cases {
                guard let entry = AskLookups.named(name) else { problems.append("no entry named \(name)"); continue }
                let got = entry.read(arguments, model.range)
                expect(got == .request(request), "\(name) \(arguments) read as \(got), not \(request)", &problems)
            }

            // A period the calendar lacks is said to be so, and looks nothing
            // up: it once fell back to this week and answered from it.
            let refusals: [(String, [String: String], String)] = [
                ("focusTotals", ["range": "31 february"], "31 february"),
                ("focusTotals", ["range": "2023-02-31"], "2023-02-31"),
                ("compareFocus", ["first": "this week", "second": "nonsense"], "nonsense"),
                ("compareFocus", ["first": "nonsense", "second": "also nonsense"], "nonsense"),
                ("bestHours", ["range": "2023-13"], "2023-13"),
                ("findSessions", ["range": "2023-02-30"], "2023-02-30"),
                ("appTime", ["range": "nonsense"], "nonsense"),
            ]
            for (name, arguments, raw) in refusals {
                let want = AskFacts.noSuchPeriod(raw)
                let got = AskLookups.named(name)?.read(arguments, model.range)
                expect(got == .refusal(want), "\(name) \(arguments) read as \(String(describing: got)), not “\(want)”",
                       &problems)
            }
            guard #available(macOS 26, *) else { return }

            // The lookups themselves, in answers of five, which the gate lets through.
            let limit = AskGate.lookupLimit
            for start in stride(from: 0, to: cases.count, by: limit) {
                let chunk = Array(cases[start..<min(start + limit, cases.count)])
                let made = AskThreadChecks.answer(lookingUp: chunk.map { ($0.0, $0.1) }, on: model)
                for (text, (name, arguments, request)) in zip(made.texts, chunk) {
                    let want = f.store.askLookup(request)
                    expect(text == want, "\(name) \(arguments) returned “\(text)”, not “\(want)”", &problems)
                }
                expect(made.texts.count == chunk.count, "\(made.texts.count) lookups answered, not \(chunk.count)", &problems)
                let provenance = chunk.map { $0.2.provenance }
                expect(made.provenance == provenance, "the lookups recorded \(made.provenance), not \(provenance)", &problems)
            }
            for start in stride(from: 0, to: refusals.count, by: limit) {
                let chunk = Array(refusals[start..<min(start + limit, refusals.count)])
                let made = AskThreadChecks.answer(lookingUp: chunk.map { ($0.0, $0.1) }, on: model)
                expect(made.texts == chunk.map { AskFacts.noSuchPeriod($0.2) },
                       "the refused periods returned \(made.texts)", &problems)
                expect(made.provenance.isEmpty, "a refused period was listed as a lookup: \(made.provenance)", &problems)
            }
            let unknown = AskThreadChecks.answer(lookingUp: [("nonsense", [:])], on: model)
            expect(unknown.texts == [AskFacts.unknownLookup("nonsense")] && unknown.provenance.isEmpty,
                   "an unknown lookup gave \(unknown.texts), listed \(unknown.provenance)", &problems)
        }
    }

    // MARK: - The tool

    private static func toolCallReturnsLookup() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return toolChecks()
    }

    /// The tool is called as the model would call it: with generated content
    /// that names its arguments. The run loop is turned to let the call land.
    @available(macOS 26, *)
    private static func toolChecks() -> [String] {
        withFixture { f, problems in
            let model = AskModel(store: f.store)
            let cases: [(String, [String: String], AskRequest)] = [
                ("focusTotals", ["range": "this week"], .focusTotals(.thisWeek, words: nil)),
                ("compareFocus", ["first": "this week", "second": "2023-10-17"],
                 .compare(.thisWeek, with: .day(year: 2023, month: 10, day: 17), words: nil)),
                ("appTime", ["range": "this week", "app": "safari"], .appTime(.thisWeek, app: "safari")),
            ]
            // The tools run inside an answer, held open while they are called.
            let hold = AskThreadChecks.Gate()
            model.responder = { _, _ in await withCheckedContinuation { hold.release = $0 } }
            model.ask("tools")
            InstalledAppCatalog.turnRunLoop(until: { hold.release != nil }, timeout: 5)
            for (name, arguments, request) in cases {
                guard let entry = AskLookups.named(name),
                      let tool = try? AskOnDeviceTool(entry, model: model, generation: model.generation)
                else { problems.append("\(name): no tool could be built"); continue }
                expect(tool.name == name && tool.description == entry.spec.description,
                       "\(name) is offered as \(tool.name), “\(tool.description)”", &problems)
                let content = generated(arguments)
                let outcome = Outcome()
                Task { @MainActor in outcome.text = await tool.call(arguments: content) }
                InstalledAppCatalog.turnRunLoop(until: { outcome.text != nil }, timeout: 5)
                let want = f.store.askLookup(request)
                expect(outcome.text == want, "\(name) returned “\(outcome.text ?? "nothing")”, not “\(want)”", &problems)
            }

            // A period that does not exist is refused, and nothing is looked up.
            guard let totals = try? AskOnDeviceTool(AskLookups.named("focusTotals")!, model: model,
                                                    generation: model.generation) else {
                problems.append("focusTotals: no tool could be built")
                return
            }
            let outcome = Outcome()
            Task { @MainActor in
                outcome.text = await totals.call(arguments: GeneratedContent(properties: ["range": "31 february"]))
            }
            InstalledAppCatalog.turnRunLoop(until: { outcome.text != nil }, timeout: 5)
            expect(outcome.text == AskFacts.noSuchPeriod("31 february"),
                   "a period that does not exist returned “\(outcome.text ?? "nothing")”", &problems)
            hold.release?.resume()
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            let used = cases.map { $0.2.provenance }
            expect(model.turns.last?.provenance == used,
                   "the tools recorded \(String(describing: model.turns.last?.provenance)), not \(used); "
                   + "a refused period must not be listed", &problems)
        }
    }
}

/// Version one's five tools as they were: their descriptions, and the
/// `@Generable` arguments the model was handed as each tool's schema.
@available(macOS 26, *)
private enum V1 {
    static let rangeGuide = "The period as the question says it, such as september, monday, 3 october, "
        + "31 february or 2025; or today, yesterday, this week, last week, this month, last month, "
        + "last 30 days, this year, last year or all time"

    /// In the order version one's session listed them.
    static let tools: [(name: String, description: String, schema: GenerationSchema)] = [
        ("focusTotals", FocusTotalsTool.description, FocusTotalsTool.Arguments.generationSchema),
        ("compareFocus", CompareFocusTool.description, CompareFocusTool.Arguments.generationSchema),
        ("bestHours", BestHoursTool.description, BestHoursTool.Arguments.generationSchema),
        ("findSessions", FindSessionsTool.description, FindSessionsTool.Arguments.generationSchema),
        ("appTime", AppTimeTool.description, AppTimeTool.Arguments.generationSchema),
    ]

    struct FocusTotalsTool {
        static let description = "Returns the focused time, sessions and days in a period, the average on each day with focus, "
            + "the most focused day, week and month, the longest session and a breakdown; for one day, when the "
            + "first session began. Optionally only for sessions matching some words. For the most focused day, "
            + "week or month overall, use all time."

        @Generable
        struct Arguments {
            @Guide(description: V1.rangeGuide)
            let range: String
            @Guide(description: "Words from a session name or note, such as thesis; leave out to count every session")
            let words: String?
        }
    }

    struct CompareFocusTool {
        static let description = "Compares the focused time of two periods and says which had more and by how much. "
            + "Optionally only for sessions matching some words."

        @Generable
        struct Arguments {
            @Guide(description: V1.rangeGuide)
            let first: String
            @Guide(description: "The period to compare it with, in the same form")
            let second: String
            @Guide(description: "Words from a session name or note, such as thesis; leave out to count every session")
            let words: String?
        }
    }

    struct BestHoursTool {
        static let description = "Returns the two-hour window of the day with the most focus, and the strongest weekday, "
            + "over the weeks of a period, at most its latest 14 as Insights reads them; with no period given, "
            + "the latest 14 weeks."

        @Generable
        struct Arguments {
            @Guide(description: V1.rangeGuide + "; leave out for when the user usually focuses best")
            let range: String?
        }
    }

    struct FindSessionsTool {
        static let description = "Lists up to ten sessions in a period, newest first, each with its day, start time, name, "
            + "duration and the note line that holds the words. To find what the user wrote or worked on about "
            + "something, give its words from the question; to list everything the user did, such as yesterday, "
            + "leave words out."

        @Generable
        struct Arguments {
            @Guide(description: "Only words the question itself uses, such as a project or topic; leave out to list every session")
            let words: String?
            @Guide(description: V1.rangeGuide)
            let range: String
        }
    }

    struct AppTimeTool {
        static let description = "Returns how long an app such as Safari or Xcode was in front during a period and in how "
            + "many sessions, or the most-used apps when no app is named. Use it for any question about an app."

        @Generable
        struct Arguments {
            @Guide(description: V1.rangeGuide)
            let range: String
            @Guide(description: "An app name such as Safari; leave out to list the most-used apps")
            let app: String?
        }
    }
}
