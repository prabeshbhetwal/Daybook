import Foundation

/// Percentages are worked out from stored figures, which are kept verbatim
/// even when malformed. A share or level that comes out NaN, infinite or past
/// `Int` prints a dash instead of crashing, and every real one reads as before.
enum PercentTextChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A malformed stored figure shows a dash or a whole per cent instead of crashing",
         malformedFigureDoesNotCrash),
        ("Every well-formed share and battery level reads the same whole per cent as before",
         wellFormedFigureUnchanged),
    ]

    private static func malformedFigureDoesNotCrash() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.anchoredNow())
        let start = clock.value.addingTimeInterval(-2 * 3_600)
        let end = clock.value.addingTimeInterval(-3_600)

        // A negative session length made today's goal share about -7e295,
        // which the idle menu bar spoke through `Int(_:)` on every refresh.
        let negative = SelfTest.makeArchive(clock, records: [
            SessionRecord(name: "Corrupted", workType: .deepWork, start: start, end: end,
                          workSeconds: -1e300)
        ])
        let goal = DailyGoal(archive: negative, goal: 4 * 3_600, now: { clock.value }).progress()
        let label = MenuBarDisplay(state: .idle, elapsed: 0, needsAttention: false,
                                   goal: goal, showsTime: false).accessibilityLabel
        let spokenGoal = figure(before: " of today's goal", in: label)
            .replacingOccurrences(of: " per cent", with: "")
        expect(isDashOrWhole(spokenGoal),
               "the idle menu bar should give today's goal as a dash or a whole per cent, got \(label)",
               &problems)

        // Two lengths near the largest Double summed to infinity, which made
        // each work type's share of that total NaN.
        let huge = SelfTest.makeArchive(clock, records: [
            SessionRecord(name: "Huge", workType: .deepWork, start: start, end: end, workSeconds: 1e308),
            SessionRecord(name: "Huge", workType: .deepWork, start: start, end: end, workSeconds: 1e308),
            SessionRecord(name: "Admin", workType: .admin, start: start, end: end, workSeconds: 1_800)
        ])
        let stats = DashboardStats(sessions: huge,
                                   usage: SelfTest.makeUsageArchive(clock, sessions: []),
                                   now: { clock.value })
        let shares = stats.focusQuality(for: clock.value).byWorkType
        let summary = SummaryText.plain(SummaryText.day(DaySummaryInput(
            day: clock.value, isToday: true, tracked: 3_600, firstSeen: nil, lastSeen: nil,
            focused: 3_600, goal: 0, sessions: [], rests: [], apps: [], peak: nil,
            insideSessionShare: 0, switchesPerStretch: 0, workTypes: shares,
            previousTracked: 0, previousFocused: 0)))
        for share in shares where summary.contains("\(share.workType.displayName) ") {
            let text = figure(after: "\(share.workType.displayName) ", in: summary)
            expect(isDashOrWhole(text.replacingOccurrences(of: "%", with: "")),
                   "the day summary should give \(share.workType.displayName) a dash or a whole per cent, "
                       + "got \(summary)", &problems)
        }

        // A battery level is decoded verbatim from the session's metadata.
        let level = PowerObservation(timestamp: start, source: .battery,
                                     percentage: 1e300, charging: .notCharging)
        let reading = PowerReading(level)
        expect(reading.level.isEmpty, "a battery level of 1e300 should read as unknown, got \(reading.level)",
               &problems)
        let power = PowerContextSummary.make(observations: [level],
                                             interval: DateInterval(start: start, end: end))
        expect(power?.headline == "Using battery · —",
               "a battery level of 1e300 should head the power summary as a dash, got "
                   + "\(power?.headline ?? "nothing")", &problems)

        for share in [Double.nan, .infinity, -.infinity, -6.94e295, 3.6e303] {
            expect(DurationText.percent(share) == "—" && DurationText.percent(share, spoken: true) == "—",
                   "a share of \(share) should read as a dash, got "
                       + "\(DurationText.percent(share)) and \(DurationText.percent(share, spoken: true))",
                   &problems)
        }
        return problems
    }

    private static func wellFormedFigureUnchanged() -> [String] {
        var problems: [String] = []
        // 0 to 1200 per cent, past the 999% the Focus ring clamps to.
        for step in 0...24_000 {
            let share = Double(step) / 2_000
            let whole = Int((share * 100).rounded())
            let text = DurationText.percent(share)
            let spoken = DurationText.percent(share, spoken: true)
            if text != "\(whole)%" || spoken != "\(whole) per cent" {
                problems.append("a share of \(share) should read \(whole)%, got \(text) and \(spoken)")
                break
            }
        }
        let now = SelfTest.anchoredNow()
        for step in 0...400 {
            let percentage = Double(step) / 4
            let reading = PowerReading(PowerObservation(timestamp: now, source: .battery,
                                                        percentage: percentage, charging: .notCharging))
            if reading.level != "\(Int(percentage.rounded()))%" {
                problems.append("a battery level of \(percentage) should read "
                                + "\(Int(percentage.rounded()))%, got \(reading.level)")
                break
            }
        }
        return problems
    }

    /// The word just before `marker`, or just after `prefix`, with trailing
    /// punctuation dropped.
    private static func figure(before marker: String, in text: String) -> String {
        guard let range = text.range(of: marker) else { return "" }
        let head = text[..<range.lowerBound]
        let words = head.split(separator: " ")
        // "12 per cent" is three words; keep it whole.
        if head.hasSuffix(" per cent"), words.count >= 3 {
            return words.suffix(3).joined(separator: " ")
        }
        return words.last.map(String.init) ?? ""
    }

    private static func figure(after prefix: String, in text: String) -> String {
        guard let range = text.range(of: prefix) else { return "" }
        let word = text[range.upperBound...].prefix { !" ,;.".contains($0) }
        return String(word)
    }

    private static func isDashOrWhole(_ text: String) -> Bool {
        text == "—" || (!text.isEmpty && text.allSatisfy(\.isASCII) && text.allSatisfy(\.isNumber))
    }
}
