import Foundation

/// What a review note is written from. Any History day, week or month becomes
/// `NoteFacts` through figures the app already computes: a day's from its
/// Story projection, a period's from History's summary and its days'
/// projections. Nothing here is stored; the questions below (current, Wrap
/// up, Yesterday) decide where a note is offered.
extension SessionStore {
    var appleIntelligenceEnabled: Bool { engine.store.useAppleIntelligence }

    /// The day containing `date`, spanned as History's tree spans its day
    /// rows, so a note keyed by this place is the note for that row.
    func notePlace(forDayContaining date: Date) -> HistoryPlace {
        HistoryPlace(level: .day, span: HistoryTreeBuilder.period(.day, containing: date, calendar: periodCalendar))
    }

    /// Whether the place holds the present, so its figures are still moving.
    func noteIsCurrent(_ place: HistoryPlace) -> Bool {
        place.span.holds(now())
    }

    /// The facts for a day, week or month; nil for a year, and for a place
    /// with no sessions. Week and month facts read History's index, which is
    /// current only while History is open, so they are requested from History
    /// views alone.
    func noteFacts(for place: HistoryPlace) -> NoteFacts? {
        switch place.level {
        case .day: return dayNoteFacts(place)
        case .week, .month: return periodNoteFacts(place)
        case .year: return nil
        }
    }

    /// "1h 30m focus · goal missed · 1 session". A day's figures come from
    /// its own projection, which is always current; History's index is only
    /// refreshed while History is open, and the Yesterday notice shows this
    /// line over the Story. Other places read History's summary, goal left out.
    func noteFiguresLine(for place: HistoryPlace) -> String {
        guard place.level == .day else {
            let summary = historySummary(for: place)
            return NoteFacts.figuresLine(focused: summary.focused, sessions: summary.sessions, goal: 0, goalCredit: 0)
        }
        let day = storyDayProjection(on: place.start, calendar: periodCalendar)
        return NoteFacts.figuresLine(focused: day.focused, sessions: day.focusSessionCount,
                                     goal: engine.store.dailyGoal, goalCredit: day.goalCredit)
    }

    // MARK: - Where a note is offered

    /// Today has a session and none is running, so "Wrap up today" can be
    /// offered.
    var wrapUpOffered: Bool {
        let sessions = storyDayProjection(on: now(), calendar: periodCalendar).focusSessions
        return !sessions.isEmpty && !sessions.contains { $0.isRunning }
    }

    /// Yesterday, when it had a session and the notice has not been closed
    /// for it.
    func yesterdayNotePlace() -> HistoryPlace? {
        guard let place = yesterdayPlace(), engine.store.yesterdayNoteDismissedDay != place.start,
              noteFacts(for: place) != nil else { return nil }
        return place
    }

    /// Closes the Yesterday notice for the day it is showing.
    func dismissYesterdayNote() {
        guard let place = yesterdayPlace() else { return }
        engine.store.yesterdayNoteDismissedDay = place.start
        objectWillChange.send()
    }

    private func yesterdayPlace() -> HistoryPlace? {
        periodCalendar.date(byAdding: .day, value: -1, to: now()).map { notePlace(forDayContaining: $0) }
    }

    // MARK: - Facts

    private func dayNoteFacts(_ place: HistoryPlace) -> NoteFacts? {
        let calendar = periodCalendar
        let day = storyDayProjection(on: place.start, calendar: calendar)
        let sessions = day.focusSessions
        guard !sessions.isEmpty else { return nil }
        // The day before is compared whole, however far through today is.
        let before = calendar.date(byAdding: .day, value: -1, to: place.start)
            .map { storyDayProjection(on: $0, calendar: calendar).focused } ?? 0
        return NoteFacts.day(NoteDayInput(date: place.start, isCurrent: noteIsCurrent(place), sessions: sessions,
                                          apps: day.apps, focused: day.focused, goal: engine.store.dailyGoal,
                                          goalCredit: day.goalCredit, previousFocused: before),
                             calendar: calendar)
    }

    private func periodNoteFacts(_ place: HistoryPlace) -> NoteFacts? {
        let calendar = periodCalendar
        let summary = historySummary(for: place)
        guard summary.sessions > 0 else { return nil }
        let goal = engine.store.dailyGoal
        let today = calendar.startOfDay(for: now())
        var worked: [String: TimeInterval] = [:]
        var goalMetDays = 0
        var cursor = calendar.startOfDay(for: place.span.start)
        while cursor < place.span.end, cursor <= today {
            let day = storyDayProjection(on: cursor, calendar: calendar)
            for session in day.focusSessions { worked[session.name, default: 0] += session.worked }
            if goal > 0, day.goalCredit >= goal { goalMetDays += 1 }
            cursor = HistoryTreeBuilder.dayAfter(cursor, calendar: calendar)
        }
        let totals = worked.map { (name: $0.key, worked: $0.value) }
            .sorted { $0.worked != $1.worked ? $0.worked > $1.worked : $0.name < $1.name }
        let current = noteIsCurrent(place)
        return NoteFacts.period(NotePeriodInput(span: place.span, level: place.level, isCurrent: current,
                                                summary: summary, sessionTotals: totals, goal: goal,
                                                goalMetDays: goalMetDays,
                                                previousFocused: previousFocused(before: place, isCurrent: current)),
                                calendar: calendar)
    }

    /// The focus of the same-level period just before, or 0 for no
    /// comparison. A period still running, or cut short by a month's edge or
    /// the start of the record, is not weighed against a whole one.
    private func previousFocused(before place: HistoryPlace, isCurrent: Bool) -> TimeInterval {
        let calendar = periodCalendar
        let whole = HistoryTreeBuilder.period(place.level, containing: place.start, calendar: calendar)
        guard !isCurrent, whole == place.span,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: place.start) else { return 0 }
        let span = HistoryTreeBuilder.period(place.level, containing: dayBefore, calendar: calendar)
        return historySummary(for: HistoryPlace(level: place.level, span: span)).focused
    }
}

private extension StoryDayProjection {
    /// The focus sessions of the day; breaks left out.
    var focusSessions: [DaySession] {
        sessions.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
    }
}
