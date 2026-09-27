import Foundation

/// One local day's complete Story read model. It owns no engine or store: every
/// action still targets the single SessionStore through the exact IDs carried
/// by `chronology`.
struct StoryDayProjection: Identifiable {
    let date: Date
    let chronology: [StoryTimelineItem]
    let summaryFacts: [String]
    let focused: TimeInterval
    let tracked: TimeInterval
    let goalCredit: TimeInterval
    let longestFocusStretch: TimeInterval
    let sessions: [DayEntry]
    let apps: [AppRank]
    let sessionDetails: [UUID: StorySessionDetail]
    let integrityNote: String?
    let isCurrentDay: Bool

    var id: String { "story-day-\(date.timeIntervalSince1970)" }
    var focusSessionCount: Int {
        Set(sessions.compactMap { entry -> UUID? in
            if case .session(let session) = entry { return session.threadID }
            return nil
        }).count
    }
    var recordedBreakSeconds: TimeInterval {
        sessions.reduce(0) { total, entry in
            if case .rest(let rest) = entry { return total + rest.length }
            return total
        }
    }
    var appColourIndices: [String: Int] {
        Dictionary(uniqueKeysWithValues: apps.enumerated().map { ($0.element.bundleID, $0.offset) })
    }
}

struct StoryDayProjectionCacheKey: Hashable {
    let day: Date
    let archiveRevision: Int
    let usageIdentity: ObjectIdentifier?
    let usageRevision: Int
    let overlayRevision: Int
    let decisionHistoryRevision: Int
    let metadataRevision: Int
}

struct StoryPeriodProjection: Identifiable {
    let scope: InsightRange
    let start: Date
    let end: Date
    let isCurrent: Bool
    let days: [StoryDayProjection]

    var id: String { "\(scope.rawValue)-\(start.timeIntervalSince1970)" }
    var focused: TimeInterval { days.reduce(0) { $0 + $1.focused } }
    var tracked: TimeInterval { days.reduce(0) { $0 + $1.tracked } }
    var goalCredit: TimeInterval { days.reduce(0) { $0 + $1.goalCredit } }
    var activeDays: Int { days.filter { $0.focused > 0 || $0.tracked > 0 }.count }
}

extension SessionStore {
    func storyDayProjection(on requestedDate: Date,
                            calendar: Calendar = .current) -> StoryDayProjection {
        let day = calendar.startOfDay(for: requestedDate)
        let dayBounds = calendar.dateInterval(of: .day, for: day)
        let revision = evidenceRevision
        let key = StoryDayProjectionCacheKey(
            day: day,
            archiveRevision: revision.sessions,
            usageIdentity: revision.usageID,
            usageRevision: revision.usage,
            overlayRevision: -1,
            decisionHistoryRevision: engine.decisionHistoryRevision,
            metadataRevision: revision.metadata)
        let runningTouchesDay = dayBounds.map { bounds in
            engine.runningSpan.map { $0.end > bounds.start && $0.start < bounds.end } ?? false
        } ?? false
        let overlayTouchesDay = dayBounds.map { bounds in
            (tracker?.usageOverlaySessions() ?? []).contains {
                $0.end > bounds.start && $0.start < bounds.end
            }
        } ?? false
        let isCurrent = calendar.isDate(day, inSameDayAs: now())
        if !isCurrent, !runningTouchesDay, !overlayTouchesDay,
           let cached = storyProjectionCache[key] {
            return cached
        }

        let running = runningTouchesDay ? runningThread() : nil
        let entries = SessionDigest.entries(records: engine.archive.records,
                                             running: running,
                                             now: now(), day: day,
                                             calendar: calendar)
        let snapshot = effectiveUsageSnapshot
        let stats: DashboardStats? = usage.map {
            DashboardStats(sessions: engine.archive, usage: $0,
                           usageSnapshot: snapshot, calendar: calendar, now: now)
        }
        let apps = stats?.rankedApps(for: day) ?? []
        let tracked = apps.reduce(0) { $0 + $1.total }
        let focused = storyFocusedSeconds(on: day)
        let goalCredit = focusedActiveSeconds(on: day, usageSnapshot: snapshot)
        let chronology = storyTimelineItems(on: day)
        var details: [UUID: StorySessionDetail] = [:]
        for entry in entries {
            if case .session(let session) = entry {
                details[session.id] = storySessionDetail(session, on: day)
            }
        }
        let integrityNote: String?
        if let usage, let bounds = dayBounds {
            let accuracyEpoch = snapshot?.accurateFrom ?? usage.metadata.accurateFrom
            integrityNote = usage.containsUsage(in: bounds, before: accuracyEpoch)
                ? "App usage from before \(Tokens.longDate(accuracyEpoch)) was preserved and may include unattended time."
                : nil
        } else {
            integrityNote = nil
        }
        let summary = Self.storyDaySummaryFacts(entries: entries, apps: apps)
        let projection = StoryDayProjection(
            date: day, chronology: chronology, summaryFacts: summary,
            focused: focused, tracked: tracked, goalCredit: goalCredit,
            longestFocusStretch: storyLongestStretch(on: day),
            sessions: entries, apps: apps, sessionDetails: details,
            integrityNote: integrityNote, isCurrentDay: isCurrent)
        if !isCurrent, !runningTouchesDay, !overlayTouchesDay {
            storyProjectionCache[key] = projection
            storyProjectionCacheOrder.removeAll { $0 == key }
            storyProjectionCacheOrder.append(key)
            while storyProjectionCacheOrder.count > 96 {
                storyProjectionCache.removeValue(forKey: storyProjectionCacheOrder.removeFirst())
            }
        }
        return projection
    }

    func insightPeriodProjections(scope: InsightRange,
                                  anchoredAt requestedAnchor: Date,
                                  limit requestedLimit: Int,
                                  calendar: Calendar = .current) -> [StoryPeriodProjection] {
        let today = calendar.startOfDay(for: now())
        let anchor = min(today, calendar.startOfDay(for: requestedAnchor))
        let limit: Int
        switch scope {
        case .day: limit = min(max(1, requestedLimit), 42)
        case .week: limit = min(max(1, requestedLimit), 14)
        case .month: limit = min(max(1, requestedLimit), 12)
        }
        let component: Calendar.Component
        switch scope {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        var result: [StoryPeriodProjection] = []
        for offset in 0..<limit {
            guard let reference = calendar.date(byAdding: component, value: -offset,
                                                to: anchor),
                  let bounds = scope == .day
                    ? calendar.dateInterval(of: .day, for: reference)
                    : calendar.dateInterval(of: component, for: reference) else { continue }
            let current = today >= bounds.start && today < bounds.end
            let lastIncluded = current ? today
                : calendar.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.start
            var days: [StoryDayProjection] = []
            var day = calendar.startOfDay(for: bounds.start)
            var visited = 0
            while day <= lastIncluded && visited < 31 {
                visited += 1
                days.append(storyDayProjection(on: day, calendar: calendar))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            result.append(StoryPeriodProjection(scope: scope, start: bounds.start,
                                                end: bounds.end, isCurrent: current,
                                                days: days))
        }
        return result
    }
}
