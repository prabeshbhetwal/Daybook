import Foundation

/// What the Day story says to someone who cannot see it. These break if a
/// spoken summary loses the figures the picture carries.
enum DayStoryAccessibilityChecks {
    static let tests: [(String, () -> [String])] = [
        ("The activity strip's summary names the longest apps first and counts its gaps", stripSummary),
        ("Compact durations are spoken in words, and nothing else is touched", spokenDurations),
        ("Dictation keeps what was said before a pause", dictationAcrossPauses)
    ]

    /// Each case is a run of recogniser results, as (text, ends utterance),
    /// and the note that should come of it.
    private static func dictationAcrossPauses() -> [String] {
        let cases: [(String, [(String, Bool)], String)] = [
            ("partials grow one utterance",
             [("Hello", false), ("Hello there", false)], "Hello there"),
            ("a reset after a pause keeps the first utterance",
             [("Hello there", false), ("And", false), ("And more words", false)],
             "Hello there And more words"),
            ("an utterance the recogniser finishes is kept",
             [("Hello there.", true), ("And", false), ("And more.", true)],
             "Hello there. And more."),
            ("a revision replaces, it does not add",
             [("I scream", false), ("Ice cream", false)], "Ice cream"),
            ("finished on every partial still says each word once",
             [("Hello", true), ("Hello there", true), ("Hello there, friend", true)],
             "Hello there, friend"),
            ("the last utterance sent again is kept once",
             [("Hello there.", true), ("Hello there.", false)], "Hello there."),
            ("a new utterance that happens to be longer is still kept after a finished one",
             [("Yes.", true), ("That is right, thank you.", true)], "Yes. That is right, thank you.")
        ]
        var failures: [String] = []
        for (name, results, expected) in cases {
            var transcript = DictationTranscript()
            var note = ""
            for (text, ends) in results { note = transcript.receive(text, endsUtterance: ends) }
            if note != expected { failures.append("\(name): \"\(note)\", expected \"\(expected)\"") }
        }
        return failures
    }

    private static func spokenDurations() -> [String] {
        var failures: [String] = []
        let cases: [(String, String)] = [
            ("2h 15m", "2 hours 15 minutes"),
            ("1h", "1 hour"),
            ("1m", "1 minute"),
            ("0m", "0 minutes"),
            ("45s", "45 seconds"),
            ("<1s", "under a second"),
            ("You've logged 51m across one focus session.",
             "You've logged 51 minutes across one focus session."),
            ("Daily goal: 30m of a 4h goal", "Daily goal: 30 minutes of a 4 hours goal"),
            // Left alone: clock times, counts, key glyphs and words with digits.
            ("9:15 am to 10:45 am", "9:15 am to 10:45 am"),
            ("Step 1 of 3 · 12 stretches", "Step 1 of 3 · 12 stretches"),
            ("⌥⌘S", "⌥⌘S"),
            ("mp3s and 4ms", "mp3s and 4ms")
        ]
        for (shown, expected) in cases {
            let spoken = DurationText.spoken(in: shown)
            if spoken != expected {
                failures.append("\"\(shown)\" was spoken as \"\(spoken)\", not \"\(expected)\"")
            }
        }
        return failures
    }

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
