import Foundation

/// Previous Day and Next Day: one day either way from the day being read.
/// Story is always today and History reads every other day, so a step always
/// lands in History. `SessionStore.stepDay` moves the dashboard's day offset;
/// only a self-check calls it, and Story never leaves offset 0, so it is not
/// used here.
enum HistoryDayStep {
    /// The start of the day `delta` days from `current`, or nil when that day
    /// is after today or before the first day anything was recorded (nil when
    /// nothing has been): History has nothing to open there.
    static func target(from current: Date, by delta: Int, earliest: Date?, today: Date,
                       calendar: Calendar) -> Date? {
        guard let earliest,
              let moved = calendar.date(byAdding: .day, value: delta,
                                        to: calendar.startOfDay(for: current)) else { return nil }
        let day = calendar.startOfDay(for: moved)
        guard day >= calendar.startOfDay(for: earliest), day <= calendar.startOfDay(for: today) else { return nil }
        return day
    }
}

extension MainWindowModel {
    /// The day Previous Day (-1) or Next Day (+1) opens, or nil when it cannot.
    /// It steps from the day open in History, else from today: in Story that
    /// is today's page, and in History with no day open it is the top of the
    /// list, which begins at today.
    func historyDayTarget(by delta: Int) -> Date? {
        guard let store else { return nil }
        let calendar = SessionStore.historyCalendar
        let today = calendar.startOfDay(for: store.now())
        let current = workspace == .history ? (reviewSelectedDate ?? today) : today
        return HistoryDayStep.target(from: current, by: delta, earliest: store.earliestSelectableDay,
                                     today: today, calendar: calendar)
    }

    /// Shows History on the day `delta` days away. Nothing happens when
    /// there is no such day.
    func stepHistoryDay(by delta: Int) {
        guard let day = historyDayTarget(by: delta) else { return }
        open(tab: .review)
        openHistory(day: day)
    }
}
