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

/// "1h more focus than the week before", or nil with no period before or a
/// difference under a minute. `fell` is true for "less".
private func comparison(_ focused: TimeInterval, with previous: TimeInterval,
                        before noun: String) -> (text: String, fell: Bool)? {
    guard previous > 0 else { return nil }
    let difference = focused - previous
    guard abs(difference) >= 60 else { return nil }
    return ("\(DurationText.compact(abs(difference))) \(difference > 0 ? "more" : "less") focus than the \(noun) before",
            difference < 0)
}

/// What a session is called: the name it was given, or its kind's name when it
/// was left blank, as the Story titles it.
private func title(_ session: DaySession) -> String {
    session.workType.sessionTitle(named: session.name)
}

/// The most sessions a day's facts name; the rest are counted.
private let namedSessionLimit = 8

/// The sessions a week's or month's facts name, by time spent. The probe's
/// week notes totalled "other sessions" when there were more.
private let namedTotalLimit = 3

extension NoteFacts {

    /// The facts for one day, or nil when it has no sessions.
    static func day(_ input: NoteDayInput, calendar: Calendar) -> NoteFacts? {
        guard !input.sessions.isEmpty else { return nil }
        let sessions = input.sessions.sorted { $0.start < $1.start }
        let topApps = input.apps.filter { $0.total > 0 }

        var lines = ["Day: " + longDate(input.date, calendar) + (input.isCurrent ? " (so far)" : ""),
                     "Focus: \(DurationText.compact(input.focused)) over \(counted(input.sessionCount, "session"))"]
        if input.goal > 0 {
            lines.append("Daily goal: \(DurationText.compact(input.goal)), met: \(input.goalCredit >= input.goal ? "yes" : "no")")
        }
        lines.append("Sessions in order: " + sessionList(sessions, calendar: calendar))
        if !topApps.isEmpty {
            lines.append("Top apps: " + topApps.prefix(3).map { "\($0.appName) \(DurationText.compact($0.total))" }
                .joined(separator: ", "))
        }

        var observations: [String] = []
        var patternOnly: Set<String> = []
        if let longest = input.longestStretch, longest.worked >= 600 {
            let from = carriesOver(longest.start, calendar) ? "before midnight" : timeOfDay(longest.start, calendar)
            observations.append("Longest stretch: \(DurationText.compact(longest.worked)) in \(longest.name), from \(from)")
        }
        observations.append(carriesOver(sessions[0].start, calendar)
            ? "Focus carried on past midnight with \(title(sessions[0]))"
            : "Focus began at \(timeOfDay(sessions[0].start, calendar)) with \(title(sessions[0]))")
        if let top = topApps.first, top.share > 0.4 {
            observations.append("Most app time was in \(top.appName) (\(DurationText.compact(top.total)))")
        }
        if let change = comparison(input.focused, with: input.previousFocused, before: "day") {
            observations.append(change.text)
            // A tip built on a drop in focus reads as a scolding; the pattern may still name it.
            if change.fell { patternOnly.insert(change.text) }
        }
        let stretchCount = sessions.reduce(0) { $0 + $1.stretches }
        if stretchCount > input.sessionCount {
            observations.append("\(counted(input.sessionCount, "session")) ran as \(counted(stretchCount, "stretch", plural: "stretches"))")
        }
        return NoteFacts(kind: .day, lines: lines, observations: Array(observations.prefix(4)), patternOnly: patternOnly)
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
        if !input.sessionTotals.isEmpty {
            // "name: duration" joined by semicolons, as the day's list is: a name may hold a comma or end in a number.
            lines.append("Most time went to: " + input.sessionTotals.prefix(namedTotalLimit)
                .map { "\($0.name): \(DurationText.compact($0.worked))" }.joined(separator: "; "))
        }

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
        if let change = comparison(summary.focused, with: input.previousFocused, before: noun) {
            observations.append(change.text)
        }
        if input.goal > 0 {
            observations.append("Goal met on \(input.goalMetDays) of \(summary.focusedDays) days with focus")
        }
        if let first = input.sessionTotals.first, summary.focused > 0, first.worked / summary.focused > 0.4 {
            observations.append("\(first.name) took \(DurationText.compact(first.worked)) of the \(noun)")
        }
        return NoteFacts(kind: .period, lines: lines, observations: Array(observations.prefix(5)))
    }

    /// "4h 10m focus · goal met · 3 sessions"; the goal part is left out when
    /// there is no goal.
    static func figuresLine(focused: TimeInterval, sessions: Int, goal: TimeInterval,
                            goalCredit: TimeInterval) -> String {
        var parts = ["\(DurationText.compact(focused)) focus"]
        if goal > 0 { parts.append(goalCredit >= goal ? "goal met" : "goal missed") }
        parts.append(counted(sessions, "session"))
        return parts.joined(separator: " · ")
    }

    /// `Parser at 9:13 am, 1h 30m; …` in start order, `Parser from before
    /// midnight, 1h` for one carried over from the night before. Past the
    /// limit, the sessions with the most time are named and the rest counted.
    private static func sessionList(_ sessions: [DaySession], calendar: Calendar) -> String {
        let kept = Set(sessions.indices.sorted {
            sessions[$0].worked != sessions[$1].worked ? sessions[$0].worked > sessions[$1].worked : $0 < $1
        }.prefix(namedSessionLimit))
        var entries = sessions.indices.filter(kept.contains).map { index in
            let session = sessions[index]
            let began = carriesOver(session.start, calendar) ? "from before midnight"
                : "at " + timeOfDay(session.start, calendar)
            return "\(title(session)) \(began), " + DurationText.compact(session.worked)
        }
        if sessions.count > namedSessionLimit { entries.append("and \(sessions.count - namedSessionLimit) more") }
        return entries.joined(separator: "; ")
    }
}
