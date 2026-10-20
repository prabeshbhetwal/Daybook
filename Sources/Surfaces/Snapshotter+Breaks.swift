import Foundation

/// The Settings — Breaks card is drawn with every optional row open: Custom's
/// numbers with a long break, a day with no reminders, a range of dates and
/// working hours. A row that only shows in some state can only clip there.
extension Snapshotter {
    /// Noon on Wednesday 21 Oct 2026 in the host's zone, so the dates on the
    /// card read the same on every run and in every zone.
    static let settingsNow = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))
        ?? Date(timeIntervalSince1970: 1_792_584_000)

    static func breaksSchedule(calendar: Calendar) -> BreakSchedule {
        func day(_ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)) ?? settingsNow
        }
        var schedule = BreakSchedule()
        schedule.rhythm = .custom
        schedule.custom = CustomRhythm(workMinutes: 45, breakMinutes: 10, longEvery: 3, longMinutes: 20)
        schedule.weekdays[0] = .off
        schedule.weekdays[6] = .preset(.flow)
        schedule.workingHours = WorkingHours(fromMinute: 9 * 60, toMinute: 17 * 60 + 30)
        schedule.setOverride(.range, plan: .preset(.deepWork), covering: day(22), through: day(24),
                             calendar: calendar)
        return schedule
    }
}
