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

    /// What a note on screen is checked against again: the session archive's
    /// and the session metadata's revisions, as `evidenceRevision` has them,
    /// and the daily goal, which a day's facts and the Yesterday figures line
    /// both state and weigh the day against. A rename, correction, deletion,
    /// edited note, a session stopping or a new goal moves one, and the facts
    /// may have changed with it. App use is left out on purpose: it moves every
    /// few seconds while you work, and a "Wrap up today" note just written
    /// would go back to its link. A few counters and no projection, so a view
    /// that redraws every second may take it.
    struct NoteEvidence: Hashable {
        let sessions: Int
        let metadata: Int
        let goal: TimeInterval
    }

    var noteEvidence: NoteEvidence {
        let revision = evidenceRevision
        return NoteEvidence(sessions: revision.sessions, metadata: revision.metadata, goal: engine.store.dailyGoal)
    }

    /// The facts for a day, week or month; nil for a year, and for a place
    /// with no sessions. A week's or month's summary and previous-period focus
    /// come from History's index, its session totals and goal days from
    /// per-day projections; request them from History, where the index is
    /// current.
    func noteFacts(for place: HistoryPlace) -> NoteFacts? {
        switch place.level {
        case .day: return dayNoteFacts(place)
        case .week, .month: return periodNoteFacts(place)
        case .year: return nil
        }
    }

    /// "1h 30m focus · goal missed · 1 session". A day's figures come from
    /// its own projection, which is always current: History's index is
    /// refreshed only while History is open or when Ask looks something up,
    /// and the Yesterday notice shows this line over the Story. Other places
    /// read History's summary, goal left out.
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
    /// for it. Asks the day's projection, not its facts: a day has facts
    /// exactly when it has a focus session, and the facts weigh 14 days more.
    func yesterdayNotePlace() -> HistoryPlace? {
        guard let place = yesterdayPlace(), engine.store.yesterdayNoteDismissedDay != place.start,
              !storyDayProjection(on: place.start, calendar: periodCalendar).focusSessions.isEmpty else { return nil }
        return place
    }

    /// Closes the Yesterday notice for the day it is showing. The caller names
    /// the day, since pressing Done after midnight finds a later yesterday.
    func dismissYesterdayNote(_ place: HistoryPlace) {
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
        let typical = NoteBaseline.typical(noteEarlierDays(before: place.start))
        // The Story's own longest stretch: a session's span counts its pauses, its work does not.
        let longest = storyLongestFocusStretch(in: place.span)
            .map { NoteStretch(name: $0.name, start: $0.start, worked: $0.seconds) }
        return NoteFacts.day(NoteDayInput(date: place.start, isCurrent: noteIsCurrent(place), sessions: sessions,
                                          sessionCount: day.focusSessionCount, apps: day.apps, focused: day.focused,
                                          goal: engine.store.dailyGoal, goalCredit: day.goalCredit,
                                          typicalFocused: typical.focused, typicalStretch: typical.stretch,
                                          typicalDays: typical.days, longestStretch: longest,
                                          focusByPart: noteFocusByPart(place.span)),
                             calendar: calendar)
    }

    /// The baseline's days, the 14 whole days before `day`: each one's focus
    /// and how many focus stretches had work on it, counted as the Story
    /// counts a day's focus (each stretch's own work inside the day, the
    /// running one's too). One pass over the stretches inside the window: the
    /// facts are built for every History day row's note.
    func noteEarlierDays(before day: Date) -> [(focused: TimeInterval, stretches: Int)] {
        let calendar = periodCalendar
        var days: [(span: DateInterval, focused: TimeInterval, stretches: Int)] = []
        var end = calendar.startOfDay(for: day)
        for _ in 0..<NoteBaseline.days {
            guard let earlier = calendar.date(byAdding: .day, value: -1, to: end) else { break }
            let start = calendar.startOfDay(for: earlier)
            days.append((DateInterval(start: start, end: end), 0, 0))
            end = start
        }
        guard let first = days.last?.span.start, let last = days.first?.span.end else { return [] }
        for record in engine.archive.records
        where record.workType.countsAsFocus && record.end > first && record.start < last {
            for index in days.indices {
                let work = record.workSeconds(in: (start: days[index].span.start, end: days[index].span.end))
                if work > 0 { days[index].focused += work; days[index].stretches += 1 }
            }
        }
        return days.map { ($0.focused + storyRunningFocusSeconds(in: $0.span), $0.stretches) }
    }

    /// The day's focus by part of the day, counted as its total is: each
    /// stretch's own work inside the part, the running one's too.
    func noteFocusByPart(_ day: DateInterval) -> [NoteDayPart: TimeInterval] {
        let calendar = periodCalendar
        func clock(_ hour: Int) -> Date {
            hour >= 24 ? day.end : calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start) ?? day.start
        }
        let records = engine.archive.records(on: day.start).filter { $0.workType.countsAsFocus }
        var focus: [NoteDayPart: TimeInterval] = [:]
        for part in NoteDayPart.allCases {
            for hours in part.hours {
                let span = (start: clock(hours.from), end: clock(hours.to))
                guard span.end > span.start else { continue }
                let archived = records.reduce(0) { $0 + $1.workSeconds(in: span) }
                focus[part, default: 0] += archived + storyRunningFocusSeconds(in: DateInterval(start: span.start, end: span.end))
            }
        }
        return focus
    }

    private func periodNoteFacts(_ place: HistoryPlace) -> NoteFacts? {
        let calendar = periodCalendar
        let summary = historySummary(for: place)
        guard summary.sessions > 0 else { return nil }
        let goal = engine.store.dailyGoal
        let today = calendar.startOfDay(for: now())
        var worked: [String: TimeInterval] = [:]
        var weekdays: [Int: NoteWeekday] = [:]
        var goalMetDays = 0
        var cursor = calendar.startOfDay(for: place.span.start)
        while cursor < place.span.end, cursor <= today {
            let day = storyDayProjection(on: cursor, calendar: calendar)
            // Named as the Story and a day's facts name them: a blank name is its kind's.
            for session in day.focusSessions {
                worked[session.workType.sessionTitle(named: session.name), default: 0] += session.worked
            }
            if goal > 0, day.goalCredit >= goal { goalMetDays += 1 }
            if day.focused > 0 {
                let weekday = calendar.component(.weekday, from: cursor)
                let seen = weekdays[weekday]
                weekdays[weekday] = NoteWeekday(date: seen?.date ?? cursor, focused: (seen?.focused ?? 0) + day.focused,
                                                days: (seen?.days ?? 0) + 1)
            }
            cursor = HistoryTreeBuilder.dayAfter(cursor, calendar: calendar)
        }
        let totals = worked.map { (name: $0.key, worked: $0.value) }
            .sorted { $0.worked != $1.worked ? $0.worked > $1.worked : $0.name < $1.name }
        // Worth saying only when focus fell on more than one weekday.
        let busiest = weekdays.count > 1
            ? weekdays.values.max { $0.focused != $1.focused ? $0.focused < $1.focused : $0.date > $1.date } : nil
        let longest = storyLongestFocusStretch(in: place.span)
            .map { NoteStretch(name: $0.name, start: $0.start, worked: $0.seconds) }
        let current = noteIsCurrent(place)
        return NoteFacts.period(NotePeriodInput(span: place.span, level: place.level, isCurrent: current,
                                                summary: summary, sessionTotals: totals, goal: goal,
                                                goalMetDays: goalMetDays,
                                                previousFocused: previousFocused(before: place, isCurrent: current),
                                                longestStretch: longest, busiestWeekday: busiest),
                                calendar: calendar)
    }

    /// The focus of the same-level period just before, or 0 for no
    /// comparison. A period still running, or cut short by a month's edge or
    /// the start of the record, is not weighed against a whole one, nor is one
    /// whose period before began ahead of the record's first day.
    private func previousFocused(before place: HistoryPlace, isCurrent: Bool) -> TimeInterval {
        let calendar = periodCalendar
        let whole = HistoryTreeBuilder.period(place.level, containing: place.start, calendar: calendar)
        guard !isCurrent, whole == place.span,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: place.start) else { return 0 }
        let span = HistoryTreeBuilder.period(place.level, containing: dayBefore, calendar: calendar)
        guard span.start >= historyTop().firstDay else { return 0 }
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
