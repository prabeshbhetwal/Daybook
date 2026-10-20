import Foundation

/// The Breaks page's values. Every date the page shows or writes is worked
/// out here, from the model's clock and calendar, so a view never reads the
/// time and a check can hand in its own. The schedule itself lives in
/// `SettingsModel.breakSchedule`, whose writes reach the session store.
extension SettingsModel {
    private var calendar: Calendar { currentCalendar() }

    var breakRhythm: BreakPreset {
        get { breakSchedule.rhythm }
        set { breakSchedule.rhythm = newValue }
    }

    /// The Custom rhythm's numbers; a write is kept inside their ranges.
    var customRhythm: CustomRhythm {
        get { breakSchedule.custom }
        set { breakSchedule.custom = newValue.clamped() }
    }

    // MARK: - Weekday plan

    /// One plan per weekday, Sunday first.
    var breakWeekdayPlans: [BreakDayPlan] {
        get { breakSchedule.weekdays }
        set { breakSchedule.weekdays = newValue }
    }

    /// The indices of `breakWeekdayPlans` in the order the calendar's week
    /// runs, from its first weekday.
    var weekdayOrder: [Int] {
        let first = calendar.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }

    /// The name of the weekday at a `breakWeekdayPlans` index.
    func weekdayName(_ index: Int) -> String {
        let names = calendar.weekdaySymbols
        return names.indices.contains(index) ? names[index] : ""
    }

    // MARK: - Overrides

    var breakOverrides: [BreakOverride] { breakSchedule.overrides }

    /// The override of this kind that Settings shows: the one covering today.
    /// Dates also shows while it lies ahead, so a range set for next week can
    /// be seen and changed; it goes when its last day has passed.
    private func shownOverride(_ kind: BreakOverrideKind) -> BreakOverride? {
        let today = CalendarDay(currentDate(), calendar: calendar)
        return breakSchedule.overrides.first {
            $0.kind == kind && today <= $0.last && (kind == .range || $0.first <= today)
        }
    }

    /// What the row for `kind` shows: the weekday plan (`.usual`) unless an
    /// override of that kind is in force.
    func breakOverridePlan(_ kind: BreakOverrideKind) -> BreakDayPlan {
        shownOverride(kind)?.plan ?? .usual
    }

    /// Sets the row for `kind` around today: today, the week or month holding
    /// it, or `from` through `to` (today when left out) for Dates.
    func setBreakOverride(_ kind: BreakOverrideKind, plan: BreakDayPlan, from: Date? = nil, to: Date? = nil) {
        var schedule = breakSchedule
        schedule.setOverride(kind, plan: plan, covering: from ?? currentDate(), through: to, calendar: calendar)
        breakSchedule = schedule
    }

    /// Dates' first day; today when there is no range to show.
    var breakRangeFrom: Date {
        get { shownOverride(.range)?.first.start(in: calendar) ?? calendar.startOfDay(for: currentDate()) }
        set {
            guard let range = shownOverride(.range) else { return }
            // Moving From past To takes To along, so the range never flips.
            setBreakOverride(.range, plan: range.plan, from: newValue, to: max(breakRangeTo, newValue))
        }
    }

    /// Dates' last day; today when there is no range to show.
    var breakRangeTo: Date {
        get { shownOverride(.range)?.last.start(in: calendar) ?? calendar.startOfDay(for: currentDate()) }
        set {
            guard let range = shownOverride(.range) else { return }
            setBreakOverride(.range, plan: range.plan, from: min(breakRangeFrom, newValue), to: newValue)
        }
    }

    // MARK: - Working hours

    private static let defaultWorkingHours = WorkingHours(fromMinute: 8 * 60, toMinute: 18 * 60)

    /// On gives 08:00 to 18:00 until the times are changed.
    var workingHoursEnabled: Bool {
        get { breakSchedule.workingHours != nil }
        set { breakSchedule.workingHours = newValue ? (breakSchedule.workingHours ?? Self.defaultWorkingHours) : nil }
    }

    /// The window's start as a time today, for the time picker.
    var workingHoursFrom: Date {
        get { time(atMinute: (breakSchedule.workingHours ?? Self.defaultWorkingHours).fromMinute) }
        set { setWorkingHours { $0.fromMinute = minute(of: newValue) } }
    }

    /// The window's end as a time today, for the time picker.
    var workingHoursTo: Date {
        get { time(atMinute: (breakSchedule.workingHours ?? Self.defaultWorkingHours).toMinute) }
        set { setWorkingHours { $0.toMinute = minute(of: newValue) } }
    }

    private func setWorkingHours(_ change: (inout WorkingHours) -> Void) {
        var hours = breakSchedule.workingHours ?? Self.defaultWorkingHours
        change(&hours)
        breakSchedule.workingHours = hours
    }

    private func minute(of date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Today at that minute of the day. On the one day a year when the clocks
    /// skip that minute the picker shows the next one; the stored minute stays.
    private func time(atMinute minute: Int) -> Date {
        let clamped = min(max(minute, 0), 24 * 60 - 1)
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: currentDate())
            ?? currentDate()
    }
}
