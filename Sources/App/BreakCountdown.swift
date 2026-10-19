import Foundation

/// A break's time left, in the three places it is shown: the menu bar, the
/// break card, and VoiceOver. One rule for rounding, so the card never says
/// 4m while the menu bar says 5m.
enum BreakCountdown {
    /// What a break can have left: a plan of up to a day, and the overtime
    /// before its cap. A value beyond that is damaged, and converting it to
    /// whole minutes would trap, so it is held to a day either way, and a
    /// value that is not a number reads as no time.
    private static func bounded(_ remaining: TimeInterval) -> TimeInterval {
        remaining.isNaN ? 0 : min(max(remaining, -BreakLength.maximum), BreakLength.maximum)
    }

    /// The menu bar's text. Minutes rounded up while more than a minute is
    /// left, so it changes once a minute; seconds in the last minute; then
    /// overtime by whole minutes.
    static func text(remaining unchecked: TimeInterval) -> String {
        let remaining = bounded(unchecked)
        if remaining > 60 { return "\(Int(ceil(remaining / 60)))m" }
        if remaining > 0 { return "\(Int(ceil(remaining)))s" }
        if remaining > -60 { return "Over" }
        return "+\(Int(-remaining / 60))m"
    }

    /// The same, as the break card prints it.
    static func cardText(remaining: TimeInterval) -> String {
        if remaining > 0 { return "\(text(remaining: remaining)) left" }
        if remaining > -60 { return "Break over" }
        return "\(text(remaining: remaining)) over"
    }

    /// As VoiceOver says it: to the minute, and "under a minute" for the
    /// last. Read to the second, a live countdown changes while it is being
    /// spoken.
    static func spoken(remaining unchecked: TimeInterval) -> String {
        let remaining = bounded(unchecked)
        func minutes(_ count: Int) -> String { count == 1 ? "1 minute" : "\(count) minutes" }
        if remaining > 60 { return "\(minutes(Int(ceil(remaining / 60)))) left" }
        if remaining > 0 { return "under a minute left" }
        if remaining > -60 { return "Break over" }
        return "Break over by \(minutes(Int(-remaining / 60)))"
    }
}

/// The lengths the Take a break menu offers: `BreakLength.choices`, each named
/// for the menu and for VoiceOver. A click on the button itself takes the
/// default, `BreakLength.standard`.
enum BreakChoice {
    struct Option: Equatable {
        let length: TimeInterval
        let title: String
        let spoken: String
    }

    /// Each is spoken beginning with the words on the control, so what a
    /// listener hears contains what a sighted person reads.
    static var options: [Option] {
        BreakLength.choices.map { length in
            let title = "\(Int(length / 60)) minutes"
            return Option(length: length, title: title, spoken: "\(title), take a break")
        }
    }

    /// The "+5 min" button: its text, and what VoiceOver says, which begins
    /// with that text.
    static var extend: (title: String, spoken: String) {
        let minutes = Int(BreakLength.extra / 60)
        return ("+\(minutes) min", "+\(minutes) min, add \(minutes) minutes to the break")
    }
}
