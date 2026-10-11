import Foundation

/// Ask's account of what happened between sessions. Every item is read from
/// the reader its screen uses: breaks from the Story's day projection,
/// answers about time away and absences not yet answered from its timeline
/// (the projection's `chronology` is `storyTimelineItems(on:)`), and the
/// Mac's rows and summary from `macAccount(on:)`. `AskFacts` only words them.
extension SessionStore {
    func askDayEvents(_ range: AskRange) -> AskLookupResult {
        let calendar = periodCalendar
        let interval = askInterval(range)
        let days = range.isOneDay ? [interval.start] : askEventDays(in: interval, calendar: calendar)
        // Newest first, and no further than the text can hold: a long
        // history is counted, not read.
        var built: [(day: Date, events: AskEventDay)] = []
        var bytes = 0, empty = 0
        var cut = false
        for day in days where day <= calendar.startOfDay(for: now()) {
            // A candidate day that yields nothing is not a day with something to tell.
            guard let events = askEventDay(day, calendar: calendar) else { empty += 1; continue }
            built.append((day, events))
            bytes += AskFacts.dayLine(events).utf8.count + 1
            if range.isOneDay || bytes > AskFacts.maximumBytes { cut = !range.isOneDay; break }
        }
        let log = askEventLogStart(before: interval, calendar: calendar)
        let absences = askEventAbsences(in: interval, beforeLog: log.before)
        // Days not read are counted as candidates; read ones, as listed.
        let total = cut ? days.count - empty : built.count
        let events = built.map { $0.events }
        let shown = range.isOneDay ? built.count
            : AskFacts.dayEventsShown(events, total: total, logFrom: log.from, beforeLog: log.before,
                                    absences: absences)
        let listed = Array(built.prefix(shown))
        let anchor = askPeriodLink(range, role: .whatHappened)
        let places = listed.map { day in
            askPlaceLink(HistoryPlace(level: .day, span: HistoryTreeBuilder.period(.day, containing: day.day,
                                                                                    calendar: calendar)),
                         role: .whatHappened)
        }
        return AskLookupResult(
            text: AskFacts.dayEvents(range, days: listed.map { $0.events }, total: total, logFrom: log.from,
                                     beforeLog: log.before, absences: absences),
            // A day asked about is the anchor itself.
            links: [anchor] + places.filter { $0 != anchor })
    }

    /// The first day the Mac's event log holds, said as a lookup says days,
    /// when the interval begins before it; and whether it ends before it.
    private func askEventLogStart(before interval: DateInterval, calendar: Calendar) -> (from: String?, before: Bool) {
        guard let first = machineEventLog?.events.first?.at else { return (nil, false) }
        let start = calendar.startOfDay(for: first)
        return interval.start < start ? (askDay(start), interval.end <= start) : (nil, false)
    }

    /// What the Mac's log, read for the interval as the "What the Mac did"
    /// card reads it, holds no sign of. Nothing is denied for a period before
    /// the log begins or with no log: it cannot say.
    private func askEventAbsences(in interval: DateInterval, beforeLog: Bool) -> [String] {
        guard let log = machineEventLog, !log.events.isEmpty, !beforeLog else { return [] }
        let kinds = Set(log.events(in: interval).map(\.kind))
        return (kinds.isDisjoint(with: MachineEvent.Kind.restarts) ? [AskFacts.noRestart] : [])
            + (kinds.isDisjoint(with: GapAnatomy.found) ? [AskFacts.noCrash] : [])
    }

