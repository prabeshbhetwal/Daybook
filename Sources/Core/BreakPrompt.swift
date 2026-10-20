import Foundation

/// A break that has come due, with the words to say about it.
struct BreakPrompt: Equatable {
    /// Which showing this is. A prompt that comes back after a Later is a new
    /// one, so a surface can tell it from the one it already dismissed.
    /// `==` therefore compares ids too: two independently built prompts are
    /// never equal.
    let id: UUID = UUID()
    let tier: BreakTier
    /// Continuous work behind it. The real figure, not the tier's threshold —
    /// a reminder that fires late must not claim you have worked less than you
    /// have.
    let worked: TimeInterval
    /// The app that took a majority of that time, when one did.
    let appName: String?
    /// How much of the stretch that app took, 0…1. Decides whether the app
    /// can carry the figure or only colour it.
    var appShare: Double = 1
    /// False once this break has been put off as often as it may be.
    var canLater = true

    var title: String { tier.title }

    /// The figure is continuous time at the Mac. It belongs to an app only
    /// when the app had nearly all of it: "You have been in Vorssaint for
    /// 20m" was written for a stretch Vorssaint had half of, after a login
    /// during which the person had also been in Dia, Claude and Finder — one
    /// true number attached to the wrong noun. Now the noun matches the
    /// number: the whole stretch names the app; a majority names it as
    /// "mostly"; anything less names the Mac.
    ///
    /// The title already says what to do and for how long, so the body says
    /// only why now. "Stretch" stays: the buttoned reminders show this body and nothing else.
    var body: String {
        let spent = BreakPrompt.phrase(worked)
        switch tier {
        case .micro:
            return "You have been \(place) for \(spent)\(mostly). Stretch while you do."
        case .cognitive:
            return "You have been \(place) for \(spent)\(mostly)."
        case .ultradian:
            return "\(spent.prefix(1).uppercased() + spent.dropFirst()) \(place) "
                + "without a real break\(mostly)."
        }
    }

    /// Nearly all of the stretch in one app is the app's stretch.
    static let wholeShare = 0.9

    private var place: String {
        if let appName, appShare >= BreakPrompt.wholeShare { return "in \(appName)" }
        return "at the Mac"
    }

    private var mostly: String {
        guard let appName, appShare < BreakPrompt.wholeShare else { return "" }
        return ", mostly in \(appName)"
    }

    /// Whole minutes, because "52m 13s" is not information anybody wants here.
    /// Below a minute it says seconds instead: the micro tier prescribes thirty
    /// seconds, and rounding that up to "1m" doubled the ask everywhere the
    /// figure appeared.
    static func phrase(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds.rounded())))s" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

/// What was said last, so the same nudge is not repeated every second.
struct BreakNotice: Equatable {
    let tier: BreakTier
    let at: Date
}
