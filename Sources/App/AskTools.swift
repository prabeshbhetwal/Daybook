import Foundation
import FoundationModels

/// How the tools read what the model sends. A period is read by
/// `AskRange.resolving`, in the store's calendar and clock, so a named range,
/// an ISO date or a weekday or month by name arrives; anything else, and a
/// date the calendar lacks, is answered as such rather than swapped for
/// another period. An empty word or app is read as none.
///
/// The period is not held to a pattern as it is generated: with a regex
/// guide on it, the on-device model wrote the next argument as broken JSON
/// (`words:<ctrl46>Thesis`) and the answer failed (probe, 2026-10-10).
enum AskToolArguments {
    static let rangeGuide = "The period as the question says it, such as september, monday, 3 october, "
        + "31 february or 2025; or today, yesterday, this week, last week, this month, last month, "
        + "last 30 days, this year, last year or all time"

    static func text(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

// The five tools the model may call. Each reads one figure through `AskModel`,
// which asks the store on the main actor, and none changes anything.

@available(macOS 26, *)
struct FocusTotalsTool: Tool {
    let model: AskModel
    /// The session these tools were built for; see `AskModel.generation`.
    let generation: Int
    let name = "focusTotals"
    let description = "Returns the focused time, sessions and days in a period, the average on each day with focus, "
        + "the most focused day, week and month, the longest session and a breakdown; for one day, when the "
        + "first session began. Optionally only for sessions matching some words. For the most focused day, "
        + "week or month overall, use all time."

    @Generable
    struct Arguments {
        @Guide(description: AskToolArguments.rangeGuide)
        let range: String
        @Guide(description: "Words from a session name or note, such as thesis; leave out to count every session")
        let words: String?
    }

    func call(arguments: Arguments) async -> String {
        guard let range = await model.range(arguments.range) else { return AskFacts.noSuchPeriod(arguments.range) }
        return await model.lookup(.focusTotals(range, words: AskToolArguments.text(arguments.words)),
                                  generation: generation)
    }
}

@available(macOS 26, *)
struct CompareFocusTool: Tool {
    let model: AskModel
    let generation: Int
    let name = "compareFocus"
    let description = "Compares the focused time of two periods and says which had more and by how much. "
        + "Optionally only for sessions matching some words."

    @Generable
    struct Arguments {
        @Guide(description: AskToolArguments.rangeGuide)
        let first: String
        @Guide(description: "The period to compare it with, in the same form")
        let second: String
        @Guide(description: "Words from a session name or note, such as thesis; leave out to count every session")
        let words: String?
    }

    func call(arguments: Arguments) async -> String {
        guard let first = await model.range(arguments.first) else { return AskFacts.noSuchPeriod(arguments.first) }
        guard let second = await model.range(arguments.second) else {
            return AskFacts.noSuchPeriod(arguments.second)
        }
        return await model.lookup(.compare(first, with: second, words: AskToolArguments.text(arguments.words)),
                                  generation: generation)
    }
}

@available(macOS 26, *)
struct BestHoursTool: Tool {
    let model: AskModel
    let generation: Int
    let name = "bestHours"
    let description = "Returns the two-hour window of the day with the most focus, and the strongest weekday, "
        + "over the weeks of a period, at most its latest 14 as Insights reads them; with no period given, "
        + "the latest 14 weeks."

    /// The period is optional: given one, for "when do I focus best?" the
    /// model passed today and answered from a single morning (probe, 2026-10-10).
    @Generable
    struct Arguments {
        @Guide(description: AskToolArguments.rangeGuide + "; leave out for when the user usually focuses best")
        let range: String?
    }

    func call(arguments: Arguments) async -> String {
        let raw = AskToolArguments.text(arguments.range) ?? AskRange.allTime.rawValue
        guard let range = await model.range(raw) else { return AskFacts.noSuchPeriod(raw) }
        return await model.lookup(.bestHours(range), generation: generation)
    }
}

@available(macOS 26, *)
struct FindSessionsTool: Tool {
    let model: AskModel
    let generation: Int
    let name = "findSessions"
    let description = "Lists up to ten sessions in a period, newest first, each with its day, start time, name, "
        + "duration and the note line that holds the words. To find what the user wrote or worked on about "
        + "something, give its words from the question; to list everything the user did, such as yesterday, "
        + "leave words out."

    @Generable
    struct Arguments {
        @Guide(description: "Only words the question itself uses, such as a project or topic; leave out to list every session")
        let words: String?
        @Guide(description: AskToolArguments.rangeGuide)
        let range: String
    }

    func call(arguments: Arguments) async -> String {
        guard let range = await model.range(arguments.range) else { return AskFacts.noSuchPeriod(arguments.range) }
        return await model.lookup(.findSessions(words: AskToolArguments.text(arguments.words) ?? "", range),
                                  generation: generation)
    }
}

@available(macOS 26, *)
struct AppTimeTool: Tool {
    let model: AskModel
    let generation: Int
    let name = "appTime"
    let description = "Returns how long an app such as Safari or Xcode was in front during a period and in how "
        + "many sessions, or the most-used apps when no app is named. Use it for any question about an app."

    @Generable
    struct Arguments {
        @Guide(description: AskToolArguments.rangeGuide)
        let range: String
        @Guide(description: "An app name such as Safari; leave out to list the most-used apps")
        let app: String?
    }

    func call(arguments: Arguments) async -> String {
        guard let range = await model.range(arguments.range) else { return AskFacts.noSuchPeriod(arguments.range) }
        return await model.lookup(.appTime(range, app: AskToolArguments.text(arguments.app)), generation: generation)
    }
}
