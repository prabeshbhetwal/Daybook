import Foundation

/// A calendar day, kept as its three numbers so it means the same day in any
/// zone and survives a daylight-saving change.
struct CalendarDay: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year ?? 0
        month = c.month ?? 1
        day = c.day ?? 1
    }

    static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// The day's first moment (some zones skip midnight).
    func start(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// What one weekday does: follow the rhythm, use another preset, or stay quiet.
/// Coded as one string; a string from a newer build reads as `.usual`.
enum BreakDayPlan: Hashable, Codable {
    case usual
    case preset(BreakPreset)
    case off

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        switch raw {
        case "off": self = .off
        default: self = BreakPreset(rawValue: raw).map { .preset($0) } ?? .usual
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .usual: try container.encode("usual")
        case .off: try container.encode("off")
        case .preset(let preset): try container.encode(preset.rawValue)
        }
    }
}

/// The four ways to set a plan aside for a while. Declaration order is the
/// order that settles a tie between spans of equal length.
enum BreakOverrideKind: String, Codable, CaseIterable {
    case today, week, month, range
}

struct BreakOverride: Codable, Equatable {
    let kind: BreakOverrideKind
    let first: CalendarDay
    let last: CalendarDay
    let plan: BreakDayPlan
}

/// The hours reminders may speak. `fromMinute > toMinute` runs overnight and
/// equal ends mean the whole day.
struct WorkingHours: Codable, Equatable {
    var fromMinute: Int
    var toMinute: Int

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if fromMinute < toMinute { return minute >= fromMinute && minute < toMinute }
        if fromMinute > toMinute { return minute >= fromMinute || minute < toMinute }
        return true
    }
}

/// Decodes to nil instead of throwing, so one unreadable element of an array
/// from another build does not lose the rest.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// Which rhythm applies on which day: a main rhythm, a plan per weekday, a few
/// overrides and the hours reminders may speak.
struct BreakSchedule: Codable, Equatable {
    var rhythm: BreakPreset = .steady
    var custom = CustomRhythm()
    /// Sunday first: the index is `calendar.component(.weekday) - 1`.
    var weekdays: [BreakDayPlan] = Array(repeating: .usual, count: 7)
    var overrides: [BreakOverride] = []
    var workingHours: WorkingHours? = nil

    init() {}

    /// Reads whatever is there: a missing key is its default, an unknown
    /// rhythm is Steady, a weekdays array of the wrong length is the default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rhythm = (try? c.decodeIfPresent(BreakPreset.self, forKey: .rhythm)) ?? .steady
        custom = (try? c.decodeIfPresent(CustomRhythm.self, forKey: .custom)) ?? CustomRhythm()
        if let plans = try? c.decodeIfPresent([BreakDayPlan].self, forKey: .weekdays), plans.count == 7 {
            weekdays = plans
        }
        overrides = ((try? c.decodeIfPresent([Lossy<BreakOverride>].self, forKey: .overrides)) ?? nil)?
            .compactMap(\.value) ?? []
        workingHours = (try? c.decodeIfPresent(WorkingHours.self, forKey: .workingHours)) ?? nil
    }

    /// The override covering `date`: the narrowest span, then kind order.
    /// An override whose plan is `.usual` changes nothing and is ignored.
    func override(on date: Date, calendar: Calendar) -> BreakOverride? {
        let today = CalendarDay(date, calendar: calendar)
        // Counted by day number, not by the time between two midnights: a day
        // that skips midnight starts at 01:00 and would fall a day short.
        func dayNumber(_ day: CalendarDay) -> Int? {
            day.start(in: calendar).flatMap { calendar.ordinality(of: .day, in: .era, for: $0) }
        }
        func length(_ o: BreakOverride) -> Int {
            guard let from = dayNumber(o.first), let to = dayNumber(o.last) else { return Int.max }
            return to - from + 1
        }
        func order(_ o: BreakOverride) -> Int { BreakOverrideKind.allCases.firstIndex(of: o.kind) ?? 0 }
        return overrides
            .filter { $0.plan != .usual && $0.first <= today && today <= $0.last }
            .min { (length($0), order($0)) < (length($1), order($1)) }
    }

    /// The preset in force on `date` (nil is "No reminders") and the kind of
    /// override that decided it, if one did.
    func preset(on date: Date, calendar: Calendar) -> (preset: BreakPreset?, override: BreakOverrideKind?) {
        if let o = override(on: date, calendar: calendar) { return (resolve(o.plan), o.kind) }
        let index = calendar.component(.weekday, from: date) - 1
        return (resolve(weekdays.indices.contains(index) ? weekdays[index] : .usual), nil)
    }

    private func resolve(_ plan: BreakDayPlan) -> BreakPreset? {
        switch plan {
        case .usual: return rhythm
        case .preset(let preset): return preset
        case .off: return nil
        }
    }

    /// Replaces that kind's override with `plan` over the days around `date`
    /// (the week or month containing it; for `.range`, `date` through `end`,
    /// either way round). `.usual` removes it.
    mutating func setOverride(_ kind: BreakOverrideKind, plan: BreakDayPlan, covering date: Date,
                              through end: Date? = nil, calendar: Calendar) {
        overrides.removeAll { $0.kind == kind }
        guard plan != .usual else { return }
        let day = CalendarDay(date, calendar: calendar)
        func whole(_ unit: Calendar.Component) -> (CalendarDay, CalendarDay) {
            guard let span = calendar.dateInterval(of: unit, for: date) else { return (day, day) }
            return (CalendarDay(span.start, calendar: calendar),
                    CalendarDay(span.end.addingTimeInterval(-1), calendar: calendar))
        }
        let (first, last): (CalendarDay, CalendarDay)
        switch kind {
        case .today: (first, last) = (day, day)
        case .week: (first, last) = whole(.weekOfYear)
        case .month: (first, last) = whole(.month)
        case .range:
            let other = end.map { CalendarDay($0, calendar: calendar) } ?? day
            (first, last) = (min(day, other), max(day, other))
        }
        overrides.append(BreakOverride(kind: kind, first: first, last: last, plan: plan))
    }
}
