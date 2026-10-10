import Foundation

struct StoryAppEvidence: Equatable {
    let visits: [AppUsageSession]
    var total: TimeInterval { visits.reduce(0) { $0 + $1.seconds } }

    static func clipped(_ sessions: [AppUsageSession], bundleID: String,
                        to bounds: DateInterval) -> StoryAppEvidence {
        let visits = sessions.compactMap { source -> AppUsageSession? in
            guard source.bundleID == bundleID else { return nil }
            let start = max(source.start, bounds.start)
            let end = min(source.end, bounds.end)
            guard end > start else { return nil }
            var result = source
            result.start = start
            result.end = end
            return result
        }.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start > $1.start }
        return StoryAppEvidence(visits: visits)
    }
}

extension SessionStore {
    var storyMoments: [StoryMoment] {
        storyMoments(on: selectedDay)
    }

    func storyMoments(on day: Date) -> [StoryMoment] {
        let calendar = Calendar.current
        let bounds = calendar.dateInterval(of: .day, for: day)
        let runningIsOnDay = bounds.map { interval in
            engine.runningSpan.map { $0.end > interval.start && $0.start < interval.end } ?? false
        } ?? false
        let running = engine.state == .idle ? nil : RunningThread(
            recordID: engine.activeRecordID, threadID: engine.activeThreadID, name: engine.sessionName,
            workType: engine.activeWorkType, start: engine.sessionStartDate, worked: engine.elapsed)
        return Array(StoryChronology.build(records: engine.archive.records, running: running,
                                          usage: effectiveUsageSnapshot?.sessions(touching: day) ?? [],
                                          machineEvents: machineEvents(on: day),
                                          eventLogStart: machineEventLog?.events.first?.at,
                                          day: day, now: now()).reversed())
            .filter { moment in
                if case .entry(.session(let session)) = moment, session.isRunning {
                    return runningIsOnDay
                }
                return true
            }
    }

    /// The machine events of a day, oldest first, including one found
    /// afterwards whose window reaches into it.
    func machineEvents(on day: Date) -> [MachineEvent] {
        guard let bounds = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return machineEventLog?.events(in: bounds) ?? []
    }

    /// What the Mac's events say happened inside a hole in the day. An away
    /// answer splits a hole and each piece keeps the hole's name, so a piece
    /// beside an answer is read against the whole hole it came from.
    func gapAnatomy(of gap: DateInterval) -> GapAnatomy {
        let events = machineEvents(on: gap.start)
        let split = engine.awayDecisions.contains { $0.range.start <= gap.end && $0.range.end >= gap.start }
        guard split else { return GapAnatomy.of(gap, events: events) }
        let hole = storyMoments(on: gap.start).lazy.compactMap { moment -> DateInterval? in
            guard case .unrecorded(let hole, _) = moment, hole.start <= gap.start, hole.end >= gap.end
            else { return nil }
            return hole
        }.first
        return GapAnatomy.of(gap, in: hole, events: events)
    }

    var storyAppColourIndices: [String: Int] {
        Dictionary(uniqueKeysWithValues: rankedApps.enumerated().map { ($0.element.bundleID, $0.offset) })
    }

    /// `day` is History's open day; nil is the dashboard's.
    func storyAppEvidence(for bundleID: String, period: TrackingPeriod?, day: Date? = nil) -> StoryAppEvidence {
        let bounds = period == nil
            ? Calendar.current.dateInterval(of: .day, for: day ?? selectedDay) : storyReviewBounds()
        guard let bounds else { return StoryAppEvidence(visits: []) }
        return StoryAppEvidence.clipped(effectiveUsageSnapshot?.sessions ?? [],
                                        bundleID: bundleID, to: bounds)
    }
}
