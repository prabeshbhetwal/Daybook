import Foundation

/// What the Day story says to someone who cannot see it. These break if a
/// spoken summary loses the figures the picture carries.
enum DayStoryAccessibilityChecks {
    static let tests: [(String, () -> [String])] = [
        ("The activity strip's summary names the longest apps first and counts its gaps", stripSummary)
    ]

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func segment(_ name: String, _ from: TimeInterval, _ to: TimeInterval) -> TimelineSegment {
        TimelineSegment(id: UUID(), bundleID: "test." + name.lowercased(), appName: name,
                        start: start.addingTimeInterval(from), end: start.addingTimeInterval(to),
                        colorIndex: 0)
    }

    /// Xcode appears twice and must be summed; the fourth app is counted, not
    /// named; the one hole between Safari and Mail is the only gap.
    private static func stripSummary() -> [String] {
        let activity = RecordedActivity(
            segments: [segment("Xcode", 0, 1_200), segment("Safari", 1_200, 1_800),
                       segment("Mail", 2_100, 2_220), segment("Notes", 2_220, 2_280),
                       segment("Xcode", 2_280, 2_880)],
            spans: [DateInterval(start: start, duration: 2_880)])
        let summary = StoryShapeChart.summary(of: activity)
        let expected = "Xcode 30 minutes, Safari 10 minutes, Mail 2 minutes, and 1 more app. "
            + "1 gap with no app recording."
        var failures: [String] = []
        if summary != expected { failures.append("the strip summary read \"\(summary)\"") }
        let empty = RecordedActivity(segments: [], spans: [DateInterval(start: start, duration: 60)])
        if !StoryShapeChart.summary(of: empty).hasPrefix("No app use recorded.") {
            failures.append("an empty strip claimed app use: \(StoryShapeChart.summary(of: empty))")
        }
        return failures
    }
}
