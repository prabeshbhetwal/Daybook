import AppKit
import SwiftUI

/// History's first view: each top period says its focus in one sentence, a
/// second line only from the facts Core found, and its short name in the
/// gutter. Rows below it, and a first week's days, read and draw as before.
enum HistoryPeriodRowChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A month says its focus and its days in one sentence", oneSentence),
        ("The second line is built only from facts", secondLine),
        ("The gutter names the period briefly", gutterNames),
        ("VoiceOver reads a top month as the screen does", spokenTopMonth),
        ("Rows below the first view read exactly as before", nestedRowsUnchanged),
        ("A first week keeps its day rows", firstWeekKeepsDays),
    ]

    private static let calendar = HistoryTreeChecks.calendar
    /// Sunday 15 November 2026, so November is the period still running.
    private static let today = HistoryTreeChecks.date(11, 15)

    private static func place(_ level: HistoryLevel, _ month: Int, _ day: Int) -> HistoryPlace {
        HistoryPlace(level: level, span: HistoryTreeBuilder.period(level, containing: HistoryTreeChecks.date(month, day),
                                                                   calendar: calendar))
    }

    /// A whole month of 2026 with just the figures its words read.
    private static func month(_ month: Int, focused: TimeInterval = 0, days: Int = 0, sessions: Int = 0,
                              tracked: TimeInterval = 0, evidence: Bool = true) -> HistoryRow {
        HistoryRow(place: place(.month, month, 1), focused: focused, tracked: tracked, focusedDays: days,
                   sessions: sessions, mainWorkType: focused > 0 ? .deepWork : nil, hasEvidence: evidence, bars: [])
    }

    private static var november: HistoryRow { month(11, focused: 220_200, days: 9, sessions: 12) }

    private static func oneSentence() -> [String] {
        var problems: [String] = []
        let cases: [(label: String, row: HistoryRow, figure: String?, rest: String)] = [
            ("November, still running", november, "61h 10m", "across 9 days so far."),
            ("October", month(10, focused: 268_200, days: 14, sessions: 20), "74h 30m", "across 14 days."),
            ("a month of one focused day", month(9, focused: 1_800, days: 1, sessions: 1), Tokens.duration(1_800),
             "across one day."),
            ("a month of only a break", month(8), nil, "Nothing focused."),
            ("an empty month", month(7, evidence: false), nil, "Nothing recorded."),
            ("a month of app use only", month(6, tracked: 600), nil, "Recorded app use only · \(Tokens.duration(600))"),
        ]
        for item in cases {
            let line = HistoryRowText.sentence(item.row, today: today)
            expect(line.figure == item.figure && line.rest == item.rest,
                   "\(item.label) read \(line), wanted \(item.figure ?? "no figure") / \(item.rest)", &problems)
        }
        return problems
    }

    private static func secondLine() -> [String] {
        var problems: [String] = []
        let september = place(.month, 9, 1)
        let cases: [(facts: HistoryRowFacts, wanted: String?)] = [
            (HistoryRowFacts(facts: [.recordDay(day: HistoryTreeChecks.date(11, 12), focused: 33_600)], daysLeft: 15),
             "Thu 12 Nov was your longest day yet, at 9h 20m. 15 days left."),
            (HistoryRowFacts(facts: [.biggest, .change(percent: 63, previous: september)], daysLeft: nil),
             "Your biggest month so far, up 63% on September."),
            (HistoryRowFacts(facts: [.change(percent: -20, previous: september)], daysLeft: nil), "Down 20% on September."),
            (HistoryRowFacts(facts: [.started(day: HistoryTreeChecks.date(8, 13))], daysLeft: nil), "You started on 13 Aug."),
            (HistoryRowFacts(facts: [], daysLeft: 1), "1 day left."),
            (HistoryRowFacts(facts: [.biggest], daysLeft: nil), "Your biggest month so far."),
            // A week names the one before it with "to", as its gutter does, never a dash.
            (HistoryRowFacts(facts: [.change(percent: 20, previous: place(.week, 11, 2))], daysLeft: nil),
             "Up 20% on 2 to 8 Nov."),
            // November holds 61h 10m over 9 days, and none of it is a fact.
            (.none, nil),
        ]
        for item in cases {
            let line = HistoryRowText.detail(item.facts, row: november, calendar: calendar)
            expect(line == item.wanted, "\(item.facts) read \(line ?? "no line"), wanted \(item.wanted ?? "no line")",
                   &problems)
        }
        let year = HistoryRow(place: place(.year, 11, 1), focused: 220_200, tracked: 0, focusedDays: 9, sessions: 12,
                              mainWorkType: .deepWork, hasEvidence: true, bars: [])
        let yearLine = HistoryRowText.detail(HistoryRowFacts(facts: [.biggest], daysLeft: nil), row: year, calendar: calendar)
        expect(yearLine == "Your biggest year so far.", "a year read \(yearLine ?? "no line")", &problems)
        // No sentence of any row's second line carries a dash, whichever period it names.
        let previous = [place(.week, 11, 2), place(.week, 10, 26), place(.week, 11, 9), place(.month, 9, 1), place(.year, 11, 1)]
        for row in [november, year, month(11), HistoryRow(place: place(.week, 11, 9), focused: 3_600, tracked: 0, focusedDays: 1,
                                                          sessions: 1, mainWorkType: .deepWork, hasEvidence: true, bars: [])] {
            for named in previous {
                let facts = HistoryRowFacts(facts: [.biggest, .change(percent: 20, previous: named)], daysLeft: 3)
                let line = HistoryRowText.detail(facts, row: row, calendar: calendar) ?? ""
                expect(!line.contains("–") && !line.contains("—"), "\(row.place.level) row read \"\(line)\"", &problems)
            }
        }
        return problems
    }

    private static func gutterNames() -> [String] {
        var problems: [String] = []
        let names = [place(.month, 11, 1), place(.year, 11, 1), place(.week, 11, 9)]
            .map { HistoryRowText.gutter($0, calendar: calendar) }
        expect(names == ["Nov", "2026", "9 to 15"], "the gutter read \(names)", &problems)
        expect(HistoryPeriodRow.gutterWidth(for: .day) == 0,
               "a day row has a gutter of \(HistoryPeriodRow.gutterWidth(for: .day))", &problems)
        return problems
    }

    private static func spokenTopMonth() -> [String] {
        let spoken = HistoryRowText.spoken(november, today: today, isOpen: false, depth: 0, calendar: calendar)
        let wanted = "November 2026, 61 hours 10 minutes across 9 days so far, month, level 1, collapsed"
        var problems = spoken == wanted ? [] : ["a top November was spoken as \"\(spoken)\", wanted \"\(wanted)\""]
        // With a second line, it follows the sentence, durations in words, as its own part.
        let facts = HistoryRowFacts(facts: [.recordDay(day: HistoryTreeChecks.date(11, 4), focused: 18_060)], daysLeft: 15)
        let withDetail = HistoryRowText.spoken(november, today: today, isOpen: false, depth: 0, calendar: calendar,
                                               facts: facts)
        let wantedDetail = "November 2026, 61 hours 10 minutes across 9 days so far, "
            + "Wed 4 Nov was your longest day yet, at 5 hours 1 minute. 15 days left, month, level 1, collapsed"
        if withDetail != wantedDetail {
            problems.append("a top November with a second line was spoken as \"\(withDetail)\", wanted \"\(wantedDetail)\"")
        }
        return problems
    }

    private static func nestedRowsUnchanged() -> [String] {
        var problems: [String] = []
        let days = HistoryTreeChecks.september + [HistoryTreeChecks.row(1, 5, focused: 600, sessions: 1)]
        let today = HistoryTreeChecks.today
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        guard let september = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
                .first(where: { calendar.component(.month, from: $0.place.start) == 9 }) else { return ["no September row"] }
        let weeks = HistoryTreeBuilder.rows(under: september.place, top: top, days: days, calendar: calendar)
        guard weeks.count > 2, let monday = HistoryTreeBuilder.rows(under: weeks[0].place, top: top, days: days,
                                                                    calendar: calendar)
                .first(where: { $0.place.start == HistoryTreeChecks.date(9, 28) }) else {
            return ["September's weeks or Monday 28 September are missing: \(weeks.count) weeks"]
        }
        // Captured from these functions before the first view was redrawn.
        let wanted: [(row: HistoryRow, depth: Int, words: (String, String, String))] = [
            (weeks[2], 1, ("14 – 20 Sep", "15m · 1 day", "14 – 20 Sep, 15 minutes across 1 day, week, level 2, collapsed")),
            (monday, 2, ("Mon 28 Sep", "1h · 2 sessions", "Mon 28 Sep, 1 hour, 2 sessions, day, level 3, collapsed")),
        ]
        for item in wanted {
            let words = (HistoryRowText.title(item.row.place, today: today, calendar: calendar),
                         HistoryRowText.facts(item.row, today: today),
                         HistoryRowText.spoken(item.row, today: today, isOpen: false, depth: item.depth, calendar: calendar))
            expect(words == item.words, "a row at depth \(item.depth) read \(words), wanted \(item.words)", &problems)
        }
        return problems
    }

    /// A record of one morning: the top is this week, its rows are days.
    private static func firstWeekKeepsDays() -> [String] {
        NameSuggestionStoreChecks.withFixture(records: { days in
            [NameSuggestionStoreChecks.record(days.at(0, 8), days.at(0, 9))]
        }) { f, _, problems in
            f.store.setReviewVisible(true)
            f.store.refreshReview()
            let top = f.store.historyTop()
            guard top.rootLevel == .day,
                  let today = f.store.historyRows(under: nil).first(where: { $0.place.span.holds(top.today) }) else {
                problems.append("a record of one morning gave \(top.rootLevel) rows, so the case tests nothing")
                return
            }
            // A period row says "so far" on the period holding today; a day's plain header never does.
            let period = render(HistoryPeriodRow(store: f.store, row: today, facts: .none, isCurrent: true,
                                                 isOpen: false, isFocused: false))
            expect(period.contains(.historySoFar), "a period row holding today reported no So far, so "
                   + "the check below proves nothing", &problems)
            let drawn = render(HistoryTreeRow(store: f.store, navigation: MainWindowModel(store: f.store),
                                              row: today, depth: 0, link: HistoryGridLink()))
            expect(!drawn.contains(.historySoFar), "today's row in a first week was drawn as a period row", &problems)
            expect(HistoryPeriodRow.gutterWidth(for: top.rootLevel) == 0,
                   "a first week's day rows have a gutter of \(HistoryPeriodRow.gutterWidth(for: top.rootLevel))",
                   &problems)
        }
    }

    @MainActor private static func render<V: View>(_ view: V) -> Set<StoryRenderEvidence> {
        ActivityRuleChecks.renderEvidence(AnyView(view), width: 640, height: 260)
    }
}
