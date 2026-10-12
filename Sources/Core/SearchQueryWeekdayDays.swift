import Foundation

extension SearchPeriod {
    var isLoneWeekday: Bool {
        if case .weekday = self { return true }
        return false
    }
}

extension SearchGrammar {
    /// One weekday as one day: "last Tuesday" or "this past Tuesday", the
    /// latest before today, so a week ago on a Tuesday; "this Tuesday", this
    /// week's, which may be still to come; "the Tuesday before last", the one
    /// before last Tuesday; and
    /// "Tuesday" or "on Tuesday", the latest up to today, today included,
    /// whose day waits for the other periods (`settle(weekday:fallback:within:)`).
    /// Three letters name the weekday after "last" or "this" and before
    /// "before last" ("last tue"). Alone only the whole name does, so "wed" and
    /// "sat" stay words, and "tues", like "Tuesdays", is every Tuesday.
    func weekdayDay(_ t: SearchTokens, _ i: Int) -> SearchMatch? {
        guard let word = t.word(i) else { return nil }
        func found(_ count: Int, _ name: String, _ interval: DateInterval?) -> SearchMatch? {
            interval.map { SearchMatch(count: count, effect: .period(.relative($0, name: name))) }
        }
        if word == "last" || word == "this", let day = Self.weekday(t.word(i + 1), abbreviated: true) {
            let name = (word == "last" ? "Last " : "This ") + Self.title(day)
            return found(2, name, wholeDay(word == "last" ? -lastBack(day) : thisWeek(day)))
        }
        // "this past Tuesday", like "this past weekend", is last Tuesday.
        if word == "this", t.word(i + 1) == "past", let day = Self.weekday(t.word(i + 2), abbreviated: true) {
            return found(3, "This past " + Self.title(day), wholeDay(-lastBack(day)))
        }
        let at = word == "the" || word == "on" ? i + 1 : i
        if let day = Self.weekday(t.word(at), abbreviated: true), t.word(at + 1) == "before", t.word(at + 2) == "last" {
            return found(at + 3 - i, Self.title(day) + " before last", wholeDay(-lastBack(day) - 7))
        }
        guard word != "the", let day = Self.weekday(t.word(at), abbreviated: false),
              let fallback = wholeDay(-back(to: day, from: now)) else { return nil }
        return SearchMatch(count: at + 1 - i, effect: .period(.weekday(day, fallback: fallback)))
    }

    /// A lone weekday's day and chip: the latest such day up to today inside
    /// `others`, the overlap of the text's other periods, so "Monday 5 October"
    /// and "Tuesday last week" mean the day they name. With no other period,
    /// or none holding such a day, it is `fallback`, the latest up to today.
    func settle(weekday day: Int, fallback: DateInterval, within others: DateInterval?) -> (interval: DateInterval, label: String) {
        var chosen = fallback
        if let others, let last = calendar.date(byAdding: .second, value: -1, to: others.end) {
            let newest = min(now, last)
            if let inside = wholeDay(-back(to: day, from: newest), from: newest), others.holds(inside.start) {
                chosen = inside
            }
        }
        return (chosen, "\(Self.title(day)) · \(datesLabel(chosen))")
    }

    /// The weekday a word names, 1 = Sunday: its whole name, or with
    /// `abbreviated` its first three letters or more; "Tuesday's" is Tuesday.
    private static func weekday(_ typed: String?, abbreviated: Bool) -> Int? {
        guard let typed else { return nil }
        let word = typed.hasSuffix("'s") || typed.hasSuffix("’s") ? String(typed.dropLast(2)) : typed
        if let index = weekdayNames.firstIndex(of: word) { return index + 1 }
        guard abbreviated, word.count >= 3, let index = weekdayNames.firstIndex(where: { $0.hasPrefix(word) }) else { return nil }
        return index + 1
    }

    private static func title(_ day: Int) -> String { weekdayNames[day - 1].capitalized }

    /// How many days back from `date`'s day the latest weekday `day` is: 0 when it is that day.
    private func back(to day: Int, from date: Date) -> Int {
        (calendar.component(.weekday, from: date) - day + 7) % 7
    }

    /// How many days back last `day` is: a week on that weekday itself.
    private func lastBack(_ day: Int) -> Int {
        let days = back(to: day, from: now)
        return days == 0 ? 7 : days
    }

    /// How many days from today this week's `day` is; negative when it has passed.
    private func thisWeek(_ day: Int) -> Int {
        let first = calendar.firstWeekday
        return (day - first + 7) % 7 - (calendar.component(.weekday, from: now) - first + 7) % 7
    }

    /// The whole day `offset` days from `date`'s day, earlier when negative.
    /// Counted from noon, which every day has, so a clock change at midnight
    /// cannot move it into the day before or after.
    private func wholeDay(_ offset: Int, from date: Date? = nil) -> DateInterval? {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date ?? now),
              let moved = calendar.date(byAdding: .day, value: offset, to: noon) else { return nil }
        return calendar.dateInterval(of: .day, for: moved)
    }
}
