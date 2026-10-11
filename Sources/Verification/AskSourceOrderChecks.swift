import Foundation

/// Which places an Ask answer names, and the order a reader can check it by:
/// the places the answer names in the order it names them, then each lookup's
/// own place that the answer did not name.
enum AskSourceOrderChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A day the answer names comes first, then the lookup's own place", namedDayThenAnchor),
        ("Sources follow the answer's reading order, not the order of the lookups", readingOrderNotLookupOrder),
        ("Reading order holds the other way round, and a mention is the offsets of its words", readingOrderOtherWay),
        ("A day written with another year is not named", wrongYearIsNotNamed),
        ("A day's month is not a month named", dayNumberDoesNotNameMonth),
        ("Yesterday names the day before the question was asked", yesterdayNamesDay),
        ("A week is named by its two ends or as this week", weekByEndsOrThisWeek),
        ("Sessions sharing a name: the one whose day is named", sharedNameUsesNamedDay),
        ("Sessions sharing a name: otherwise the newest", sharedNameDefaultsToNewest),
        ("Session names match whatever the case or accents", accentsAndCaseIgnored),
        ("Dates the picker cannot read fall back to each lookup's own place", unreadFormatsFallBackToAnchors),
        ("A place two lookups share is listed once, at its first place", sameTargetListedOnce),
        ("A lookup adds only its anchor, never its other places, however many the answer left unnamed", anchorOnly),
        ("The whole week and History's clipped week are one place and are listed once", clippedWeekIsTheSamePlace),
        ("The word may names May only when capitalised or written with a year", mayIsMonthOnlyWhenWritten),
    ]

    /// Every date comes from the calendar the picker is given, so the suite
    /// holds in any time zone.
    private enum Fixture {
        static let calendar = Calendar.current.forPeriods

        static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }

        /// Saturday 10 October 2026.
        static let now = date(2026, 10, 10, hour: 17, minute: 30)

        static let tue15 = AskLink(target: .day(date(2026, 9, 15)), label: "Tue 15 Sep", role: .bestDay)
        static let fri9 = AskLink(target: .day(date(2026, 10, 9)), label: "Fri 9 Oct", role: .bestDay)
        static let sep = AskLink(
            target: .period(HistoryPlace(level: .month, span: DateInterval(start: date(2026, 9, 1), end: date(2026, 10, 1)))),
            label: "September 2026", role: .totals)
        static let may = AskLink(
            target: .period(HistoryPlace(level: .month, span: DateInterval(start: date(2026, 5, 1), end: date(2026, 6, 1)))),
            label: "May 2026", role: .totals)
        static let week = AskLink(
            target: .period(HistoryPlace(level: .week, span: DateInterval(start: date(2026, 10, 5), end: date(2026, 10, 12)))),
            label: "5 Oct \u{2013} 11 Oct", role: .bestWeek)
        static let thesisSep = AskLink(target: .session(thread: UUID(), day: date(2026, 9, 15)),
                                       label: "Thesis \u{00B7} Tue 15 Sep", role: .session, sessionName: "Thesis")
        static let thesisOct = AskLink(target: .session(thread: UUID(), day: date(2026, 10, 9)),
                                       label: "Thesis \u{00B7} Fri 9 Oct", role: .session, sessionName: "Thesis")
        static let cafe = AskLink(target: .session(thread: UUID(), day: date(2026, 10, 9)),
                                  label: "Caf\u{00E9} notes \u{00B7} Fri 9 Oct", role: .session, sessionName: "Caf\u{00E9} notes")
        static let all = AskLink(target: .history, label: "All time", role: .totals)
        static let year = AskLink(
            target: .period(HistoryPlace(level: .year, span: DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1)))),
            label: "2026", role: .totals)
        /// The same week as `week`, drawn by History to the end of Fri 9 Oct.
        static let clippedWeek = AskLink(
            target: .period(HistoryPlace(level: .week, span: DateInterval(start: date(2026, 10, 5), end: date(2026, 10, 10)))),
            label: "5 Oct \u{2013} 9 Oct", role: .bestWeek)
    }

    private static func pick(_ answer: String, _ lookups: [[AskLink]]) -> [AskSource] {
        AskSourcePicker.sources(answer: answer, lookups: lookups, calendar: Fixture.calendar, now: Fixture.now)
    }

    /// Labels in order, an anchor the answer did not name marked `[anchor]`.
    private static func described(_ sources: [AskSource]) -> [String] {
        sources.map { $0.link.label + ($0.mention == nil ? " [anchor]" : "") }
    }

    private static func expectOrder(_ answer: String, _ lookups: [[AskLink]], _ expected: [String],
                                    _ problems: inout [String]) {
        let got = described(pick(answer, lookups))
        expect(got == expected, "\"\(answer)\" lists \(got), not \(expected)", &problems)
    }

    /// Character offsets of `words` in `answer`, as the picker reports them.
    private static func offsets(of words: String, in answer: String) -> Range<Int>? {
        guard let found = answer.range(of: words) else { return nil }
        return answer.distance(from: answer.startIndex, to: found.lowerBound)
            ..< answer.distance(from: answer.startIndex, to: found.upperBound)
    }

    private static func namedDayThenAnchor() -> [String] {
        var problems: [String] = []
        expectOrder("The most focused day in the entire year was Tuesday, 15 September.",
                    [[Fixture.all, Fixture.tue15, Fixture.sep]], ["Tue 15 Sep", "All time [anchor]"], &problems)
        return problems
    }

    private static func readingOrderNotLookupOrder() -> [String] {
        var problems: [String] = []
        expectOrder("Tue 15 Sep was the best day of September 2026.",
                    [[Fixture.sep, Fixture.tue15]], ["Tue 15 Sep", "September 2026"], &problems)
        return problems
    }

    private static func readingOrderOtherWay() -> [String] {
        var problems: [String] = []
        let answer = "In September 2026, the best day was Tue 15 Sep, with 9h."
        let sources = pick(answer, [[Fixture.sep, Fixture.tue15]])
        expect(described(sources) == ["September 2026", "Tue 15 Sep"], "lists \(described(sources))", &problems)
        expect(sources.last?.mention == offsets(of: "Tue 15 Sep", in: answer),
               "the day's mention is \(String(describing: sources.last?.mention)), "
               + "not the offsets of \"Tue 15 Sep\"", &problems)
        return problems
    }

    private static func wrongYearIsNotNamed() -> [String] {
        var problems: [String] = []
        expectOrder("Your best day was 15 September 2025.",
                    [[Fixture.sep, Fixture.tue15]], ["September 2026 [anchor]"], &problems)
        return problems
    }

    private static func dayNumberDoesNotNameMonth() -> [String] {
        var problems: [String] = []
        expectOrder("The best day was 15 September.",
                    [[Fixture.sep, Fixture.tue15]], ["Tue 15 Sep", "September 2026 [anchor]"], &problems)
        return problems
    }

    private static func yesterdayNamesDay() -> [String] {
        var problems: [String] = []
        expectOrder("Yesterday you focused 3h 42m.", [[Fixture.fri9]], ["Fri 9 Oct"], &problems)
        return problems
    }

    private static func weekByEndsOrThisWeek() -> [String] {
        var problems: [String] = []
        let ends = "The most focused week was 5 Oct \u{2013} 11 Oct."
        expectOrder(ends, [[Fixture.week]], ["5 Oct \u{2013} 11 Oct"], &problems)
        expect(pick(ends, [[Fixture.week]]).first?.mention == offsets(of: "5 Oct \u{2013} 11 Oct", in: ends),
               "a week named by its ends is mentioned across both", &problems)
        expectOrder("This week was your best.", [[Fixture.week]], ["5 Oct \u{2013} 11 Oct"], &problems)
        expectOrder("The week of Monday 5 October was your best.", [[Fixture.week]], ["5 Oct \u{2013} 11 Oct"], &problems)
        expectOrder("Last week was quieter.", [[Fixture.week]], ["5 Oct \u{2013} 11 Oct [anchor]"], &problems)
        return problems
    }

    private static func sharedNameUsesNamedDay() -> [String] {
        var problems: [String] = []
        expectOrder("Thesis ran longest on Friday 9 October.", [[Fixture.thesisSep, Fixture.thesisOct]],
                    ["Thesis \u{00B7} Fri 9 Oct", "Thesis \u{00B7} Tue 15 Sep [anchor]"], &problems)
        return problems
    }

    private static func sharedNameDefaultsToNewest() -> [String] {
        var problems: [String] = []
        expectOrder("Thesis ran longest.", [[Fixture.thesisSep], [Fixture.thesisOct]],
                    ["Thesis \u{00B7} Fri 9 Oct", "Thesis \u{00B7} Tue 15 Sep [anchor]"], &problems)
        return problems
    }

    private static func accentsAndCaseIgnored() -> [String] {
        var problems: [String] = []
        expectOrder("Most of it went to cafe NOTES.", [[Fixture.cafe]], ["Caf\u{00E9} notes \u{00B7} Fri 9 Oct"], &problems)
        return problems
    }

    private static func unreadFormatsFallBackToAnchors() -> [String] {
        var problems: [String] = []
        expectOrder("Your best day was 15/9, a Tuesday.", [[Fixture.sep, Fixture.tue15], [Fixture.all]],
                    ["September 2026 [anchor]", "All time [anchor]"], &problems)
        return problems
    }

    private static func sameTargetListedOnce() -> [String] {
        var problems: [String] = []
        expectOrder("Tue 15 Sep.", [[Fixture.tue15], [Fixture.tue15, Fixture.sep]], ["Tue 15 Sep"], &problems)
        return problems
    }

    /// Spec section 5: each lookup's anchor when it is not already listed, not its
    /// first unlisted place. A year total that names only the year does not
    /// drag in the best day it also returned.
    private static func anchorOnly() -> [String] {
        var problems: [String] = []
        expectOrder("In 2026 you focused 120h 5m.", [[Fixture.year, Fixture.tue15]], ["2026"], &problems)
        expectOrder("Nothing here is named.", [[Fixture.year, Fixture.tue15], [Fixture.sep, Fixture.fri9]],
                    ["2026 [anchor]", "September 2026 [anchor]"], &problems)
        return problems
    }

    private static func clippedWeekIsTheSamePlace() -> [String] {
        var problems: [String] = []
        expectOrder("Nothing here is named.", [[Fixture.week], [Fixture.clippedWeek]], ["5 Oct \u{2013} 11 Oct [anchor]"],
                    &problems)
        expectOrder("This week was your best.", [[Fixture.clippedWeek], [Fixture.week]], ["5 Oct \u{2013} 9 Oct"], &problems)
        return problems
    }

    private static func mayIsMonthOnlyWhenWritten() -> [String] {
        var problems: [String] = []
        expectOrder("You may do well.", [[Fixture.may]], ["May 2026 [anchor]"], &problems)
        expectOrder("In May you focused most.", [[Fixture.may]], ["May 2026"], &problems)
        expectOrder("In may 2026 you focused most.", [[Fixture.may]], ["May 2026"], &problems)
        return problems
    }
}
