import Foundation

/// The Review read model. It composes existing canonical period/accounting
/// helpers and publishes presentation-ready values; no archive mutation or
/// historical repair is possible from this surface.
extension SessionStore {
    func setReviewVisible(_ visible: Bool) {
        reviewVisible = visible
        if visible && reviewRefreshPending { refreshReview() }
    }

    func selectReviewSection(_ section: ReviewSection) {
        switch section {
        case .week: refreshReview(period: .week)
        case .month: refreshReview(period: .month)
        case .history:
            if reviewRefreshPending { refreshReview() }
        }
    }

    /// Rebuilds period Review and canonical History from one authoritative usage
    /// snapshot. The optional period is only the Review-local selection; Today's
    /// `dayOffset` and selected evidence remain untouched.
    func refreshReview(period requestedPeriod: TrackingPeriod? = nil) {
        if let requestedPeriod, requestedPeriod != .day { reviewPeriod = requestedPeriod }
        guard let usage else {
            clearReviewData()
            return
        }

        let calendar = Calendar.current
        let snapshot = effectiveUsageSnapshot ?? AppUsageSnapshot(archive: usage)
        let anchor = reviewAnchor ?? calendar.startOfDay(for: now())
        reviewAnchor = anchor

        let previousNewest = historyDays.first?.date
        let previousOldest = historyDays.last?.date
        let rebuiltHistory = HistoryStats.days(
            sessionRecords: engine.archive.records,
            usage: snapshot.sessions,
            calendar: calendar)
        historyDays = rebuiltHistory
        maintainHistoryRange(previousNewest: previousNewest,
                             previousOldest: previousOldest,
                             calendar: calendar)

        var names: [String: String] = [:]
        for session in snapshot.sessions.sorted(by: { $0.end < $1.end }) {
            names[session.bundleID] = session.appName
        }
        historyAppNames = names

        let periodStats = PeriodStats(sessions: engine.archive, usage: usage,
                                      usageSnapshot: snapshot,
                                      calendar: calendar, now: now)
        let rollup = periodStats.rollup(for: reviewPeriod, containing: anchor)
        reviewDays = rollup.days
        reviewLog = rollup.log
        reviewAppGroups = PeriodStats.appGroups(from: rollup.log)
        reviewDayTotals = rollup.dayTotals
        reviewSummary = rollup.summary
        reviewWorkTypeShares = Self.reviewWorkTypes(from: rollup.days)

        let bounds = periodStats.bounds(for: reviewPeriod, containing: anchor)
        var longestFocusRecord: SessionRecord?
        var longestFocusSeconds: TimeInterval = 0
        for record in engine.archive.records where record.workType.countsAsFocus {
            let seconds = record.workSeconds(in: (start: bounds.start, end: bounds.end))
            if seconds > 0 && (seconds > longestFocusSeconds
                || (seconds == longestFocusSeconds
                    && record.start < (longestFocusRecord?.start ?? .distantFuture))) {
                longestFocusRecord = record
                longestFocusSeconds = seconds
            }
        }
        reviewLongestFocusSeconds = longestFocusSeconds
        reviewLongestFocusName = longestFocusRecord.map {
            $0.name.isEmpty ? $0.workType.displayName : $0.name
        }
        let legacyEnd = min(bounds.end, snapshot.accurateFrom)
        let containsLegacy = legacyEnd > bounds.start && snapshot.sessions.contains {
            $0.end > bounds.start && $0.start < legacyEnd
        }
        reviewIntegrityNote = containsLegacy
            ? "App usage from before \(Tokens.longDate(snapshot.accurateFrom)) was preserved "
                + "and may include unattended time."
            : nil
        reviewRefreshPending = false
    }

    func moveReviewPeriod(by delta: Int) {
        guard delta != 0 else { return }
        let calendar = Calendar.current
        let anchor = reviewAnchor ?? calendar.startOfDay(for: now())
        let component: Calendar.Component = reviewPeriod == .month ? .month : .weekOfYear
        guard var candidate = calendar.date(byAdding: component, value: delta, to: anchor) else {
            return
        }
        let today = calendar.startOfDay(for: now())
        if candidate > today { candidate = today }
        reviewAnchor = candidate
        refreshReview()
    }

    var reviewCanMoveForward: Bool {
        let calendar = Calendar.current
        guard let usage else { return false }
        let periodStats = PeriodStats(sessions: engine.archive, usage: usage,
                                      usageSnapshot: effectiveUsageSnapshot,
                                      calendar: calendar, now: now)
        let shown = periodStats.bounds(for: reviewPeriod,
                                       containing: reviewAnchor ?? now())
        let current = periodStats.bounds(for: reviewPeriod, containing: now())
        return shown.start < current.start
    }

