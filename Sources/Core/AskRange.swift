import Foundation

/// The periods Ask Daybook can look up: one of the named ranges, each the
/// period History draws under the same name, or a calendar day, month or year
/// the model gives as an ISO date (`2026-10-03`, `2026-08`, `2025`). The model
/// names a period; the dates are read here, so a question about August is
/// answered from August rather than from whichever named range is nearest,
/// and 31 February is refused rather than rolled over into March.
enum AskRange: Equatable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case last30Days
    case thisYear
    case lastYear
    case allTime
    case day(year: Int, month: Int, day: Int)
    case month(year: Int, month: Int)
    case year(Int)

    /// The named ranges, in the order the model is offered them.
    static let allCases: [AskRange] = [.today, .yesterday, .thisWeek, .lastWeek, .thisMonth, .lastMonth,
                                       .last30Days, .thisYear, .lastYear, .allTime]

    /// What the model sends and the Used line shows: the range's name, or its ISO date.
    var rawValue: String {
        switch self {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .thisWeek: return "this week"
        case .lastWeek: return "last week"
        case .thisMonth: return "this month"
        case .lastMonth: return "last month"
        case .last30Days: return "last 30 days"
        case .thisYear: return "this year"
        case .lastYear: return "last year"
        case .allTime: return "all time"
        case let .day(year, month, day): return String(format: "%04d-%02d-%02d", year, month, day)
        case let .month(year, month): return String(format: "%04d-%02d", year, month)
        case let .year(year): return String(format: "%04d", year)
        }
    }

    /// A range's name or an ISO date; nil for anything else, and for a date
    /// the calendar does not have.
    init?(rawValue: String) {
        let text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let named = Self.allCases.first(where: { $0.rawValue == text }) {
            self = named
            return
        }
        guard let match = text.wholeMatch(of: #/(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?/#),
              let year = Int(match.1), year > 0 else { return nil }
        guard let monthText = match.2 else {
            self = .year(year)
            return
        }
        guard let month = Int(monthText), (1...12).contains(month) else { return nil }
        guard let dayText = match.3 else {
            self = .month(year: year, month: month)
            return
        }
        guard let day = Int(dayText), Self.noon(year, month, day) != nil else { return nil }
        self = .day(year: year, month: month, day: day)
    }

    /// The model's text for a period: a name or an ISO date, as
    /// `init?(rawValue:)` reads them, or a weekday, a month or a day of a
    /// month as a question says it in English, which means the latest one up
    /// to today. On Saturday 10 October 2026, "monday" is 5 October,
    /// "saturday" today, "aug" August 2026, "november" November 2025 and
    /// "3 october" or "october 3rd" the 3rd; a four-digit year names its own.
    /// The model is asked to pass dates this way because, left to work them
    /// out, it compared October for "September than August" and looked up
    /// 28 February for 31 February (probe, 2026-10-10). Nil for a date the
    /// calendar lacks, so 31 February is refused.
    static func resolving(_ raw: String, now: Date, calendar: Calendar) -> AskRange? {
        if let range = AskRange(rawValue: raw) { return range }
        let words = raw.lowercased().replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace).map(String.init)
        let today = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let year = today.year, let month = today.month, let date = today.day, let weekday = today.weekday
        else { return nil }
        if words.count == 1, let index = named(words[0], in: weekdayNames) {
            let back = (weekday - (index + 1) + 7) % 7
            guard let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)) else {
                return nil
            }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
            return .day(year: y, month: m, day: d)
        }
        // A month, with a day of it and a year in any order.
        guard (1...3).contains(words.count),
              let at = words.firstIndex(where: { named($0, in: monthNames) != nil }),
              let index = named(words[at], in: monthNames) else { return nil }
        let wanted = index + 1
        var day: Int?
        var given: Int?
        for (position, word) in words.enumerated() where position != at {
            let digits = ["st", "nd", "rd", "th"].first { word.hasSuffix($0) }.map { _ in String(word.dropLast(2)) } ?? word
            guard let number = Int(digits) else { return nil }
            if digits.count == 4, given == nil, number > 0 {
                given = number
            } else if digits.count <= 2, day == nil, (1...31).contains(number) {
                day = number
            } else {
                return nil
            }
        }
        guard let day else { return .month(year: given ?? (wanted <= month ? year : year - 1), month: wanted) }
        var y = given ?? ((wanted, day) <= (month, date) ? year : year - 1)
        // 29 February with no year is the latest there was, not this year's, which may not exist.
        while given == nil, wanted == 2, day == 29, noon(y, wanted, day) == nil, y > year - 8 { y -= 1 }
        return noon(y, wanted, day) == nil ? nil : .day(year: y, month: wanted, day: day)
    }

    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august",
                                     "september", "october", "november", "december"]

    /// The name a word begins, at three letters or more: "aug", "sept", "tues".
    private static func named(_ word: String, in names: [String]) -> Int? {
        word.count >= 3 ? names.firstIndex { $0.hasPrefix(word) } : nil
    }

    /// Half-open `[start, end)`. Pass `Calendar.forPeriods`, so a week starts
    /// on Monday and a month is the Gregorian month wherever the Mac is set.
    func interval(now: Date, firstDay: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        // Some zones skip midnight, so a day there begins at 01:00 and adding
        // days to it keeps the hour: each edge is brought back to a day's start.
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        func period(_ component: Calendar.Component, offset: Int) -> DateInterval {
            let anchor = calendar.date(byAdding: component, value: offset, to: today) ?? today
            return calendar.dateInterval(of: component, for: anchor) ?? DateInterval(start: today, end: tomorrow)
        }
        // Noon, so a zone whose clocks change at midnight still lands inside the day.
        func named(_ component: Calendar.Component, _ year: Int, _ month: Int, _ day: Int) -> DateInterval {
            let anchor = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? today
            return calendar.dateInterval(of: component, for: anchor) ?? DateInterval(start: today, end: tomorrow)
        }
        switch self {
        case .today: return period(.day, offset: 0)
        case .yesterday: return period(.day, offset: -1)
        case .thisWeek: return period(.weekOfYear, offset: 0)
        case .lastWeek: return period(.weekOfYear, offset: -1)
        case .thisMonth: return period(.month, offset: 0)
        case .lastMonth: return period(.month, offset: -1)
        case .thisYear: return period(.year, offset: 0)
        case .lastYear: return period(.year, offset: -1)
        case .last30Days:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: today) ?? today)
            return DateInterval(start: start, end: tomorrow)
        case .allTime:
            return DateInterval(start: min(calendar.startOfDay(for: firstDay), today), end: tomorrow)
        case let .day(year, month, day): return named(.day, year, month, day)
        case let .month(year, month): return named(.month, year, month, 1)
        case let .year(year): return named(.year, year, 1, 1)
        }
    }

    /// The History level that holds this range's breakdown; `nil` when none does.
    var level: HistoryLevel? {
        switch self {
        case .today, .yesterday, .day: return .day
        case .thisWeek, .lastWeek: return .week
        case .thisMonth, .lastMonth, .last30Days, .month: return .month
        case .thisYear, .lastYear, .year: return .year
        case .allTime: return nil
        }
    }

    /// Whether the range is one calendar day, which has no best day of its own.
    var isOneDay: Bool { level == .day }

    /// The range as a name: `this week`, `Sat 3 Oct 2026`, `August 2026`, `2025`.
    var title: String {
        switch self {
        case let .day(year, month, day): return Self.text("EEE d MMM yyyy", year, month, day)
        case let .month(year, month): return Self.text("MMMM yyyy", year, month, 1)
        case let .year(year): return String(year)
        default: return rawValue
        }
    }

    /// How a sentence places something in this range.
    var inPhrase: String {
        switch self {
        case .last30Days: return "in the last 30 days"
        case .allTime: return "in all your history"
        case .day: return "on \(title)"
        case .month, .year: return "in \(title)"
        default: return rawValue
        }
    }

    /// Noon on the date in Gregorian UTC, or nil when the calendar has no
    /// such date: the day of the week of a date is the same in every zone.
    private static func noon(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            return nil
        }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day ? date : nil
    }

    private static func text(_ format: String, _ year: Int, _ month: Int, _ day: Int) -> String {
        guard let date = noon(year, month, day), let utc = TimeZone(identifier: "UTC") else { return "" }
        return DateFormats.australian(format, in: utc).string(from: date)
    }
}
