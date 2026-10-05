import Foundation

/// The four check frequencies map to the intervals the updater stores, and
/// an interval stored some other way still reads as one of them.
enum UpdatePreferenceChecks {
    static let tests: [(String, () -> [String])] = [
        ("Update checks offer daily, weekly, fortnightly and monthly, each its own interval", frequencies),
        ("An update's countdown installs at zero, but waits while a note, an answer or a naming is open",
         countdownWaitsForUnsavedWork)
    ]

    static func frequencies() -> [String] {
        var problems: [String] = []
        let days = UpdateFrequency.allCases.map { Int($0.interval / 86_400) }
        if days != [1, 7, 14, 30] { problems.append("frequencies were \(days) days") }
        for frequency in UpdateFrequency.allCases where UpdateFrequency.nearest(to: frequency.interval) != frequency {
            problems.append("\(frequency.title) did not read back as itself")
        }
        // Sparkle's own default is one day; a stray 10 days sits nearest a week.
        if UpdateFrequency.nearest(to: 10 * 86_400) != .weekly { problems.append("10 days did not read as weekly") }
        if UpdateFrequency.nearest(to: 86_400) != .daily { problems.append("one day did not read as daily") }
        // Out of range reads as the end it lies beyond, never the opposite one.
        for (value, expected) in [(Double.nan, UpdateFrequency.daily), (.infinity, .monthly), (1e300, .monthly),
                                  (-1e300, .daily), (0, .daily), (90 * 86_400, .monthly)]
        where UpdateFrequency.nearest(to: value) != expected {
            problems.append("\(value) read as \(UpdateFrequency.nearest(to: value).title), not \(expected.title)")
        }
        if !UpdateInstallMode.automatic.detail.contains("30-second") {
            problems.append("the automatic mode did not say it counts down")
        }
        return problems
    }

    static func countdownWaitsForUnsavedWork() -> [String] {
        var problems: [String] = []
        let deadline = Date(timeIntervalSinceReferenceDate: 800_000_000)
        if UpdateCountdownStep.at(deadline.addingTimeInterval(-29.2), deadline: deadline, busy: true) != .counting(secondsLeft: 30) {
            problems.append("29.2 s before the deadline did not count 30")
        }
        if UpdateCountdownStep.at(deadline, deadline: deadline, busy: false) != .install {
            problems.append("the deadline with nothing open did not install")
        }
        if UpdateCountdownStep.at(deadline.addingTimeInterval(5), deadline: deadline, busy: true) != .waiting {
            problems.append("the deadline with a note open did not wait")
        }
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            if store.holdsUnsavedWork { problems.append("a store with nothing open held unsaved work") }
            store.sessionNoteDrafts[UUID()] = "half a thought"
            if !store.holdsUnsavedWork { problems.append("a note being written did not hold the update") }
            store.sessionNoteDrafts.removeAll()
            store.isNamingAutomaticSession = true
            if !store.holdsUnsavedWork { problems.append("an automatic session being named did not hold the update") }
        }
        return problems
    }
}
