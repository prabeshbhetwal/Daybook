import Foundation

/// Decides which places an answer rests on, in the order a reader can check
/// the answer by: the places it names, in the order it names them, then each
/// lookup's own place that it did not name.
enum AskSourcePicker {
    static let shownAtOnce = 5

    /// What makes two targets one place. A period is its level and first day,
    /// whatever span it was drawn with: a lookup lists the whole calendar week
    /// while History's row for it may stop at today or at the first day recorded.
    private static func place(_ target: AskLink.Target) -> AskLink.Target {
        guard case .period(let period) = target else { return target }
        return .period(HistoryPlace(level: period.level, span: DateInterval(start: period.start, duration: 0)))
    }

    /// `lookups`: each lookup's links, its anchor first, in the order the lookups were made.
    /// Every place appears once, at its first place; the caller shows `shownAtOnce` rows.
    static func sources(answer: String, lookups: [[AskLink]], calendar: Calendar, now: Date) -> [AskSource] {
        var seen = Set<AskLink.Target>()
        let links = lookups.joined().filter { seen.insert(place($0.target)).inserted }
        let reader = AnswerReader(answer, calendar: calendar, now: now)
        let sessions = reader.sessionsToName(among: links)
        let named = links.enumerated().compactMap { index, link -> (index: Int, link: AskLink, mention: Range<Int>)? in
            if case .session = link.target, !sessions.contains(link.target) { return nil }
            return reader.mention(of: link).map { (index, link, $0) }
        }.sorted { ($0.mention.lowerBound, $0.index) < ($1.mention.lowerBound, $1.index) }

        var sources = named.map { AskSource(link: $0.link, mention: $0.mention) }
        var listed = Set(named.map { place($0.link.target) })
        // Each lookup's anchor, its first link, when nothing listed is that place.
        // A lookup whose anchor is listed adds nothing: its other links are not
        // what the answer rests on.
        for anchor in lookups.compactMap(\.first) {
            guard listed.insert(place(anchor.target)).inserted else { continue }
            sources.append(AskSource(link: anchor, mention: nil))
        }
        return sources
    }
}

/// Every date, year and week an answer writes, found once. Matching runs on
/// the answer as written, so every range is a character offset into it.
private struct AnswerReader {
    private struct Day {
        let range: Range<Int>
        let day: Int
        let month: Int
        let year: Int?

        func matches(_ date: Date, in calendar: Calendar) -> Bool {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return c.day == day && c.month == month && (year == nil || c.year == year)
        }
    }

    private struct Month {
        let range: Range<Int>
        let month: Int
        let year: Int?
    }

    private enum Pattern {
        static let month = #"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?"#
            + #"|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#
        static let weekday = #"(?:(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?"#
            + #"|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b,?\s+)?"#
        static let year = #"(?:,?\s+((?:19|20)\d{2})\b)?"#
        static let ordinal = "(?:st|nd|rd|th)?"

