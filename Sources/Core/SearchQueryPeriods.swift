import Foundation

extension SearchGrammar {
    /// Periods counted from today: "today", "last week", "past fortnight",
    /// "the weekend before last", "3 weeks ago" or "back", "last 7 days".
    func relative(_ t: SearchTokens, _ i: Int) -> SearchMatch? {
        guard let word = t.word(i) else { return nil }
        func found(_ count: Int, _ interval: DateInterval?) -> SearchMatch? {
            guard let interval else { return nil }
            var words = t.phrase(i, count)
            if words.hasPrefix("the ") { words.removeFirst(4) }
            return SearchMatch(count: count, effect: .period(.relative(interval, name: words.prefix(1).uppercased() + words.dropFirst())))
        }
        func named(_ range: AskRange) -> DateInterval { range.interval(now: now, firstDay: now, calendar: calendar) }
        /// The unit word at `at`, after "last" or "past".
        func recent(_ at: Int) -> SearchMatch? {
            switch t.word(at) {
            case "fortnight": return found(at + 1 - i, rolling(days: 14))
            case "weekend": return found(at + 1 - i, weekend(weeksAgo: 1))
            default: return nil
            }
        }
        let ranges: [String: (AskRange, AskRange)] = ["week": (.thisWeek, .lastWeek), "month": (.thisMonth, .lastMonth),
                                                      "year": (.thisYear, .lastYear)]
        switch word {
        case "today": return found(1, named(.today))
        case "yesterday": return found(1, named(.yesterday))
        case "this", "last":
            if let unit = t.word(i + 1), let pair = ranges[unit] { return found(2, named(word == "this" ? pair.0 : pair.1)) }
            if word == "this", t.word(i + 1) == "past" { return recent(i + 2) }
            if word == "last", let hit = recent(i + 1) { return hit }
            guard word == "last", let number = t.count(i + 1), let unit = t.word(i + 1 + number.used),
                  ["day", "days", "week", "weeks"].contains(unit) else { return nil }
            return found(2 + number.used, rolling(days: number.value * (unit.hasPrefix("week") ? 7 : 1)))
        case "past":
            return recent(i + 1)
        case "the", "week", "month", "fortnight", "weekend":
            let at = word == "the" ? i + 1 : i
            if word == "the", t.word(at) == "past" { return recent(at + 1) }
            guard let unit = t.word(at), t.word(at + 1) == "before", t.word(at + 2) == "last" else { return nil }
            let before: DateInterval?
            switch unit {
            case "week": before = shifted(.weekOfYear, by: -2)
            case "month": before = shifted(.month, by: -2)
            case "fortnight": before = rolling(days: 14, back: 14)
            case "weekend": before = weekend(weeksAgo: 2)
            default: return nil
            }
            return found(at + 3 - i, before)
        default:
            guard let number = t.count(i, article: true), let unit = t.word(i + number.used),
                  let tail = t.word(i + number.used + 1), tail == "ago" || tail == "back" else { return nil }
            let component: [String: (Calendar.Component, Int)] = [
                "day": (.day, 1), "days": (.day, 1), "week": (.weekOfYear, 1), "weeks": (.weekOfYear, 1),
                "fortnight": (.weekOfYear, 2), "fortnights": (.weekOfYear, 2), "month": (.month, 1), "months": (.month, 1)]
            guard let (which, weeks) = component[unit] else { return nil }
            return found(number.used + 2, shifted(which, by: -number.value * weeks))
        }
    }

    /// The whole `component` that holds today moved by `offset`.
    func shifted(_ component: Calendar.Component, by offset: Int) -> DateInterval? {
        guard let anchor = calendar.date(byAdding: component, value: offset, to: calendar.startOfDay(for: now)) else { return nil }
        return calendar.dateInterval(of: component, for: anchor)
    }

    /// `days` days ending with today's midnight-to-midnight, or, with `back`,
    /// ending that many days earlier.
    func rolling(days: Int, back: Int = 0) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: 1 - days - back, to: today),
              let after = calendar.date(byAdding: .day, value: 1 - back, to: today) else { return nil }
        return DateInterval(start: calendar.startOfDay(for: from), end: calendar.startOfDay(for: after))
    }

    /// Saturday midnight to Monday midnight of the week `weeks` before this one.
    func weekend(weeksAgo weeks: Int) -> DateInterval? {
        guard let week = shifted(.weekOfYear, by: -weeks),
              let saturday = calendar.date(byAdding: .day, value: 5, to: week.start) else { return nil }
        return DateInterval(start: calendar.startOfDay(for: saturday), end: week.end)
    }
}
