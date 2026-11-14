import Foundation

/// The words on and about a row. Kept apart from the view so the checks can
/// read them without rendering.
enum HistoryRowText {
    static func title(_ place: HistoryPlace, today: Date, calendar: Calendar) -> String {
        switch place.level {
        case .year:
            return DateFormats.australian("yyyy", in: calendar.timeZone).string(from: place.start)
        case .month:
            return DateFormats.australian("MMMM", in: calendar.timeZone).string(from: place.start)
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: place.span.end) ?? place.start
            if calendar.isDate(place.start, inSameDayAs: last) {
                return DateFormats.australian("EEE d MMM", in: calendar.timeZone).string(from: place.start)
            }
            let sameMonth = calendar.isDate(place.start, equalTo: last, toGranularity: .month)
            let first = DateFormats.australian(sameMonth ? "d" : "d MMM", in: calendar.timeZone).string(from: place.start)
            return "\(first) – \(DateFormats.australian("d MMM", in: calendar.timeZone).string(from: last))"
        case .day:
            return calendar.isDate(place.start, inSameDayAs: today) ? "Today"
                : DateFormats.australian("EEE d MMM", in: calendar.timeZone).string(from: place.start)
        }
    }

    /// Today is still being recorded, so its figure is the total so far.
    private static func isToday(_ row: HistoryRow, today: Date) -> Bool {
        row.place.level == .day && Calendar.current.isDate(row.place.start, inSameDayAs: today)
    }

    /// `20h 40m · 14 days`, `2h 10m · 3 sessions`, `25m so far · 1 session`,
    /// or why there is no figure.
    static func facts(_ row: HistoryRow, today: Date) -> String {
        if row.isAppUseOnly { return "Recorded app use only · \(Tokens.duration(row.tracked))" }
        if row.isEmpty {
            return isToday(row, today: today) ? "nothing recorded yet today" : "nothing recorded"
        }
        if row.place.level == .day {
            let noun = row.sessions == 1 ? "1 session" : "\(row.sessions) sessions"
            let soFar = isToday(row, today: today) ? " so far" : ""
            return row.focused > 0 ? "\(Tokens.duration(row.focused))\(soFar) · \(noun)" : noun + soFar
        }
        let days = row.focusedDays == 1 ? "1 day" : "\(row.focusedDays) days"
        return row.focused > 0 ? "\(Tokens.duration(row.focused)) · \(days)" : "no focus recorded"
    }

    /// `September 2026, 1 hour 45 minutes across 3 days, month, level 2, collapsed`.
    static func spoken(_ row: HistoryRow, today: Date, isOpen: Bool, depth: Int, calendar: Calendar) -> String {
        var name = title(row.place, today: today, calendar: calendar)
        if row.place.level == .month { name += " " + DateFormats.australian("yyyy", in: calendar.timeZone).string(from: row.place.start) }
        let figure: String
        if row.isAppUseOnly {
            figure = "recorded app use only, \(Tokens.spent(row.tracked))"
        } else if depth == 0, row.place.level != .day {
            // A first-view period says its sentence, with the figure in words.
            let rest = sentence(row, today: today).rest.dropLast()
            figure = row.focused > 0 ? "\(Tokens.spent(row.focused)) \(rest)" : rest.lowercased()
        } else if row.isEmpty {
            figure = facts(row, today: today)
        } else if row.place.level == .day {
            let noun = row.sessions == 1 ? "1 session" : "\(row.sessions) sessions"
            let soFar = isToday(row, today: today) ? " so far" : ""
            figure = row.focused > 0 ? "\(Tokens.spent(row.focused))\(soFar), \(noun)" : noun + soFar
        } else {
            let days = row.focusedDays == 1 ? "1 day" : "\(row.focusedDays) days"
            figure = row.focused > 0 ? "\(Tokens.spent(row.focused)) across \(days)" : "no focus recorded"
        }
        var parts = [name, figure, row.place.level.spokenName, "level \(depth + 1)"]
        if !row.isEmpty { parts.append(isOpen ? "expanded" : "collapsed") }
        return parts.joined(separator: ", ")
    }

    static func headline(top: HistoryTop, summary: HistorySummary, calendar: Calendar)
        -> (eyebrow: String, sentence: String, facts: [String]) {
        let eyebrow: String
        switch top.place?.level {
        case .year: eyebrow = DateFormats.australian("yyyy", in: calendar.timeZone).string(from: top.span.start)
        case .month: eyebrow = DateFormats.australian("MMMM yyyy", in: calendar.timeZone).string(from: top.span.start)
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: top.span.end) ?? top.span.start
            // A week of one recorded day is that day; a week across two months names both.
            let sameMonth = calendar.isDate(top.span.start, equalTo: last, toGranularity: .month)
            eyebrow = calendar.isDate(top.span.start, inSameDayAs: last)
                ? DateFormats.australian("EEEE d MMMM", in: calendar.timeZone).string(from: top.span.start)
                : "\(DateFormats.australian(sameMonth ? "d" : "d MMMM", in: calendar.timeZone).string(from: top.span.start)) – "
                    + DateFormats.australian("d MMMM", in: calendar.timeZone).string(from: last)
        case .day, .none:
            eyebrow = "On record since \(DateFormats.australian("d MMMM yyyy", in: calendar.timeZone).string(from: top.firstDay))"
        }
        let days = summary.focusedDays == 1 ? "1 day" : "\(summary.focusedDays) days"
        let sentence = summary.focused > 0
            ? "You focused \(Tokens.duration(summary.focused)) across \(days)."
            : "Nothing focused here yet."
        var facts: [String] = []
        if summary.focusedDays > 1 {
            facts.append("\(Tokens.duration(summary.focused / Double(summary.focusedDays))) per focused day")
        }
        // The best month or day is the rail's to say; the headline says how
        // steady the record has been. The top period holds the whole record.
        let elapsed = (calendar.dateComponents([.day], from: calendar.startOfDay(for: top.firstDay),
                                               to: calendar.startOfDay(for: top.today)).day ?? 0) + 1
        if summary.focusedDays > 0, elapsed > 1 {
            facts.append(summary.focusedDays >= elapsed ? "focus on every day since you started"
                         : "focus on \(summary.focusedDays) of the \(elapsed) days since you started")
        }
        return (eyebrow, sentence, facts)
    }
}

