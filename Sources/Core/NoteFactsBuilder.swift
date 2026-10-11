import Foundation

private func timeOfDay(_ date: Date, _ calendar: Calendar) -> String {
    DateFormats.australian("h:mm a", in: calendar.timeZone).string(from: date)
}

/// A session or stretch the day begins in the middle of: the day's sessions are
/// clipped to its start, so it began the night before.
// ponytail: one that truly began at 00:00 reads the same, since only the clipped start is kept; carry the unclipped start in `DaySession` to tell them apart.
private func carriesOver(_ date: Date, _ calendar: Calendar) -> Bool {
    date == calendar.startOfDay(for: date)
}

private func longDate(_ date: Date, _ calendar: Calendar) -> String {
    DateFormats.australian("EEEE d MMMM yyyy", in: calendar.timeZone).string(from: date)
}

private func counted(_ count: Int, _ noun: String, plural: String? = nil) -> String {
    "\(count) \(count == 1 ? noun : plural ?? noun + "s")"
}

/// "1h more focus than the week before", or nil with nothing to compare with
/// or a difference under a minute. `than` ends the sentence.
private func comparison(_ focused: TimeInterval, with other: TimeInterval, than: String) -> String? {
    guard other > 0 else { return nil }
    let difference = focused - other
    guard abs(difference) >= 60 else { return nil }
    return "\(DurationText.compact(abs(difference))) \(difference > 0 ? "more" : "less") focus than \(than)"
}

/// The sessions a day's, week's or month's facts name, by time spent. The
/// probe's week notes totalled "other sessions" when there were more.
private let namedTotalLimit = 3

/// "Most time went to: Parser: 1h 40m; Thesis: 50m", busiest first: "name:
/// duration" joined by semicolons, since a name may hold a comma or end in a
/// number.
private func mostTimeLine(_ totals: [(name: String, worked: TimeInterval)]) -> String {
    "Most time went to: " + totals.prefix(namedTotalLimit)
        .map { "\($0.name): \(DurationText.compact($0.worked))" }.joined(separator: "; ")
}

extension NoteFacts {

    /// The facts for one day, or nil when it has no sessions. The sessions are
    /// named by time spent, not listed in order: History already lists them,
    /// and a note handed the list retold it. The observations weigh the day
    /// against the person's own typical day, and none is a calendar artefact:
    /// a session carried over from the night before once became "Focus carried
    /// on past midnight", and the tip built on it said to keep doing that.
    static func day(_ input: NoteDayInput, calendar: Calendar) -> NoteFacts? {
        guard !input.sessions.isEmpty else { return nil }
        let compact = DurationText.compact
        var lines = ["Day: " + longDate(input.date, calendar) + (input.isCurrent ? " (so far)" : ""),
                     "Focus: \(compact(input.focused)) over \(counted(input.sessionCount, "session"))"]
        if input.goal > 0 {
            lines.append("Daily goal: \(compact(input.goal)); counted towards it: \(compact(input.goalCredit)) "
                         + "of focus with hands-on app use; met: \(input.goalCredit >= input.goal ? "yes" : "no")")
        }
        // Named as the Story and a week's facts name them: a blank name is its kind's.
        var worked: [String: TimeInterval] = [:]
        for session in input.sessions { worked[session.workType.sessionTitle(named: session.name), default: 0] += session.worked }
        lines.append(mostTimeLine(worked.map { (name: $0.key, worked: $0.value) }
            .sorted { $0.worked != $1.worked ? $0.worked > $1.worked : $0.name < $1.name }))
        let topApps = input.apps.filter { $0.total > 0 }
        if !topApps.isEmpty {
            lines.append("Top apps: " + topApps.prefix(3).map { "\($0.appName) \(compact($0.total))" }
                .joined(separator: ", "))
        }

        var observations: [String] = []
        if let change = comparison(input.focused, with: input.typicalFocused,
                                   than: "your typical day of \(compact(input.typicalFocused)) (the median of "
                                       + "\(input.typicalDays) days with focus in your last \(NoteBaseline.days))") {
            observations.append(change)
        }
        // The part that held the most focus, worth saying once it holds a fair share of it. The
        // share is of the parts' own sum: on a day with no midnight the day's total runs an hour long.
        let partsTotal = input.focusByPart.values.reduce(0, +)
        if let best = NoteDayPart.allCases.map({ (part: $0, focused: input.focusByPart[$0] ?? 0) })
            .max(by: { $0.focused < $1.focused }), best.focused >= 60, best.focused >= partsTotal * 0.4 {
            observations.append("The most focus came \(best.part.phrase): \(compact(best.focused))")
        }
        let stretchCount = input.sessions.reduce(0) { $0 + $1.stretches }
        if stretchCount > 1 {
            observations.append("Focus ran as \(counted(stretchCount, "stretch", plural: "stretches")) averaging "
                                + compact(input.focused / Double(stretchCount))
                                + (input.typicalStretch > 0 ? "; your typical stretch is \(compact(input.typicalStretch))" : ""))
        }
        // A stretch the day begins in the middle of is the night before's.
        if let longest = input.longestStretch, longest.worked >= 600, !carriesOver(longest.start, calendar) {
            observations.append("Longest stretch: \(compact(longest.worked)) in \(longest.name), "
                                + "from \(timeOfDay(longest.start, calendar))")
        }
        return NoteFacts(kind: .day, lines: lines, observations: observations)
    }

