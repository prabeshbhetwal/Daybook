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
                                          usage: effectiveUsageSnapshot?.sessions ?? [],
                                          day: day, now: now()).reversed())
            .filter { moment in
                if case .entry(.session(let session)) = moment, session.isRunning {
                    return runningIsOnDay
                }
                return true
            }
    }

    var storyAppColourIndices: [String: Int] {
        Dictionary(uniqueKeysWithValues: rankedApps.enumerated().map { ($0.element.bundleID, $0.offset) })
    }

    func storyAppEvidence(for bundleID: String, period: TrackingPeriod?) -> StoryAppEvidence {
        let bounds = period == nil
            ? Calendar.current.dateInterval(of: .day, for: selectedDay) : storyReviewBounds()
        guard let bounds else { return StoryAppEvidence(visits: []) }
        return StoryAppEvidence.clipped(effectiveUsageSnapshot?.sessions ?? [],
                                        bundleID: bundleID, to: bounds)
    }
}