/// The words of a first-view period row: its gutter label, its sentence and
/// the line under it.
extension HistoryRowText {
    /// `Nov`, `2026`, `9 to 15`: the period's short name beside the spine.
    static func gutter(_ place: HistoryPlace, calendar: Calendar) -> String {
        let format = { (pattern: String, date: Date) in
            DateFormats.australian(pattern, in: calendar.timeZone).string(from: date)
        }
        switch place.level {
        case .year: return format("yyyy", place.start)
        case .month: return format("MMM", place.start)
        case .week:
            // A first-view week lies inside one month, so its days name it.
            let last = calendar.date(byAdding: .day, value: -1, to: place.span.end) ?? place.start
            let first = format("d", place.start)
            return calendar.isDate(place.start, inSameDayAs: last) ? first : "\(first) to \(format("d", last))"
        case .day: return format("EEE", place.start)
        }
    }

    /// `61h 10m` and `across 9 days so far.`; with no figure, why there is none.
    static func sentence(_ row: HistoryRow, today: Date) -> (figure: String?, rest: String) {
        if row.isAppUseOnly { return (nil, facts(row, today: today)) }
        if row.isEmpty { return (nil, "Nothing recorded.") }
        guard row.focused > 0 else { return (nil, "Nothing focused.") }
        let days = row.focusedDays == 1 ? "one day" : "\(row.focusedDays) days"
        let soFar = row.place.span.holds(today) ? " so far" : ""
        return (Tokens.duration(row.focused), "across \(days)\(soFar).")
    }

    /// The line under the sentence, said only from `facts`: nil when nothing
    /// stands out and no days are left.
    static func detail(_ facts: HistoryRowFacts, row: HistoryRow, calendar: Calendar) -> String? {
        let format = { (pattern: String, date: Date) in
            DateFormats.australian(pattern, in: calendar.timeZone).string(from: date)
        }
        var sentences: [String] = []
        for (index, fact) in facts.facts.enumerated() {
            switch fact {
            case let .recordDay(day, focused):
                sentences.append("\(format("EEE d MMM", day)) was your longest day yet, at \(Tokens.duration(focused)).")
            case .biggest:
                sentences.append("Your biggest \(row.place.level.spokenName) so far.")
            case let .change(percent, previous):
                // Only a day's title reads today, and a day has no facts.
                let change = "\(percent > 0 ? "up" : "down") \(abs(percent))% on "
                    + "\(title(previous, today: .distantPast, calendar: calendar))."
                if index > 0, facts.facts[index - 1] == .biggest {
                    sentences[sentences.count - 1] = "\(sentences[sentences.count - 1].dropLast()), \(change)"
                } else {
                    sentences.append(change.prefix(1).uppercased() + change.dropFirst())
                }
            case let .started(day):
                sentences.append("You started on \(format("d MMM", day)).")
            }
        }
        if let left = facts.daysLeft { sentences.append(left == 1 ? "1 day left." : "\(left) days left.") }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
