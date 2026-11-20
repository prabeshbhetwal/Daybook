import Foundation

/// Everything the model is told about a session, and nothing else (Phase C, rulings C5 and C28). The App
/// fills it from the session's shape, in its own words for activities; there is no field for the session's
/// name, note, window titles, addresses or bundle identifiers, so none can reach the text.
struct CategoryQuestionFacts {
    var activities: [(name: String, minutes: Int)]
    var depthWord: String?
    /// Display names of the top apps, at most two are used.
    var appNames: [String]
    /// A kind of site ("video"), only when the site signal is on.
    var siteKind: String?
    /// The categories that can be started, in catalogue order, at most `maxOffered` are used. The model
    /// answers with a number from this list.
    var categories: [(id: String, name: String)]
}

/// The question put to the model for one ended session.
struct CategoryQuestion: Equatable {
    let text: String
    /// The numbered list, in order: number n is `offered[n - 1]`.
    let offered: [WorkType]
    let fingerprint: ActivityFingerprint

    /// Whole minutes for a length in seconds, rounded to nearest and never below zero. Every figure the
    /// model sees comes from here, not from the model.
    static func minutes(fromSeconds seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((min(seconds, 1e9) / 60).rounded())
    }

    static func make(facts: CategoryQuestionFacts, fingerprint: ActivityFingerprint) -> CategoryQuestion {
        let categories = Array(facts.categories.prefix(AILabelConstants.maxOffered))
        var lines: [String] = []
        if !facts.activities.isEmpty {
            lines.append("Time spent:")
            lines += facts.activities.map { "- \($0.name): \($0.minutes) min" }
        }
        if let depth = facts.depthWord, !depth.isEmpty { lines.append("Depth: \(depth)") }
        if !facts.appNames.isEmpty { lines.append("Apps: \(facts.appNames.prefix(2).joined(separator: ", "))") }
        if let site = facts.siteKind, !site.isEmpty { lines.append("Site kind: \(site)") }
        lines.append("Categories:")
        lines += categories.enumerated().map { "\($0.offset + 1). \($0.element.name)" }
        return CategoryQuestion(text: lines.joined(separator: "\n"), offered: categories.map { WorkType(rawValue: $0.id) },
                                fingerprint: fingerprint)
    }
}