    /// The facts for one week or month, or nil when History counts no
    /// sessions in it (or `level` is neither).
    static func period(_ input: NotePeriodInput, calendar: Calendar) -> NoteFacts? {
        let summary = input.summary
        guard summary.sessions > 0 else { return nil }
        let heading: String
        switch input.level {
        case .week: heading = "Week of " + longDate(input.span.start, calendar)
        case .month: heading = "Month: " + DateFormats.australian("MMMM yyyy", in: calendar.timeZone).string(from: input.span.start)
        default: return nil
        }
        let noun = input.level.spokenName

        var lines = [heading + (input.isCurrent ? " (so far)" : ""),
                     "Focus: \(DurationText.compact(summary.focused)) over \(counted(summary.sessions, "session")) "
                     + "on \(counted(summary.focusedDays, "day"))"]
        if !input.sessionTotals.isEmpty { lines.append(mostTimeLine(input.sessionTotals)) }

        // Each is a sentence the note can quote whole, as a day's are.
        var observations: [String] = []
        if let best = summary.best {
            observations.append("Best day: \(longDate(best.place.start, calendar)) with \(DurationText.compact(best.focused))")
        }
        if input.level == .month, let busiest = input.busiestWeekday {
            let name = DateFormats.australian("EEEE", in: calendar.timeZone).string(from: busiest.date)
            observations.append("Busiest weekday: \(name) with \(DurationText.compact(busiest.focused)) over \(counted(busiest.days, "day"))")
        }
        if let longest = input.longestStretch, longest.worked >= 600 {
            let from = carriesOver(longest.start, calendar) ? "before midnight" : timeOfDay(longest.start, calendar)
            observations.append("Longest stretch: \(DurationText.compact(longest.worked)) in \(longest.name), "
                                + "on \(longDate(longest.start, calendar)) from \(from)")
        }
        if let change = comparison(summary.focused, with: input.previousFocused, than: "the \(noun) before") {
            observations.append(change)
        }
        if input.goal > 0 {
            observations.append("Goal met on \(input.goalMetDays) of \(summary.focusedDays) days with focus")
        }
        if let first = input.sessionTotals.first, summary.focused > 0, first.worked / summary.focused > 0.4 {
            observations.append("\(first.name) took \(DurationText.compact(first.worked)) of the \(noun)")
        }
        return NoteFacts(kind: .period, lines: lines, observations: Array(observations.prefix(5)),
                         namedSessions: min(input.sessionTotals.count, namedTotalLimit))
    }

    /// "4h 10m focus · goal met · 3 sessions", or "5h 40m focus · 3h 59m
    /// towards 4h goal · 4 sessions" when the goal was missed: the goal counts
    /// only focus with hands-on use, so a day can hold more focus than its goal
    /// and still miss it, and "goal missed" beside the larger figure read as a
    /// fault. The goal part is left out when there is no goal.
    static func figuresLine(focused: TimeInterval, sessions: Int, goal: TimeInterval,
                            goalCredit: TimeInterval) -> String {
        var parts = ["\(DurationText.compact(focused)) focus"]
        if goal > 0 {
            parts.append(goalCredit >= goal ? "goal met"
                         : "\(DurationText.compact(goalCredit)) towards \(DurationText.compact(goal)) goal")
        }
        parts.append(counted(sessions, "session"))
        return parts.joined(separator: " · ")
    }
}
