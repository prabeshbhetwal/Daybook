import Foundation

/// A period as a search phrase gave it.
enum SearchPeriod {
    case relative(DateInterval, name: String)
    case named(AskRange)
    /// A month or day typed without its year: its year waits for the other
    /// periods in the text, and `fallback` is the latest one not in the future.
    case yearless(words: String, fallback: AskRange)
}

/// What one phrase asks for, and how many words it took.
struct SearchMatch {
    enum Effect {
        case period(SearchPeriod)
        case weekdays(Set<Int>)
        case length(min: TimeInterval?, max: TimeInterval?)
        case app(String)
        case category(WorkType)

        var kind: SearchPhrase.Kind {
            switch self {
            case .period: return .period
            case .weekdays: return .weekdays
            case .length: return .length
            case .app: return .app
            case .category: return .category
            }
        }
    }

    let count: Int
    let effect: Effect
    /// The chip's text. A period is labelled once the other periods are known.
    var label = ""
}

/// The phrases of spec §2, each read from the words at one position.
struct SearchGrammar {
    let now: Date
    let calendar: Calendar
    private let names: [Name]

    private struct Name {
        let words: [String]
        let initial: Character
        let label: String
        let effect: SearchMatch.Effect
    }

    private enum Part { case day, month, year }
    private static let dateForms: [[Part]] = [[.day, .month, .year], [.month, .day, .year], [.day, .month],
                                              [.month, .day], [.month, .year], [.month], [.year]]
    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let overWords = [["over"], ["longer", "than"], ["more", "than"], ["at", "least"]]
    private static let underWords = [["under"], ["shorter", "than"], ["less", "than"], ["at", "most"]]

    /// `apps` maps a bundle ID to its display name. Longer names are tried first.
    init(now: Date, calendar: Calendar, apps: [String: String], categories: [WorkType]) {
        self.now = now
        self.calendar = calendar
        let entries: [(label: String, effect: SearchMatch.Effect)] = apps.sorted { $0.key < $1.key }.map { ($0.value, .app($0.key)) }
            + categories.map { ($0.displayName, .category($0)) }
        let built: [Name] = entries.compactMap { entry in
            let words = entry.label.split(whereSeparator: \.isWhitespace).map { SearchToken.trimmed(String($0)).lowercased() }
            guard let initial = SearchToken.trimmed(entry.label).first, words.allSatisfy({ !$0.isEmpty }) else { return nil }
            return Name(words: words, initial: initial, label: entry.label, effect: entry.effect)
        }
        names = built.enumerated().sorted { ($0.element.words.count, $1.offset) > ($1.element.words.count, $0.offset) }.map(\.element)
    }

    /// The longest phrase that begins at word `i`, skipping a kind of name that is already taken.
    func match(_ t: SearchTokens, at i: Int, excluding taken: [SearchPhrase.Kind]) -> SearchMatch? {
        var best: SearchMatch?
        for found in [period(t, i), weekdays(t, i), length(t, i), name(t, i, excluding: taken)] {
            if let found, found.count > (best?.count ?? 0) { best = found }
        }
        return best
    }

    // MARK: Periods

    private func period(_ t: SearchTokens, _ i: Int) -> SearchMatch? {
        [relative(t, i), dated(t, i)].compactMap { $0 }.first
    }

