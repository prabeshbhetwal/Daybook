import Foundation

/// The figures on the Yesterday card, worked out in code from the same input
/// the day's note facts use, so what the card shows and what the model is told
/// can never disagree. Rows are sorted by time spent, longest first.
struct DayRecap: Equatable {
    struct Row: Equatable {
        let name: String
        let worked: TimeInterval
    }
    /// How the day compares with the person's typical day.
    struct Delta: Equatable {
        let isAbove: Bool
        /// "53m above your typical 9h 26m".
        let text: String
        /// "The median of 13 days with focus in your last 14."
        let detail: String
    }
    struct Peak: Equatable {
        /// "Afternoon, noon–5 pm".
        let label: String
        let focused: TimeInterval
    }
    static let rowLimit = 3

    let delta: Delta?
    let sessions: [Row]
    let moreSessions: Int
    let apps: [Row]
    let moreApps: Int
    let peak: Peak?

    init(_ input: NoteDayInput) {
        let compact = DurationText.compact
        let difference = input.focused - input.typicalFocused
        if input.typicalFocused > 0, abs(difference) >= 60 {
            delta = Delta(isAbove: difference > 0,
                          text: "\(compact(abs(difference))) \(difference > 0 ? "above" : "below") your typical "
                              + compact(input.typicalFocused),
                          detail: "The median of \(input.typicalDays) days with focus in your last \(NoteBaseline.days).")
        } else {
            delta = nil
        }
        var worked: [String: TimeInterval] = [:]
        for session in input.sessions { worked[session.workType.sessionTitle(named: session.name), default: 0] += session.worked }
        let named = worked.map { Row(name: $0.key, worked: $0.value) }.sorted(by: Self.longestFirst)
        sessions = Array(named.prefix(Self.rowLimit))
        moreSessions = max(0, named.count - Self.rowLimit)
        let used = input.apps.filter { $0.total > 0 }.map { Row(name: $0.appName, worked: $0.total) }
            .sorted(by: Self.longestFirst)
        apps = Array(used.prefix(Self.rowLimit))
        moreApps = max(0, used.count - Self.rowLimit)
        peak = NoteDayPart.peak(of: input.focusByPart).map { Peak(label: $0.part.label(), focused: $0.focused) }
    }

    private static func longestFirst(_ a: Row, _ b: Row) -> Bool {
        a.worked != b.worked ? a.worked > b.worked : a.name < b.name
    }
}

extension NoteDayPart {
    /// The part that held the most focus, once it holds a fair share of it.
    /// The share is of the parts' own sum: on a day with no midnight the
    /// day's total runs an hour long.
    static func peak(of byPart: [NoteDayPart: TimeInterval]) -> (part: NoteDayPart, focused: TimeInterval)? {
        let total = byPart.values.reduce(0, +)
        guard let best = allCases.map({ (part: $0, focused: byPart[$0] ?? 0) }).max(by: { $0.focused < $1.focused }),
              best.focused >= 60, best.focused >= total * 0.4 else { return nil }
        return best
    }

    /// "Afternoon, noon–5 pm".
    func label(locale: Locale = Locale(identifier: "en_AU")) -> String {
        func hour(_ hour: Int) -> String { hour == 12 ? "noon" : DateFormats.wholeHour(hour, locale: locale) }
        switch self {
        case .morning: return "Morning, \(hour(5))–noon"
        case .afternoon: return "Afternoon, noon–\(hour(17))"
        case .evening: return "Evening, \(hour(17))–\(hour(22))"
        case .night: return "Night, \(hour(22))–\(hour(5))"
        }
    }
}
