import Foundation

/// The break rhythms a person can pick. Pure numbers and copy; the reminder
/// engine and Settings read them from here.
enum BreakPreset: String, Codable, CaseIterable {
    case steady, pomodoro, deepWork, flow, custom

    var title: String {
        switch self {
        case .steady: return "Steady"
        case .pomodoro: return "Pomodoro"
        case .deepWork: return "Deep work"
        case .flow: return "Flow"
        case .custom: return "Custom"
        }
    }

    /// One plain sentence about where the numbers come from; Custom has none.
    var evidenceNote: String? {
        switch self {
        case .steady: return "Close to HSE and OSHA guidance: 5 to 10 minutes an hour."
        case .pomodoro: return "A popular fixed cadence. Studies find it about as good as choosing your own breaks."
        case .deepWork: return "Longer blocks for focused work, with a proper reset."
        case .flow: return "You decide when to stop; Daybook suggests a break length."
        case .custom: return nil
        }
    }
}

/// The person's own numbers for the Custom rhythm, in minutes.
struct CustomRhythm: Codable, Equatable {
    var workMinutes = 50
    var breakMinutes = 5
    /// Every this many breaks one is the long one; nil for no long break.
    var longEvery: Int? = nil
    var longMinutes = 15

    /// The same numbers moved inside their ranges: work 10 to 180, break 1 to 30,
    /// long break every 2 to 8, long break from the break's length to 60.
    func clamped() -> CustomRhythm {
        let shortBreak = min(max(breakMinutes, 1), 30)
        return CustomRhythm(workMinutes: min(max(workMinutes, 10), 180),
                            breakMinutes: shortBreak,
                            longEvery: longEvery.map { min(max($0, 2), 8) },
                            longMinutes: min(max(longMinutes, shortBreak), 60))
    }
}

/// A preset resolved to seconds. Under Flow `work` and `breakLength` are nil:
/// the person decides when to stop and Daybook suggests the break.
struct BreakRhythm: Equatable {
    let preset: BreakPreset
    let work: TimeInterval?
    let breakLength: TimeInterval?
    let longEvery: Int?
    let longLength: TimeInterval?

    static let flowShortest: TimeInterval = 300
    static let flowLongest: TimeInterval = 1_200

    init(_ preset: BreakPreset, custom: CustomRhythm = CustomRhythm()) {
        self.preset = preset
        switch preset {
        case .steady:
            (work, breakLength, longEvery, longLength) = (3_000, 300, nil, nil)
        case .pomodoro:
            (work, breakLength, longEvery, longLength) = (1_500, 300, 4, 900)
        case .deepWork:
            (work, breakLength, longEvery, longLength) = (5_400, 900, nil, nil)
        case .flow:
            (work, breakLength, longEvery, longLength) = (nil, nil, nil, nil)
        case .custom:
            let c = custom.clamped()
            work = TimeInterval(c.workMinutes * 60)
            breakLength = TimeInterval(c.breakMinutes * 60)
            longEvery = c.longEvery
            longLength = c.longEvery == nil ? nil : TimeInterval(c.longMinutes * 60)
        }
    }

    /// Flow's break after a stretch of work: a fifth of it in whole minutes
    /// (a half rounds up), from 5 to 20. Whole, because the offer reads "9
    /// minutes" and counts down from there; `BreakCycles.flowRun` credits a
    /// gap with this same figure, so the two cannot disagree.
    static func flowSuggestion(after stretch: TimeInterval) -> TimeInterval {
        min(max((stretch / 300).rounded() * 60, flowShortest), flowLongest)
    }
}