        /// `15th of Sep`, `Tuesday, 15 September 2026`, `September 15`. Groups: day, month, month, day, year.
        static let day = regex(#"\b\#(weekday)(?:(\d{1,2})\#(ordinal)(?:\s+of)?\s+\#(month)"#
                               + #"|\#(month)\s+(\d{1,2})\#(ordinal)\b)\#(year)"#)
        static let monthAlone = regex(#"\b\#(month)\#(year)"#)
        static let relativeDay = regex(#"\b(today|yesterday)\b"#)
        static let bareYear = regex(#"\b((?:19|20)\d{2})\b"#)
        static let weekOf = regex(#"\bweek\s+of\s+"#)
        static let relativeWeek = regex(#"\b(this|last)\s+week\b"#)

        private static func regex(_ pattern: String) -> NSRegularExpression? {
            try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private let text: String
    private let characters: [Character]
    private let calendar: Calendar
    private let days: [Day]
    private let months: [Month]
    private let years: [(range: Range<Int>, year: Int)]
    private let weekOfs: [Range<Int>]
    private let relativeWeeks: [(range: Range<Int>, isThis: Bool)]
    private let thisWeek: DateInterval?
    private let lastWeek: DateInterval?

    init(_ text: String, calendar: Calendar, now: Date) {
        self.text = text
        self.calendar = calendar
        characters = Array(text)

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let written = Self.scan(Pattern.day, text).compactMap { match -> Day? in
            guard let day = (match.groups[0] ?? match.groups[3]).flatMap({ Int($0) }),
                  let month = Self.monthNumber(match.groups[1] ?? match.groups[2]) else { return nil }
            return Day(range: match.range, day: day, month: month, year: match.groups[4].flatMap { Int($0) })
        }
        let relative = Self.scan(Pattern.relativeDay, text).map { match -> Day in
            let c = calendar.dateComponents([.year, .month, .day],
                                            from: match.groups[0]?.lowercased() == "yesterday" ? yesterday : today)
            return Day(range: match.range, day: c.day ?? 0, month: c.month ?? 0, year: c.year)
        }
        let days = (written + relative).sorted { $0.range.lowerBound < $1.range.lowerBound }
        // A month inside a day ("15 Sep") is part of that date, not a month named.
        // A bare "may" is the verb unless it is capitalised: "You may do well".
        let months = Self.scan(Pattern.monthAlone, text).compactMap { match -> Month? in
            guard !days.contains(where: { $0.range.contains(match.range.lowerBound) }),
                  let month = Self.monthNumber(match.groups[0]) else { return nil }
            let year = match.groups[1].flatMap { Int($0) }
            if month == 5, year == nil, match.groups[0]?.first?.isUppercase != true { return nil }
            return Month(range: match.range, month: month, year: year)
        }
        // A year inside a date ("15 Sep 2026", "September 2026") is part of it.
        let dated = days.map(\.range) + months.map(\.range)
        years = Self.scan(Pattern.bareYear, text).compactMap { match -> (range: Range<Int>, year: Int)? in
            guard !dated.contains(where: { $0.contains(match.range.lowerBound) }),
                  let year = match.groups[0].flatMap({ Int($0) }) else { return nil }
            return (match.range, year)
        }
        self.days = days
        self.months = months
        weekOfs = Self.scan(Pattern.weekOf, text).map(\.range)
        relativeWeeks = Self.scan(Pattern.relativeWeek, text).map { ($0.range, $0.groups[0]?.lowercased() == "this") }
        thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        lastWeek = thisWeek.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.start) }
            .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
    }

    /// Where the answer first names this link's place; nil when it does not.
    /// A history link is never named.
    func mention(of link: AskLink) -> Range<Int>? {
        switch link.target {
        case .history: return nil
        case .day(let date): return mention(ofDay: date)
        case .session: return link.sessionName.flatMap { mention(ofName: $0) }
        case .awards: return link.names.compactMap { mention(ofName: $0) }.min { $0.lowerBound < $1.lowerBound }
        case .period(let place):
            switch place.level {
            case .day: return mention(ofDay: place.start)
            case .week: return mention(ofWeek: place.span)
            case .month:
                let c = calendar.dateComponents([.year, .month], from: place.start)
                return months.first { $0.month == c.month && ($0.year == nil || $0.year == c.year) }?.range
            case .year:
                let year = calendar.component(.year, from: place.start)
                return years.first { $0.year == year }?.range
            }
        }
    }

    /// Sessions that share a name are told apart by the day the answer names;
    /// when it names none of their days, the newest is the one meant.
    func sessionsToName(among links: [AskLink]) -> Set<AskLink.Target> {
        let sessions = links.compactMap { link -> (link: AskLink, day: Date)? in
            if case .session(_, let day) = link.target { return (link, day) }
            return nil
        }
        var kept = Set<AskLink.Target>()
        for group in Dictionary(grouping: sessions, by: { SearchWords.fold($0.link.sessionName ?? "") }).values {
            let onNamedDays = group.filter { mention(ofDay: $0.day) != nil }
            let newest = group.dropFirst().reduce(group[0]) { $1.day > $0.day ? $1 : $0 }
            kept.formUnion((onNamedDays.isEmpty ? [newest] : onNamedDays).map(\.link.target))
        }
        return kept
    }

    private func mention(ofDay date: Date) -> Range<Int>? {
        days.first { $0.matches(date, in: calendar) }?.range
    }

    /// By its two end days together (one link across both when only a dash
    /// joins them), by "week of" its first day, or as this week or last week.
    /// Whichever comes first in the answer.
    private func mention(ofWeek span: DateInterval) -> Range<Int>? {
        var found: [Range<Int>] = []
        let last = calendar.date(byAdding: .day, value: -1, to: span.end) ?? span.start
        if !calendar.isDate(last, inSameDayAs: span.start),
           let first = mention(ofDay: span.start), let end = mention(ofDay: last) {
            let joined = end.lowerBound >= first.upperBound
                && !characters[first.upperBound..<end.lowerBound].contains { $0.isLetter || $0.isNumber }
            found.append(joined ? first.lowerBound..<end.upperBound : first)
        }
        for prefix in weekOfs {
            if let day = days.first(where: { $0.range.lowerBound == prefix.upperBound && $0.matches(span.start, in: calendar) }) {
                found.append(prefix.lowerBound..<day.range.upperBound)
                break
            }
        }
        if let relative = relativeWeeks.first(where: { ($0.isThis ? thisWeek : lastWeek)?.holds(span.start) == true }) {
            found.append(relative.range)
        }
        return found.min { $0.lowerBound < $1.lowerBound }
    }

    /// The name as whole words, ignoring case and accents.
    private func mention(ofName name: String) -> Range<Int>? {
        guard !name.isEmpty else { return nil }
        var from = text.startIndex
        while let hit = text.range(of: name, options: [.caseInsensitive, .diacriticInsensitive],
                                   range: from..<text.endIndex), !hit.isEmpty {
            let found = Self.offsets(hit, in: text)
            let wordBefore = found.lowerBound > 0 && isWordCharacter(characters[found.lowerBound - 1])
            let wordAfter = found.upperBound < characters.count && isWordCharacter(characters[found.upperBound])
            if !wordBefore && !wordAfter { return found }
            from = hit.upperBound
        }
        return nil
    }

    private func isWordCharacter(_ character: Character) -> Bool { character.isLetter || character.isNumber }

    private static func monthNumber(_ word: String?) -> Int? {
        word.flatMap { monthNames.firstIndex(of: $0.prefix(3).lowercased()) }.map { $0 + 1 }
    }

    private static func offsets(_ range: Range<String.Index>, in text: String) -> Range<Int> {
        text.distance(from: text.startIndex, to: range.lowerBound)
            ..< text.distance(from: text.startIndex, to: range.upperBound)
    }

    /// Each match as character offsets, with its capture groups' text (nil for a group that did not take part).
    private static func scan(_ regex: NSRegularExpression?, _ text: String) -> [(range: Range<Int>, groups: [String?])] {
        regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let groups = (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
            return (offsets(range, in: text), groups)
        } ?? []
    }
}
