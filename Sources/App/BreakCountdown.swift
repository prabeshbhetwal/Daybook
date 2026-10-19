import Foundation

/// A break's time left, in the three places it is shown: the menu bar, the
/// break card, and VoiceOver. One rule for rounding, so the card never says
/// 4m while the menu bar says 5m.
enum BreakCountdown {
    /// The menu bar's text. Minutes rounded up while more than a minute is
    /// left, so it changes once a minute; seconds in the last minute; then
    /// overtime by whole minutes.
    static func text(remaining: TimeInterval) -> String {
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
    static func spoken(remaining: TimeInterval) -> String {
        func minutes(_ count: Int) -> String { count == 1 ? "1 minute" : "\(count) minutes" }
        if remaining > 60 { return "\(minutes(Int(ceil(remaining / 60)))) left" }
        if remaining > 0 { return "under a minute left" }
        if remaining > -60 { return "Break over" }
        return "Break over by \(minutes(Int(-remaining / 60)))"
    }
}
