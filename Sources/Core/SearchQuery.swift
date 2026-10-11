import Foundation

/// One phrase the search box understood: what kind, where it sits in the
/// typed text and what its chip says.
struct SearchPhrase: Equatable {
    enum Kind: Equatable { case period, weekdays, length, app, category }
    let kind: Kind
    let range: Range<String.Index>   // in the parsed text
    let label: String                // chip text
}

/// What a search box's text asks for: filters read from its phrases, and the
/// words left over for the word search.
struct ParsedSearch: Equatable {
    var span: DateInterval?          // intersection of every period phrase
    var noOverlap = false            // periods given but disjoint; span is then nil and nothing matches
    var weekdays: Set<Int>?          // Calendar weekday numbers, 1 = Sunday … 7 = Saturday
    var minLength: TimeInterval?
    var maxLength: TimeInterval?
    var appBundleID: String?
    var workType: WorkType?
    var leftover: String             // every unread word, in order, single-spaced, quotes kept
    var phrases: [SearchPhrase]      // in text order
}

/// Reads dates, recurring weekdays, lengths and exact app or category names
/// out of free text (spec §2). Pure: it never reads the clock or the settings.
enum SearchQuery {
    /// Phrases are taken left to right, the longest one that begins at a word
    /// first. Text in double quotes is never read. `apps` maps a bundle ID to
    /// its display name; an app or category is read only when typed with its
    /// own leading capital, and only the first of each is taken.
    static func parse(_ text: String, now: Date, calendar: Calendar, apps: [String: String],
                      categories: [WorkType]) -> ParsedSearch {
        let tokens = SearchTokens(text)
        let grammar = SearchGrammar(now: now, calendar: calendar, apps: apps, categories: categories)
        var found: [(first: Int, match: SearchMatch)] = []
        var leftover: [String] = []
        var i = 0
        while i < tokens.items.count {
            if let match = grammar.match(tokens, at: i, excluding: found.map { $0.match.effect.kind }) {
                found.append((i, match))
                i += match.count
            } else {
                leftover.append(tokens.items[i].text)
                i += 1
            }
        }

        var result = ParsedSearch(leftover: leftover.joined(separator: " "), phrases: [])
        // The periods that name their year pin the year of a month or day typed without one.
        let pinned = overlap(found.compactMap { grammar.fixedInterval($0.match) })
        var spans: [DateInterval] = []
        for (first, match) in found {
            var label = match.label
            switch match.effect {
            case let .period(period):
                let settled = grammar.settle(period, within: pinned)
                spans.append(settled.interval)
                label = settled.label
            case let .weekdays(days):
                result.weekdays = (result.weekdays ?? []).union(days)
            case let .length(low, high):
                result.minLength = [result.minLength, low].compactMap { $0 }.max()
                result.maxLength = [result.maxLength, high].compactMap { $0 }.min()
            case let .app(bundleID):
                result.appBundleID = bundleID
            case let .category(type):
                result.workType = type
            }
            let last = tokens.items[first + match.count - 1]
            result.phrases.append(SearchPhrase(kind: match.effect.kind,
                                               range: tokens.items[first].range.lowerBound..<last.range.upperBound,
                                               label: label))
        }
        if !spans.isEmpty {
            result.span = overlap(spans)
            result.noOverlap = result.span == nil
        }
        return result
    }

    /// The part every interval shares, half-open; nil when there are none or two only touch or are apart.
    fileprivate static func overlap(_ intervals: [DateInterval]) -> DateInterval? {
        guard let first = intervals.first else { return nil }
        return intervals.dropFirst().reduce(first as DateInterval?) { merged, next in
            guard let a = merged, a.holds(next.start) || next.holds(a.start) else { return nil }
            return DateInterval(start: max(a.start, next.start), end: min(a.end, next.end))
        }
    }
}

extension SearchGrammar {
    /// A period whose dates do not depend on the other periods.
    func fixedInterval(_ match: SearchMatch) -> DateInterval? {
        guard case let .period(period) = match.effect else { return nil }
        switch period {
        case let .relative(interval, _): return interval
        case let .named(range): return range.interval(now: now, firstDay: now, calendar: calendar)
        case .yearless: return nil
        }
    }

    /// A period's dates and chip. A month or day typed without a year takes it
    /// from `pinned`, the periods that give theirs: the latest occurrence, not
    /// in the future, that meets them. With none it is the latest not in the future.
    func settle(_ period: SearchPeriod, within pinned: DateInterval?) -> (interval: DateInterval, label: String) {
        switch period {
        case let .relative(interval, name):
            return (interval, "\(name) · \(datesLabel(interval))")
        case let .named(range):
            return (range.interval(now: now, firstDay: now, calendar: calendar), range.title)
        case let .yearless(words, fallback):
            var chosen = fallback
            if let pinned, let last = calendar.date(byAdding: .second, value: -1, to: pinned.end) {
                let newest = min(calendar.component(.year, from: now), calendar.component(.year, from: last))
                for year in stride(from: newest, through: calendar.component(.year, from: pinned.start), by: -1) {
                    guard let candidate = AskRange.resolving("\(words) \(year)", now: now, calendar: calendar) else { continue }
                    let interval = candidate.interval(now: now, firstDay: now, calendar: calendar)
                    if interval.start <= now, interval.holds(pinned.start) || pinned.holds(interval.start) {
                        chosen = candidate
                        break
                    }
                }
            }
            return (chosen.interval(now: now, firstDay: now, calendar: calendar), chosen.title)
        }
    }

    /// `Sat 10 Oct`, `6–12 Oct`, `28 Sep – 4 Oct`; the year follows when the
    /// span is not in this year, on both ends when it crosses New Year.
    func datesLabel(_ interval: DateInterval) -> String {
        let last = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.start
        func text(_ format: String, _ date: Date) -> String { DateFormats.australian(format, in: calendar.timeZone).string(from: date) }
        let (from, to) = (calendar.dateComponents([.year, .month, .day], from: interval.start),
                          calendar.dateComponents([.year, .month, .day], from: last))
        if from.year != to.year { return "\(text("d MMM yyyy", interval.start)) – \(text("d MMM yyyy", last))" }
        let dates: String
        if from.month == to.month, from.day == to.day {
            dates = text("EEE d MMM", interval.start)
        } else if from.month == to.month {
            dates = "\(text("d", interval.start))–\(text("d MMM", last))"
        } else {
            dates = "\(text("d MMM", interval.start)) – \(text("d MMM", last))"
        }
        return to.year == calendar.component(.year, from: now) ? dates : "\(dates) \(text("yyyy", last))"
    }
}