    private func relative(_ t: SearchTokens, _ i: Int) -> SearchMatch? {
        guard let word = t.word(i) else { return nil }
        func found(_ count: Int, _ interval: DateInterval?) -> SearchMatch? {
            guard let interval else { return nil }
            var words = t.phrase(i, count)
            if words.hasPrefix("the ") { words.removeFirst(4) }
            return SearchMatch(count: count, effect: .period(.relative(interval, name: words.prefix(1).uppercased() + words.dropFirst())))
        }
        func named(_ range: AskRange) -> DateInterval { range.interval(now: now, firstDay: now, calendar: calendar) }
        switch word {
        case "today": return found(1, named(.today))
        case "yesterday": return found(1, named(.yesterday))
        case "this", "last":
            let ranges: [String: (AskRange, AskRange)] = ["week": (.thisWeek, .lastWeek), "month": (.thisMonth, .lastMonth),
                                                          "year": (.thisYear, .lastYear)]
            if let unit = t.word(i + 1), let pair = ranges[unit] { return found(2, named(word == "this" ? pair.0 : pair.1)) }
            guard word == "last", let number = t.count(i + 1), let unit = t.word(i + 1 + number.used),
                  ["day", "days", "week", "weeks"].contains(unit) else { return nil }
            return found(2 + number.used, rolling(days: number.value * (unit.hasPrefix("week") ? 7 : 1)))
        case "the", "week", "month":
            let at = word == "the" ? i + 1 : i
            guard let unit = t.word(at), unit == "week" || unit == "month", t.word(at + 1) == "before",
                  t.word(at + 2) == "last" else { return nil }
            return found(at + 3 - i, shifted(unit == "week" ? .weekOfYear : .month, by: -2))
        default:
            guard let number = t.count(i, article: true), let unit = t.word(i + number.used),
                  t.word(i + number.used + 1) == "ago" else { return nil }
            let component: [String: Calendar.Component] = ["day": .day, "days": .day, "week": .weekOfYear,
                                                           "weeks": .weekOfYear, "month": .month, "months": .month]
            guard let which = component[unit] else { return nil }
            return found(number.used + 2, shifted(which, by: -number.value))
        }
    }

    /// The whole `component` that holds today moved by `offset`.
    private func shifted(_ component: Calendar.Component, by offset: Int) -> DateInterval? {
        guard let anchor = calendar.date(byAdding: component, value: offset, to: calendar.startOfDay(for: now)) else { return nil }
        return calendar.dateInterval(of: component, for: anchor)
    }