    var reviewPeriodLabel: String {
        let anchor = reviewAnchor ?? now()
        if reviewPeriod == .month {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: anchor)
        }
        guard let usage else { return Tokens.longDate(anchor) }
        let calendar = Calendar.current
        let bounds = PeriodStats(sessions: engine.archive, usage: usage,
                                 usageSnapshot: effectiveUsageSnapshot,
                                 calendar: calendar, now: now)
            .bounds(for: .week, containing: anchor)
        let finalDay = calendar.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.start
        let first = DateFormatter()
        first.locale = Locale(identifier: "en_AU")
        first.dateFormat = calendar.component(.month, from: bounds.start)
            == calendar.component(.month, from: finalDay) ? "d" : "d MMM"
        let last = DateFormatter()
        last.locale = Locale(identifier: "en_AU")
        last.dateFormat = "d MMMM yyyy"
        return "\(first.string(from: bounds.start))–\(last.string(from: finalDay))"
    }

    var reviewSummaryLine: String {
        guard reviewSummary.activeDays > 0 else {
            return "No comparable days yet; period history builds locally."
        }
        let dayWord = reviewSummary.activeDays == 1 ? "active day" : "active days"
        return "\(Tokens.duration(reviewSummary.tracked)) tracked · "
            + "\(reviewSummary.activeDays) \(dayWord) · "
            + "\(Tokens.duration(reviewSummary.averagePerActiveDay)) average"
    }

    var filteredHistoryDays: [HistoryDay] {
        let calendar = Calendar.current
        let filtered = historyFilter.apply(to: historyDays)
        guard let rawStart = historyRangeStart, let rawEnd = historyRangeEnd else {
            return filtered
        }
        let start = calendar.startOfDay(for: min(rawStart, rawEnd))
        let end = calendar.startOfDay(for: max(rawStart, rawEnd))
        return filtered.filter { $0.date >= start && $0.date <= end }
    }

    var historyAppBundleIDs: [String] {
        Set(historyDays.flatMap(\.appBundleIDs)).sorted {
            historyAppName(for: $0).localizedCaseInsensitiveCompare(historyAppName(for: $1))
                == .orderedAscending
        }
    }

    func historyAppName(for bundleID: String) -> String {
        historyAppNames[bundleID] ?? bundleID
    }

    func setHistoryQuery(_ query: String) {
        historyFilter.query = query
    }

    func setHistoryApp(_ bundleID: String?) {
        historyFilter.appBundleID = bundleID
    }

    func setHistoryWorkType(_ workType: WorkType?) {
        historyFilter.workType = workType
    }

    func clearHistoryFilters() {
        historyFilter = HistoryFilter()
    }

    func resetHistoryRange() {
        historyRangeStart = historyDays.last?.date
        historyRangeEnd = historyDays.first?.date
    }

    private func maintainHistoryRange(previousNewest: Date?,
                                      previousOldest: Date?,
                                      calendar: Calendar) {
        guard let newest = historyDays.first?.date, let oldest = historyDays.last?.date else {
            historyRangeStart = nil
            historyRangeEnd = nil
            return
        }
        let rangeTrackedOldest: Bool
        if let rangeStart = historyRangeStart, let previousOldest {
            rangeTrackedOldest = calendar.isDate(previousOldest, inSameDayAs: rangeStart)
        } else {
            rangeTrackedOldest = false
        }
        if historyRangeStart == nil || rangeTrackedOldest {
            historyRangeStart = oldest
        } else if let start = historyRangeStart, start < oldest {
            historyRangeStart = oldest
        }
        let rangeTrackedNewest: Bool
        if let rangeEnd = historyRangeEnd, let previousNewest {
            rangeTrackedNewest = calendar.isDate(previousNewest, inSameDayAs: rangeEnd)
        } else {
            rangeTrackedNewest = false
        }
        if historyRangeEnd == nil || rangeTrackedNewest {
            historyRangeEnd = newest
        } else if let end = historyRangeEnd, end > newest {
            historyRangeEnd = newest
        }
    }

    private func clearReviewData() {
        reviewDays = []
        reviewLog = []
        reviewAppGroups = []
        reviewDayTotals = [:]
        reviewSummary = PeriodRollup.empty.summary
        reviewLongestFocusSeconds = 0
        reviewLongestFocusName = nil
        reviewWorkTypeShares = []
        reviewIntegrityNote = nil
        historyDays = []
        historyRangeStart = nil
        historyRangeEnd = nil
        historyAppNames = [:]
        reviewRefreshPending = false
    }

    private static func reviewWorkTypes(from days: [PeriodDay]) -> [WorkTypeShare] {
        var seconds: [WorkType: TimeInterval] = [:]
        for day in days {
            for share in day.byWorkType { seconds[share.workType, default: 0] += share.seconds }
        }
        let total = seconds.values.reduce(0, +)
        return WorkType.allCases.compactMap { type in
            guard let value = seconds[type], value > 0 else { return nil }
            return WorkTypeShare(workType: type, seconds: value,
                                 share: total > 0 ? value / total : 0)
        }
        .sorted { $0.seconds > $1.seconds }
    }
}
