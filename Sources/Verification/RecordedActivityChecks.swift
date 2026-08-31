import Foundation

/// Literal evidence cases for the Story's session activity detail. These use
/// only fixed intervals, so no calendar, process, or live archive can affect
/// their result.
enum RecordedActivityChecks {
    static let tests: [(String, () -> [String])] = [
        ("Recorded activity prose keeps finite short observations factual", shortDurationProse),
        ("Recorded activity prose counts switches from the foreground projection", canonicalSwitchProse),
        ("Recorded activity duration text marks invalid values unavailable", unavailableDurationText),
        ("Recorded activity prose ignores zero-length app records", zeroLengthEvidence),
        ("Recorded activity coverage never sums overlapping records", overlappingEvidence),
        ("Recorded activity projects gaps without calling them rest", canonicalGaps)
    ]

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func segment(_ name: String, _ startOffset: TimeInterval,
                                _ endOffset: TimeInterval) -> TimelineSegment {
        TimelineSegment(id: UUID(), bundleID: "test." + name.lowercased(), appName: name,
                        start: start.addingTimeInterval(startOffset),
                        end: start.addingTimeInterval(endOffset), colorIndex: 0)
    }

    /// Breaks if sub-minute source evidence is rounded down to a minute or if
    /// fractional evidence is sent through an unsafe integer conversion.
    private static func shortDurationProse() -> [String] {
        let chat = segment("ChatGPT", 0, 31)
        let paragraph = SessionShape.paragraph(.init(segments: [chat], workType: .deepWork,
                                                     stretches: 1, worked: 31)) ?? ""
        var failures: [String] = []
        if !paragraph.contains("31s") || paragraph.contains("0m") {
            failures.append("a 31-second ChatGPT observation was not described as 31s")
        }
        if Tokens.preciseDuration(0.4) != "<1s" {
            failures.append("a positive fractional observation was not described as <1s")
        }
        return failures
    }

    /// Breaks if an overlapping source record that lost the foreground tie is
    /// still counted as an app switch in the reader-facing prose.
    private static func canonicalSwitchProse() -> [String] {
        let xcode = segment("Xcode", 0, 30)
        let safari = segment("Safari", 10, 40)
        let chrome = segment("Chrome", 20, 25)
        let activity = RecordedActivity(segments: [xcode, safari, chrome],
                                        spans: [DateInterval(start: start, duration: 40)])
        let paragraph = SessionShape.paragraph(.init(segments: [xcode, safari, chrome], activity: activity,
                                                     workType: .deepWork, stretches: 1, worked: 40)) ?? ""
        return paragraph.contains("You moved between apps once.")
            && !paragraph.contains("2 times")
            && !paragraph.contains("Chrome")
            ? [] : ["nested overlapping records added a raw-source app switch to canonical prose"]
    }

    /// Breaks if corrupt or unrepresentable persisted duration values are
    /// silently presented as zero seconds rather than unavailable evidence.
    private static func unavailableDurationText() -> [String] {
        let invalid: [TimeInterval] = [-1, -.infinity, .infinity, .nan, TimeInterval(Int.max)]
        return invalid.allSatisfy { DurationText.precise($0) == "—" }
            ? [] : ["invalid duration evidence was rendered as an ordinary duration"]
    }

    /// Breaks if an actual zero-length record becomes a second app or a switch
    /// claim in the factual session prose.
    private static func zeroLengthEvidence() -> [String] {
        let chat = segment("ChatGPT", 0, 31)
        let finder = segment("Finder", 31, 31)
        let paragraph = SessionShape.paragraph(.init(segments: [chat, finder], workType: .deepWork,
                                                     stretches: 1, worked: 31)) ?? ""
        return paragraph.contains("Finder") || paragraph.contains("across 2 apps")
            || paragraph.contains("moved between")
            ? ["a zero-length Finder record introduced a second-app or app-switch claim"] : []
    }

    /// Breaks if [0,30] and [10,40] are summed as sixty seconds rather than
    /// represented as forty seconds of observed foreground coverage.
    private static func overlappingEvidence() -> [String] {
        let first = segment("Editor", 0, 30)
        let second = segment("Browser", 10, 40)
        let paragraph = SessionShape.paragraph(.init(segments: [first, second], workType: .deepWork,
                                                     stretches: 1, worked: 40)) ?? ""
        return paragraph.contains("40s") && !paragraph.contains("60s")
            ? [] : ["overlapping [0,30] and [10,40] records did not retain 40 seconds of coverage"]
    }

    /// Breaks if canonical intervals omit an evidenced gap, turn it into a
    /// foreground app, or count the enclosed run more than once.
    private static func canonicalGaps() -> [String] {
        let activity = RecordedActivity(segments: [segment("Editor", 10, 20)],
                                        spans: [DateInterval(start: start, duration: 30)])
        let gaps = activity.intervals.filter(\.isGap)
        let apps = activity.intervals.filter { !$0.isGap }
        var failures: [String] = []
        if activity.coverage != 10 || activity.gapDuration != 20 {
            failures.append("a [10,20] run inside [0,30] did not preserve its 10 seconds of coverage and 20 seconds of gaps")
        }
        if gaps.count != 2 || gaps.map(\.duration) != [10, 10] {
            failures.append("the two explicit recording gaps were merged or hidden")
        }
        if apps.count != 1 || apps.first?.appName != "Editor" || apps.first?.recordedSeconds != 10 {
            failures.append("the only observed interval did not retain its app identity and duration")
        }
        if gaps.contains(where: { $0.appName != nil || $0.bundleID != nil }) {
            failures.append("a recording gap acquired an app or rest identity")
        }
        return failures
    }
}