    /// The last `days` days, ending with today's midnight-to-midnight.
    private func rolling(days: Int) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: 1 - days, to: today),
              let after = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        return DateInterval(start: calendar.startOfDay(for: from), end: calendar.startOfDay(for: after))
    }

    /// A month, a day and month, or a year, read by `AskRange.resolving`.
    private func dated(_ t: SearchTokens, _ i: Int) -> SearchMatch? {
        let parts = (0..<3).map { t.word(i + $0).flatMap(part) }
        for form in Self.dateForms where parts.starts(with: form.map { Optional($0) }) {
            let words = t.phrase(i, form.count)
            guard let range = AskRange.resolving(words, now: now, calendar: calendar) else { continue }
            let period: SearchPeriod = form.contains(.year) ? .named(range) : .yearless(words: words, fallback: range)
            return SearchMatch(count: form.count, effect: .period(period))
        }
        return nil
    }

    private func part(_ word: String) -> Part? {
        if word.count == 4, SearchTokens.isDigits(word) { return (1900...2100).contains(Int(word) ?? 0) ? .year : nil }
        let digits = ["st", "nd", "rd", "th"].contains { word.hasSuffix($0) } ? String(word.dropLast(2)) : word
        if digits.count <= 2, SearchTokens.isDigits(digits), (1...31).contains(Int(digits) ?? 0) { return .day }
        if word.count >= 3, word.allSatisfy(\.isLetter), case .month? = AskRange.resolving(word, now: now, calendar: calendar) {
            return .month
        }
        return nil
    }

    // MARK: Weekdays

    /// "Mondays", "on Mondays", "Mondays and Fridays", "weekends".
    private func weekdays(_ t: SearchTokens, _ i: Int) -> SearchMatch? {
        var j = t.word(i) == "on" ? i + 1 : i
        var days = Set<Int>()
        var labels: [String] = []
        while let item = Self.plural(t.word(j)) {
            days.formUnion(item.days)
            labels.append(item.name)
            j += 1
            let comma = t.items[j - 1].commaAfter
            let next = t.word(j) == "and" ? j + 1 : j
            guard comma || next > j, Self.plural(t.word(next)) != nil else { break }
            j = next
        }
        guard !labels.isEmpty else { return nil }
        return SearchMatch(count: j - i, effect: .weekdays(days), label: labels.joined(separator: ", "))
    }

    /// A plural weekday, or three letters of one and an "s": "mons", "tues".
    // ponytail: "thus" is a word, not Thursdays; the other abbreviations ("suns", "sats") read as plurals.
    private static func plural(_ word: String?) -> (days: Set<Int>, name: String)? {
        guard let word, word.hasSuffix("s") else { return nil }
        if word == "weekends" { return ([1, 7], "Weekends") }
        if word == "weekdays" { return ([2, 3, 4, 5, 6], "Weekdays") }
        let stem = String(word.dropLast())
        guard stem.count >= 3, word != "thus", let index = weekdayNames.firstIndex(where: { $0.hasPrefix(stem) }) else { return nil }
        return ([index + 1], weekdayNames[index].capitalized + "s")
    }

    // MARK: Lengths

    private func length(_ t: SearchTokens, _ i: Int) -> SearchMatch? {
        if t.word(i) == "between", let low = duration(t, i + 1), t.word(i + 1 + low.used) == "and",
           let high = duration(t, i + 2 + low.used) {
            let (lower, upper) = (Swift.min(low.seconds, high.seconds), Swift.max(low.seconds, high.seconds))
            return SearchMatch(count: 2 + low.used + high.used, effect: .length(min: lower, max: upper),
                               label: "\(DurationText.compact(lower))–\(DurationText.compact(upper))")
        }
        for (words, isLower) in Self.overWords.map({ ($0, true) }) + Self.underWords.map({ ($0, false) }) {
            guard words.indices.allSatisfy({ t.word(i + $0) == words[$0] }),
                  let found = duration(t, i + words.count) else { continue }
            let text = DurationText.compact(found.seconds)
            return SearchMatch(count: words.count + found.used,
                               effect: isLower ? .length(min: found.seconds, max: nil) : .length(min: nil, max: found.seconds),
                               label: (isLower ? "Over " : "Under ") + text)
        }
        return nil
    }

    /// "1h", "1 h", "90 min", "1h 30m", "1.5h", "an hour", "forty minutes".
    private func duration(_ t: SearchTokens, _ i: Int) -> (seconds: TimeInterval, used: Int)? {
        guard let first = component(t, i) else { return nil }
        var seconds = first.seconds
        var used = first.used
        if first.isHours, let more = component(t, i + used), !more.isHours {
            seconds += more.seconds
            used += more.used
        }
        return seconds > 0 && seconds <= 3_600_000 ? (seconds, used) : nil
    }

    private func component(_ t: SearchTokens, _ i: Int) -> (seconds: TimeInterval, used: Int, isHours: Bool)? {
        guard let word = t.word(i) else { return nil }
        if let joined = word.wholeMatch(of: #/(\d+(?:\.\d+)?)([a-z]+)/#), let amount = Double(joined.1),
           let unit = Self.unitSeconds(String(joined.2)) {
            return (amount * unit, 1, unit == 3_600)
        }
        var amount = 0.0
        var used = 1
        if word.wholeMatch(of: #/\d+(?:\.\d+)?/#) != nil, let number = Double(word) {
            amount = number
        } else if let number = t.count(i, article: true) {
            (amount, used) = (Double(number.value), number.used)
        } else {
            return nil
        }
        guard let unitWord = t.word(i + used), let unit = Self.unitSeconds(unitWord) else { return nil }
        return (amount * unit, used + 1, unit == 3_600)
    }

    private static func unitSeconds(_ unit: String) -> TimeInterval? {
        switch unit {
        case "h", "hr", "hrs", "hour", "hours": return 3_600
        case "m", "min", "mins", "minute", "minutes": return 60
        default: return nil
        }
    }

    // MARK: Names

    /// An app or category written as its name, with the name's own capital.
    private func name(_ t: SearchTokens, _ i: Int, excluding taken: [SearchPhrase.Kind]) -> SearchMatch? {
        guard t.word(i) != nil else { return nil }
        let entry = names.first { entry in
            !taken.contains(entry.effect.kind) && t.items[i].bare.first == entry.initial
                && entry.words.indices.allSatisfy { t.word(i + $0) == entry.words[$0] }
        }
        return entry.map { SearchMatch(count: $0.words.count, effect: $0.effect, label: $0.label) }
    }
}
