import Foundation

/// The four check frequencies map to the intervals the updater stores, and
/// an interval stored some other way still reads as one of them.
enum UpdatePreferenceChecks {
    static let tests: [(String, () -> [String])] = [
        ("Update checks offer daily, weekly, fortnightly and monthly, each its own interval", frequencies)
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
        if !UpdateInstallMode.automatic.detail.contains("30-second") {
            problems.append("the automatic mode did not say it counts down")
        }
        return problems
    }
}
