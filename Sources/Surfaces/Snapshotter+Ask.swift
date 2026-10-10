import Foundation

/// The chats the Ask scenarios show: written out, with no model behind them.
extension Snapshotter {
    static func askTurns(for scenario: SnapshotScenario) -> [AskTurn] {
        switch scenario {
        case .askAnswered:
            return [augustTurn, septemberTurn]
        case .askFailed:
            return [augustTurn, AskTurn(question: "And what about every week this year?", state: .failed(AskModel.keptLooking),
                                        provenance: ["focus totals (2026)", "focus totals (this week)"])]
        case .askStopped:
            return [augustTurn, AskTurn(question: "And in September?",
                                        answer: "In September 2026 you focused 52h 10m over 58 sessi",
                                        state: .stopped, provenance: ["focus totals (September 2026)"])]
        default:
            return []
        }
    }

    private static let calendar = Calendar.current.forPeriods

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private static func month(_ month: Int, label: String) -> AskLink {
        let span = DateInterval(start: date(2026, month, 1), end: date(2026, month + 1, 1))
        return AskLink(target: .period(HistoryPlace(level: .month, span: span)), label: label, role: .totals)
    }

    private static func week(_ day: Int, label: String) -> AskLink {
        let span = DateInterval(start: date(2026, 9, day), end: date(2026, 9, day + 7))
        return AskLink(target: .period(HistoryPlace(level: .week, span: span)), label: label, role: .bestWeek)
    }

    private static func session(_ name: String, _ month: Int, _ day: Int, label: String, role: AskSourceRole) -> AskLink {
        AskLink(target: .session(thread: UUID(), day: date(2026, month, day)), label: label, role: role, sessionName: name)
    }

    /// A source for the words of `answer` it is named by, as the picker would report them.
    private static func source(_ link: AskLink, _ words: String?, in answer: String) -> AskSource {
        let mention = words.flatMap { answer.range(of: $0) }.map {
            answer.distance(from: answer.startIndex, to: $0.lowerBound)
                ..< answer.distance(from: answer.startIndex, to: $0.upperBound)
        }
        return AskSource(link: link, mention: mention)
    }

    private static var augustTurn: AskTurn {
        let answer = "In August 2026 you focused 60h 54m over 63 sessions on 21 days. The most focused day was Mon 3 Aug, 4h 30m."
        let bestDay = AskLink(target: .day(date(2026, 8, 3)), label: "Mon 3 Aug", role: .bestDay)
        return AskTurn(question: "How much did I focus in August?", answer: answer, state: .answered,
                       provenance: ["focus totals (August 2026)"],
                       sources: [source(month(8, label: "August 2026"), "August 2026", in: answer),
                                 source(bestDay, "Mon 3 Aug", in: answer)])
    }

    /// Seven sources, so the list ends in "Show 2 more", two of them long.
    private static var septemberTurn: AskTurn {
        let answer = "In September 2026 the longest session was Thesis on Tue 15 Sep, 4h 30m. "
            + "Your most focused week was 14 Sep \u{2013} 20 Sep."
        let longest = session("Thesis", 9, 15, label: "Thesis \u{00B7} Tue 15 Sep", role: .longestSession)
        let day = AskLink(target: .day(date(2026, 9, 15)), label: "Tue 15 Sep", role: .bestDay)
        let sources = [
            source(month(9, label: "September 2026"), "September 2026", in: answer),
            source(longest, "Thesis", in: answer),
            source(day, "Tue 15 Sep", in: answer),
            source(week(14, label: "14 Sep \u{2013} 20 Sep"), "14 Sep \u{2013} 20 Sep", in: answer),
            source(session("Parser", 9, 18, label: "Parser \u{00B7} Fri 18 Sep", role: .session), nil, in: answer),
            source(session("Chapter four, the long appendix on sampling error and its limits", 9, 9,
                           label: "Chapter four, the long appendix on sampling error and its limits \u{00B7} Wed 9 Sep",
                           role: .session), nil, in: answer),
            source(session("Reading", 9, 2, label: "Reading \u{00B7} Wed 2 Sep", role: .session), nil, in: answer),
        ]
        return AskTurn(question: "Which was my longest session in September?", answer: answer, state: .answered,
                       provenance: ["find sessions (September 2026)"], sources: sources)
    }
}
