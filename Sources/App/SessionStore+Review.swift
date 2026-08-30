import Foundation

/// One archive focus stretch clipped to the selected Review period. This is a
/// read model only; its source `SessionRecord` is never edited or repaired.
struct ReviewFocusEntry: Identifiable, Equatable {
    let id: UUID
    let threadID: UUID
    let name: String
    let workType: WorkType
    let start: Date
    let end: Date
    let seconds: TimeInterval
}

/// The Review read model. It composes existing canonical period/accounting
/// helpers and publishes presentation-ready values; no archive mutation or
/// historical repair is possible from this surface.
extension SessionStore {
    private static let maximumReviewFocusRows = 500

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
        let rebuiltHistory = HistoryStats.build(
            sessionRecords: engine.archive.records,
            usage: snapshot.sessions,
            calendar: calendar)
        historyDays = rebuiltHistory.days
        historyIntegrityNotices = []
        if snapshot.sessions.contains(where: {
            $0.end > $0.start && $0.start < snapshot.accurateFrom
        }) {
            historyIntegrityNotices.append(
                "History includes preserved legacy app usage from before "
                    + "\(Tokens.longDate(snapshot.accurateFrom)); it may include unattended time.")
        }
        if rebuiltHistory.droppedUsageSpans > 0
            || rebuiltHistory.droppedSessionSpans > 0 {
            var dropped: [String] = []
            if rebuiltHistory.droppedUsageSpans > 0 {
                let count = rebuiltHistory.droppedUsageSpans
                dropped.append("\(count) app-usage " + (count == 1 ? "record" : "records"))
            }
            if rebuiltHistory.droppedSessionSpans > 0 {
                let count = rebuiltHistory.droppedSessionSpans
                dropped.append("\(count) focus " + (count == 1 ? "record" : "records"))
            }
            historyIntegrityNotices.append(
                "History omitted \(dropped.joined(separator: " and ")) from derived day rows "
                    + "because each spans at least "
                    + "\(HistoryStats.maximumCalendarDaysPerRecord) calendar days. "
                    + "Source records remain preserved in local data.")
        }
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
        reviewLogTotalEntries = rollup.totalLogEntries
        reviewAppGroups = rollup.exactAppGroups
        reviewDayTotals = rollup.dayTotals
        reviewSummary = rollup.summary
        reviewWorkTypeShares = Self.reviewWorkTypes(from: rollup.days)

        let bounds = periodStats.bounds(for: reviewPeriod, containing: anchor)
        reviewFocusSessions = engine.archive.records.compactMap { record in
            guard record.workType.countsAsFocus else { return nil }
            let seconds = record.workSeconds(in: (start: bounds.start, end: bounds.end))
            guard seconds > 0 else { return nil }
            return ReviewFocusEntry(
                id: record.id,
                threadID: record.threadID,
                name: record.name.isEmpty ? record.workType.displayName : record.name,
                workType: record.workType,
                start: max(record.start, bounds.start),
                end: min(record.end, bounds.end),
                seconds: seconds)
        }
        .sorted { left, right in
            left.start == right.start ? left.id.uuidString > right.id.uuidString
                                      : left.start > right.start
        }
        let longestFocus = reviewFocusSessions.max { left, right in
            left.seconds == right.seconds ? left.start > right.start
                                          : left.seconds < right.seconds
        }
        reviewLongestFocusSeconds = longestFocus?.seconds ?? 0
        reviewLongestFocusName = longestFocus?.name
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
        guard reviewHasRelevantEvidence else {
            return "No comparable days yet; period history builds locally."
        }
        if reviewSummary.activeDays == 0 {
            let count = reviewFocusSessionCount
            let sessions = count == 1 ? "1 focus session" : "\(count) focus sessions"
            let focused = reviewFocusSessions.reduce(0) { $0 + $1.seconds }
            return "No tracked time · \(sessions) · \(Tokens.duration(focused)) recorded focus"
        }
        let dayWord = reviewSummary.activeDays == 1 ? "active day" : "active days"
        return "\(Tokens.duration(reviewSummary.tracked)) tracked · "
            + "\(reviewSummary.activeDays) \(dayWord) · "
            + "\(Tokens.duration(reviewSummary.averagePerActiveDay)) average"
    }

    var reviewHasRelevantEvidence: Bool {
        reviewSummary.tracked > 0 || !reviewFocusSessions.isEmpty || !reviewLog.isEmpty
    }

    var reviewLogRowsOmitted: Int {
        max(0, reviewLogTotalEntries - reviewLog.count)
    }

    var reviewLogRowsQualification: String {
        "Showing newest \(reviewLog.count) of \(reviewLogTotalEntries) app-session rows"
    }

    var reviewAppAggregateQualification: String {
        let sessions = reviewLogTotalEntries == 1 ? "1 app session"
            : "\(reviewLogTotalEntries) app sessions"
        return "Exact full period · \(sessions)"
    }

    var reviewFocusSessionCount: Int {
        Set(reviewFocusSessions.map(\.threadID)).count
    }

    /// Only the row presentation is bounded. Summary, longest-focus, work-type
    /// and session-count evidence continue to consume `reviewFocusSessions` in
    /// full. The source array is already newest first and deterministically tied.
    var reviewFocusSessionRows: [ReviewFocusEntry] {
        Array(reviewFocusSessions.prefix(Self.maximumReviewFocusRows))
    }

    var reviewFocusRowsOmitted: Int {
        max(0, reviewFocusSessions.count - Self.maximumReviewFocusRows)
    }

    var reviewFocusRowsQualification: String {
        "Showing newest \(reviewFocusSessionRows.count) of "
            + "\(reviewFocusSessions.count) stretches"
    }

    var filteredHistoryDays: [HistoryDay] {
        let calendar = Calendar.current
        let filtered = historyFilter.apply(to: historyDays,
                                           appNamesByBundleID: historyAppNames)
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
        reviewLogTotalEntries = 0
        reviewAppGroups = []
        reviewDayTotals = [:]
        reviewSummary = PeriodRollup.empty.summary
        reviewLongestFocusSeconds = 0
        reviewLongestFocusName = nil
        reviewFocusSessions = []
        reviewWorkTypeShares = []
        reviewIntegrityNote = nil
        historyDays = []
        historyRangeStart = nil
        historyRangeEnd = nil
        historyAppNames = [:]
        historyIntegrityNotices = []
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
