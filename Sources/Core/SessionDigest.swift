import Foundation

/// One focus session as the day shows it: the records of one thread that ran
/// back to back (only breaks between them), folded into a row with its
/// stretches and spans. Pure value, so the card and the tests share it.
struct DaySession: Identifiable, Equatable {
    let id: UUID
    let threadID: UUID
    let name: String
    let workType: WorkType
    let start: Date
    let end: Date
    let worked: TimeInterval
    let stretches: Int
    /// Each stretch's span, for framing the timeline and for "apps used
    /// inside this session".
    let spans: [DateInterval]
    var recordIDs: [UUID] = []
    let isRunning: Bool
}

/// A recorded rest between sessions, named when the user named it.
struct RestEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let start: Date
    let end: Date
    var length: TimeInterval { end.timeIntervalSince(start) }
}

enum DayEntry: Identifiable, Equatable {
    case session(DaySession)
    case rest(RestEntry)

    var id: UUID {
        switch self {
        case .session(let session): return session.id
        case .rest(let rest): return rest.id
        }
    }

    var start: Date {
        switch self {
        case .session(let session): return session.start
        case .rest(let rest): return rest.start
        }
    }
}

/// Folds a day's records into the rows the Sessions card shows.
enum SessionDigest {

    /// `records` are the day's (anything overlapping it); `running` is the live
    /// session when the day is today. Sorted by start; a focus record joins the
    /// open session when it shares its thread and nothing but rest came between;
    /// a break record is a rest row and leaves the session open.
    static func entries(records: [SessionRecord],
                        running: RunningThread?,
                        now: Date,
                        day: Date,
                        calendar: Calendar = .current) -> [DayEntry] {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return [] }
        func clip(start: Date, end: Date, worked: TimeInterval) -> (start: Date, end: Date,
                                                                      worked: TimeInterval)? {
            let clippedStart = max(start, bounds.start)
            let clippedEnd = min(end, bounds.end)
            guard clippedEnd >= clippedStart else { return nil }
            let fullSpan = max(0, end.timeIntervalSince(start))
            let credit: TimeInterval
            if fullSpan > 0 {
                credit = worked * (clippedEnd.timeIntervalSince(clippedStart) / fullSpan)
            } else {
                credit = end >= bounds.start && end < bounds.end ? worked : 0
            }
            guard clippedEnd > clippedStart || credit > 0 else { return nil }
            return (clippedStart, clippedEnd, credit)
        }
        var items: [(start: Date, end: Date, name: String, type: WorkType, worked: TimeInterval,
                     thread: UUID, id: UUID, running: Bool)] = records.compactMap { record in
            guard let clipped = clip(start: record.start, end: record.end, worked: record.workSeconds) else {
                return nil
            }
            return (clipped.start, clipped.end, record.name, record.workType, clipped.worked,
                    record.threadID, record.id, false)
        }
        if let running {
            if let clipped = clip(start: running.start, end: now, worked: running.worked) {
                items.append((clipped.start, clipped.end, running.name, running.workType, clipped.worked,
                              running.threadID, running.recordID ?? running.threadID, true))
            }
        }
        items.sort { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }

        var entries: [DayEntry] = []
        var open: DaySession?
        func close() {
            if let session = open { entries.append(.session(session)) }
            open = nil
        }
        for item in items {
            if item.type == .breakTime {
                entries.append(.rest(RestEntry(id: item.id,
                                               name: item.name.isEmpty ? "Break" : item.name,
                                               start: item.start, end: item.end)))
                continue
            }
            if let current = open, current.threadID == item.thread {
                open = DaySession(id: current.id, threadID: current.threadID,
                                  name: item.name.isEmpty ? current.name : item.name,
                                  workType: current.workType,
                                  start: current.start, end: max(current.end, item.end),
                                  worked: current.worked + item.worked,
                                  stretches: current.stretches + 1,
                                  spans: current.spans + [DateInterval(start: item.start, end: max(item.start, item.end))],
                                  recordIDs: current.recordIDs + [item.id],
                                  isRunning: current.isRunning || item.running)
            } else {
                close()
                open = DaySession(id: item.id, threadID: item.thread,
                                  name: item.name, workType: item.type,
                                  start: item.start, end: item.end,
                                  worked: item.worked, stretches: 1,
                                  spans: [DateInterval(start: item.start, end: max(item.start, item.end))],
                                  recordIDs: [item.id],
                                  isRunning: item.running)
            }
        }
        close()
        // Rests were appended as met; sessions when closed. Order the lot by start.
        return entries.sorted { $0.start < $1.start }
    }
}
