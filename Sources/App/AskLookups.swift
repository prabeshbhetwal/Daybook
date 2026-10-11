import Foundation

/// What a lookup makes of the arguments a model sent: the request to run, or
/// the words that tell the model its period does not exist.
enum AskLookupCall: Equatable {
    case request(AskRequest)
    case refusal(String)
}

/// One lookup Ask offers a model: what the model is told about it, and how the
/// arguments it sends become a request. The ones below are the only lookups;
/// each model's adapter reaches them through this type, and none changes anything.
struct AskLookup {
    let spec: AskLookupSpec
    /// An optional argument is trimmed, and an empty one is absent. A required
    /// period is read as it was sent, so a refusal quotes it as the model wrote
    /// it. `period` reads a period as `AskModel.range(_:)` does.
    let read: (_ arguments: [String: String], _ period: (String) -> AskRange?) -> AskLookupCall
}

/// The catalogue, in the order the on-device model has always been offered the
/// lookups; those added since come after them. A period is read by `AskRange.resolving`, in the store's calendar
/// and clock, so a named range, an ISO date or a weekday or month by name
/// arrives; anything else, and a date the calendar lacks, is answered as such
/// rather than swapped for another period.
enum AskLookups {
    static let all: [AskLookup] = [focusTotals, compareFocus, bestHours, findSessions, appTime, dayEvents, sessionDetail]

    static func named(_ name: String) -> AskLookup? {
        all.first { $0.spec.name == name }
    }

    // MARK: - Wording

    /// The period is not held to a pattern as it is generated: with a regex
    /// guide on it, the on-device model wrote the next argument as broken JSON
    /// (`words:<ctrl46>Thesis`) and the answer failed (probe, 2026-10-10).
    private static let rangeGuide = "The period as the question says it, such as september, monday, 3 october, "
        + "31 february or 2025; or today, yesterday, this week, last week, this month, last month, "
        + "last 30 days, this year, last year or all time"

    private static let wordsGuide = "Words from a session name or note, such as thesis; leave out to count every session"

    private static func text(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: - The five lookups

    private static let focusTotals = AskLookup(
        spec: AskLookupSpec(
            name: "focusTotals",
            description: "Returns the focused time, sessions and days in a period, the average on each day with focus, "
                + "the most focused day, week and month, the longest session and a breakdown; for one day, when the "
                + "first session began. Optionally only for sessions matching some words. For the most focused day, "
                + "week or month overall, use all time. Also gives the time in each work type.",
            parameters: [AskParameter(name: "range", description: rangeGuide, required: true),
                         AskParameter(name: "words", description: wordsGuide, required: false)]),
        read: { arguments, period in
            let raw = arguments["range"] ?? ""
            guard let range = period(raw) else { return .refusal(AskFacts.noSuchPeriod(raw)) }
            return .request(.focusTotals(range, words: text(arguments["words"])))
        })

    private static let compareFocus = AskLookup(
        spec: AskLookupSpec(
            name: "compareFocus",
            description: "Compares the focused time of two periods and says which had more and by how much. "
                + "Optionally only for sessions matching some words.",
            parameters: [AskParameter(name: "first", description: rangeGuide, required: true),
                         AskParameter(name: "second", description: "The period to compare it with, in the same form",
                                      required: true),
                         AskParameter(name: "words", description: wordsGuide, required: false)]),
        read: { arguments, period in
            let rawFirst = arguments["first"] ?? ""
            guard let first = period(rawFirst) else { return .refusal(AskFacts.noSuchPeriod(rawFirst)) }
            let rawSecond = arguments["second"] ?? ""
            guard let second = period(rawSecond) else { return .refusal(AskFacts.noSuchPeriod(rawSecond)) }
            return .request(.compare(first, with: second, words: text(arguments["words"])))
        })

    /// The period is optional: given one, for "when do I focus best?" the
    /// model passed today and answered from a single morning (probe, 2026-10-10).
    private static let bestHours = AskLookup(
        spec: AskLookupSpec(
            name: "bestHours",
            description: "Returns the two-hour window of the day with the most focus, and the strongest weekday, "
                + "over the weeks of a period, at most its latest 14 as Insights reads them; with no period given, "
                + "the latest 14 weeks.",
            parameters: [AskParameter(name: "range",
                                      description: rangeGuide + "; leave out for when the user usually focuses best",
                                      required: false)]),
        read: { arguments, period in
            let raw = text(arguments["range"]) ?? AskRange.allTime.rawValue
            guard let range = period(raw) else { return .refusal(AskFacts.noSuchPeriod(raw)) }
            return .request(.bestHours(range))
        })

    private static let findSessions = AskLookup(
        spec: AskLookupSpec(
            name: "findSessions",
            description: "Lists up to ten sessions in a period, newest first, each with its day, start time, name, "
                + "duration and the note line that holds the words. To find what the user wrote or worked on about "
                + "something, give its words from the question; to list everything the user did, such as yesterday, "
                + "leave words out.",
            parameters: [AskParameter(name: "words",
                                      description: "Only words the question itself uses, such as a project or topic; "
                                          + "leave out to list every session",
                                      required: false),
                         AskParameter(name: "range", description: rangeGuide, required: true)]),
        read: { arguments, period in
            let raw = arguments["range"] ?? ""
            guard let range = period(raw) else { return .refusal(AskFacts.noSuchPeriod(raw)) }
            return .request(.findSessions(words: text(arguments["words"]) ?? "", range))
        })

    private static let appTime = AskLookup(
        spec: AskLookupSpec(
            name: "appTime",
            description: "Returns how long an app such as Safari or Xcode was in front during a period and in how "
                + "many sessions, or the most-used apps when no app is named. Use it for any question about an app. "
                + "Also gives the hours of the day it was in front.",
            parameters: [AskParameter(name: "range", description: rangeGuide, required: true),
                         AskParameter(name: "app",
                                      description: "An app name such as Safari; leave out to list the most-used apps",
                                      required: false)]),
        read: { arguments, period in
            let raw = arguments["range"] ?? ""
            guard let range = period(raw) else { return .refusal(AskFacts.noSuchPeriod(raw)) }
            return .request(.appTime(range, app: text(arguments["app"])))
        })

    // MARK: - Added since version one

    private static let dayEvents = AskLookup(
        spec: AskLookupSpec(
            name: "dayEvents",
            description: "Lists what happened between sessions in a period: breaks, where the user was and what "
                + "they answered when asked about time away, and what the Mac did, such as sleep, lock, restart "
                + "or a crash, with their times.",
            parameters: [AskParameter(name: "range", description: rangeGuide, required: true)]),
        read: { arguments, period in
            let raw = arguments["range"] ?? ""
            guard let range = period(raw) else { return .refusal(AskFacts.noSuchPeriod(raw)) }
            return .request(.dayEvents(range))
        })

    private static let sessionDetail = AskLookup(
        spec: AskLookupSpec(
            name: "sessionDetail",
            description: "Returns the detail of sessions in a period: each working stretch with its start and end, "
                + "its note and its battery reading, such as whether the Mac was plugged in.",
            parameters: [AskParameter(name: "range", description: rangeGuide, required: true),
                         AskParameter(name: "words",
                                      description: "Words from the session's name, such as thesis; leave out for every session",
                                      required: false)]),
        read: { arguments, period in
            let raw = arguments["range"] ?? ""
            guard let range = period(raw) else { return .refusal(AskFacts.noSuchPeriod(raw)) }
            return .request(.sessionDetail(range, words: text(arguments["words"])))
        })
}
