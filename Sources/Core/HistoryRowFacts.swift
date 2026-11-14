import Foundation

/// One thing that stands out about a History row, as data. Its wording is
/// the surface's, which owns the duration formatting.
enum HistoryRowFact: Equatable {
    case recordDay(day: Date, focused: TimeInterval)
    case biggest
    /// Against the whole period before; signed and never 0.
    case change(percent: Int, previous: HistoryPlace)
    case started(day: Date)
}

struct HistoryRowFacts: Equatable {
    /// At most two, in the order of `HistoryRowFact`'s cases.
    let facts: [HistoryRowFact]
    /// Whole days after today in the period still running; nil at 0.
    let daysLeft: Int?

    static let none = HistoryRowFacts(facts: [], daysLeft: nil)
}

/// What the whole record says about its days: the figures a row's facts
/// are judged against.
struct HistoryRecord: Equatable {
    let longestDay: Date?
    let longestFocus: TimeInterval
    let focusedDays: Int

    /// The earliest day wins a tie, whatever order the index is walked in.
    static func of(byDate: [Date: HistoryDay]) -> HistoryRecord {
        var longest: (day: Date, focused: TimeInterval)?
        var focusedDays = 0
        for (day, row) in byDate where row.focused > 0 {
            focusedDays += 1
            let beats = longest.map { row.focused > $0.focused || (row.focused == $0.focused && day < $0.day) } ?? true
            if beats { longest = (day, row.focused) }
        }
        return HistoryRecord(longestDay: longest?.day, longestFocus: longest?.focused ?? 0, focusedDays: focusedDays)
    }

    /// The record as built from the day index, brought up to today's live
    /// figures. `cachedToday` is today as that index held it. Today is the
    /// latest day, so only a longer one takes the longest-day place.
    func patched(live: HistoryDay?, cachedToday: HistoryDay?, calendar: Calendar) -> HistoryRecord {
        guard let live, live != cachedToday else { return self }
        let days = focusedDays - ((cachedToday?.focused ?? 0) > 0 ? 1 : 0) + (live.focused > 0 ? 1 : 0)
        let longer = live.focused > longestFocus
        return HistoryRecord(longestDay: longer ? calendar.startOfDay(for: live.date) : longestDay,
                             longestFocus: longer ? live.focused : longestFocus, focusedDays: days)
    }
}

enum HistoryRowFactsBuilder {
    /// Fewer focused days than this have no longest day worth naming.
    static let recordDayMinimumDays = 14
    /// A rounded change smaller than this is left unsaid.
    static let changeMinimumPercent = 10
    static let biggestMinimumRows = 3

    /// What stands out about each of `rows`, sibling rows at one level,
    /// newest first. Keyed by `HistoryPlace.id`; day rows get `.none`.
    static func facts(rows: [HistoryRow], top: HistoryTop, record: HistoryRecord,
                      calendar: Calendar) -> [String: HistoryRowFacts] {
        let biggest = biggestRow(in: rows)
        var result: [String: HistoryRowFacts] = [:]
        for (index, row) in rows.enumerated() {
            guard row.place.level != .day else { result[row.id] = HistoryRowFacts.none; continue }
            var facts: [HistoryRowFact] = []
            if record.focusedDays >= recordDayMinimumDays, let day = record.longestDay, row.place.span.holds(day) {
                facts.append(.recordDay(day: day, focused: record.longestFocus))
            }
            if row.id == biggest { facts.append(.biggest) }
            if let change = change(of: row, from: rows.indices.contains(index + 1) ? rows[index + 1] : nil,
                                   top: top, calendar: calendar) {
                facts.append(change)
            }
            if row.place.span.holds(top.firstDay) { facts.append(.started(day: top.firstDay)) }
            result[row.id] = HistoryRowFacts(facts: Array(facts.prefix(2)),
                                             daysLeft: daysLeft(of: row, top: top, calendar: calendar))
        }
        return result
    }

    /// The one row with more focus than any other, once there are enough
    /// rows to make that worth saying.
    private static func biggestRow(in rows: [HistoryRow]) -> String? {
        guard rows.count >= biggestMinimumRows, let most = rows.map(\.focused).max(), most > 0 else { return nil }
        let leaders = rows.filter { $0.focused == most }
        return leaders.count == 1 ? leaders[0].id : nil
    }

    /// A whole period against the whole one before it, once it is over.
    private static func change(of row: HistoryRow, from previous: HistoryRow?, top: HistoryTop,
                               calendar: Calendar) -> HistoryRowFact? {
        guard let previous, previous.focused > 0, !row.place.span.holds(top.today),
              isWhole(row.place, calendar: calendar), isWhole(previous.place, calendar: calendar) else { return nil }
        let percent = Int(((row.focused - previous.focused) / previous.focused * 100).rounded())
        return abs(percent) >= changeMinimumPercent ? .change(percent: percent, previous: previous.place) : nil
    }

    /// Whether the place is a whole calendar period, not one clipped to the
    /// record or to today.
    private static func isWhole(_ place: HistoryPlace, calendar: Calendar) -> Bool {
        place.span == HistoryTreeBuilder.period(place.level, containing: place.start, calendar: calendar)
    }

    /// The days after today in the row's whole period, not its clipped span,
    /// while the row holds today.
    private static func daysLeft(of row: HistoryRow, top: HistoryTop, calendar: Calendar) -> Int? {
        guard row.place.span.holds(top.today) else { return nil }
        let end = HistoryTreeBuilder.period(row.place.level, containing: row.place.start, calendar: calendar).end
        var left = 0
        var day = HistoryTreeBuilder.dayAfter(top.today, calendar: calendar)
        while day < end {
            left += 1
            day = HistoryTreeBuilder.dayAfter(day, calendar: calendar)
        }
        return left > 0 ? left : nil
    }
}