    /// The days of the interval, up to today and newest first, that have
    /// something to tell. Found from the archive's break records, the away
    /// answers and the event log's days, not by reading every day; a day the
    /// log touches counts only when the Mac's card has rows for it.
    private func askEventDays(in interval: DateInterval, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now())
        func touched(_ span: DateInterval) -> [Date] {
            guard span.end > interval.start || (span.duration == 0 && span.end == interval.start) else { return [] }
            var days: [Date] = []
            var day = calendar.startOfDay(for: max(span.start, interval.start))
            while day < interval.end, day <= today {
                days.append(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = calendar.startOfDay(for: next)
                if day >= span.end { break }
            }
            return days
        }
        var found = Set<Date>()
        for record in engine.archive.records where record.workType == .breakTime {
            found.formUnion(touched(DateInterval(start: record.start, end: max(record.start, record.end))))
        }
        for receipt in engine.awayDecisions { found.formUnion(touched(receipt.range)) }
        if let pending = pendingAwayRange {
            found.formUnion(touched(DateInterval(start: pending.start, end: max(pending.start, pending.end))))
        }
        var mac = Set<Date>()
        for event in machineEventLog?.events ?? [] {
            mac.formUnion(touched(DateInterval(start: event.at, end: max(event.at, event.end))))
        }
        found.formUnion(mac.subtracting(found).filter { macAccount(on: $0) != nil })
        return found.sorted(by: >)
    }

    /// One day's items in time order, breaks before answers before the Mac
    /// when they start together; nil when it has none.
    private func askEventDay(_ day: Date, calendar: Calendar) -> AskEventDay? {
        var found: [(start: Date, rank: Int, item: AskEventItem)] = []
        let projection = storyDayProjection(on: day, calendar: calendar)
        // A break an answer made is told by the answer, as the timeline has it.
        let answered = Set(engine.awayDecisions.compactMap(\.insertedRecord?.id))
        var breaks = 0, breakTime: TimeInterval = 0, answers = 0, pending = 0
        for case let .rest(rest) in projection.sessions where !answered.contains(rest.id) {
            breaks += 1
            breakTime += rest.length
            found.append((rest.start, 0, AskEventItem(
                kind: .breakTaken(name: rest.name == "Break" ? nil : rest.name),
                from: askClock(rest.start, on: day, calendar: calendar),
                to: askClock(rest.end, on: day, calendar: calendar), length: rest.length)))
        }
        for entry in projection.chronology {
            switch entry {
            case let .decision(receipt, span) where receipt.isResolved:
                answers += 1
                found.append((span.start, 1, askAway(.away(
                    answer: receipt.name.isEmpty ? nil : receipt.name, outcome: receipt.title,
                    credited: receipt.decision == .mergeTime ? receipt.creditedSeconds : nil), span, on: day)))
            case let .decision(_, span), let .pending(span):
                pending += 1
                found.append((span.start, 1, askAway(.pending, span, on: day)))
            default:
                continue
            }
        }
        let account = macAccount(on: day)
        for row in account?.rows ?? [] {
            found.append((row.span.start, 2, AskEventItem(
                kind: .mac(title: row.title, uncertain: row.state == .uncertain || row.foundAt != nil,
                           found: row.foundAt.map(askTime)),
                from: askClock(row.span.start, on: day, calendar: calendar),
                to: row.span.duration > 0 ? askClock(row.span.end, on: day, calendar: calendar) : nil, length: nil)))
        }
        guard !found.isEmpty else { return nil }
        let ordered = found.enumerated().sorted {
            ($0.element.start, $0.element.rank, $0.offset) < ($1.element.start, $1.element.rank, $1.offset)
        }
        let summary = account?.summary
        return AskEventDay(label: askDay(day), items: ordered.map { $0.element.item }, breaks: breaks,
                           breakTime: breakTime, answers: answers, pending: pending,
                           macSummary: summary?.isEmpty == false ? summary : nil)
    }

    private func askAway(_ kind: AskEventItem.Kind, _ span: DateInterval, on day: Date) -> AskEventItem {
        let calendar = periodCalendar
        return AskEventItem(kind: kind, from: askClock(span.start, on: day, calendar: calendar),
                            to: span.duration > 0 ? askClock(span.end, on: day, calendar: calendar) : nil, length: nil)
    }

    /// A clock time on `day`, said “midnight” at the day's own start or end
    /// (where the day cuts a span) rather than 12:00am, which the model read
    /// as the next morning.
    private func askClock(_ date: Date, on day: Date, calendar: Calendar) -> String {
        date == day || date == calendar.date(byAdding: .day, value: 1, to: day) ? AskFacts.midnight : askTime(date)
    }
}
