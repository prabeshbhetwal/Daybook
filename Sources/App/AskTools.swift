import Foundation
import FoundationModels

/// How the tools read what the model sends. A range it invents is read as this
/// week, and an empty word or app is read as none, so a vague call still gets
/// a real answer.
enum AskToolArguments {
    static func range(_ raw: String) -> AskRange { AskRange(rawValue: raw) ?? .thisWeek }

    static func text(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

// The four tools the model may call. Each reads one figure through `AskModel`,
// which asks the store on the main actor, and none changes anything.

@available(macOS 26, *)
struct FocusTotalsTool: Tool {
    let model: AskModel
    let name = "focusTotals"
    let description = "Returns the total focused time, session count and best day or week for a time range, "
        + "optionally only for sessions matching some words."

    @Generable
    struct Arguments {
        @Guide(description: "Time range", .anyOf(AskRange.allCases.map(\.rawValue)))
        let range: String
        @Guide(description: "Words from a session name, note or app; leave out to count every session")
        let words: String?
    }

    func call(arguments: Arguments) async -> String {
        await model.lookup(.focusTotals(AskToolArguments.range(arguments.range),
                                        words: AskToolArguments.text(arguments.words)))
    }
}

@available(macOS 26, *)
struct BestHoursTool: Tool {
    let model: AskModel
    let name = "bestHours"
    let description = "Returns the two-hour window of the day with the most focus, and the strongest weekday, "
        + "for a time range."

    @Generable
    struct Arguments {
        @Guide(description: "Time range", .anyOf(AskRange.allCases.map(\.rawValue)))
        let range: String
    }

    func call(arguments: Arguments) async -> String {
        await model.lookup(.bestHours(AskToolArguments.range(arguments.range)))
    }
}

@available(macOS 26, *)
struct FindSessionsTool: Tool {
    let model: AskModel
    let name = "findSessions"
    let description = "Returns up to ten sessions in a time range whose name, note or apps match some words, "
        + "each with its date and duration."

    @Generable
    struct Arguments {
        @Guide(description: "Words from a session name, note or app")
        let words: String
        @Guide(description: "Time range", .anyOf(AskRange.allCases.map(\.rawValue)))
        let range: String
    }

    func call(arguments: Arguments) async -> String {
        await model.lookup(.findSessions(words: AskToolArguments.text(arguments.words) ?? "",
                                         AskToolArguments.range(arguments.range)))
    }
}

@available(macOS 26, *)
struct AppTimeTool: Tool {
    let model: AskModel
    let name = "appTime"
    let description = "Returns how long an app was in front during a time range, or the most-used apps "
        + "when no app is named."

    @Generable
    struct Arguments {
        @Guide(description: "Time range", .anyOf(AskRange.allCases.map(\.rawValue)))
        let range: String
        @Guide(description: "An app name such as Safari; leave out to list the most-used apps")
        let app: String?
    }

    func call(arguments: Arguments) async -> String {
        await model.lookup(.appTime(AskToolArguments.range(arguments.range),
                                    app: AskToolArguments.text(arguments.app)))
    }
}
