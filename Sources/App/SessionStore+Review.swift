import Foundation

/// One archive focus stretch clipped to the selected Review period. This is a
/// read model only; its source `SessionRecord` is never edited or repaired.
struct ReviewFocusEntry: Identifiable, Equatable {
    /// Presentation identity is namespaced so a legacy record whose ID equals
    /// its thread cannot collide with that thread's live projection.
    let id: String
    /// Durable provenance remains available without becoming the view identity.
    let sourceRecordID: UUID?
    let threadID: UUID
    let name: String
    let workType: WorkType
    let start: Date
    let end: Date
    let seconds: TimeInterval
}

/// One selected Review day, projected from values Review has already published.
/// `day` is the canonical History row and remains the displayed source of
/// truth, so the inline detail can never disagree with the chart or the table
/// the day was selected from. Nothing here recomputes tracked or focused time.
struct ReviewDayDetail: Equatable {
    let day: HistoryDay
    let periodDay: PeriodDay?
    let appEntries: [LogEntry]
    let focusEntries: [ReviewFocusEntry]
}

/// The Review read model. It composes existing canonical period/accounting
/// helpers and publishes presentation-ready values; no archive mutation or
/// historical repair is possible from this surface.
extension SessionStore {
    private static let maximumReviewFocusRows = 500

    func setReviewVisible(_ visible: Bool) {
        reviewVisible = visible
        if visible && (reviewRefreshPending || reviewLiveTailRefreshPending) { refreshReview() }
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
    func refreshReview(period requestedPeriod: TrackingPeriod? = nil,
                       rebuildingHistory: Bool = true) {
        withRefreshTransaction {
            rebuildReview(period: requestedPeriod, rebuildingHistory: rebuildingHistory)
        }
    }

    private func rebuildReview(period requestedPeriod: TrackingPeriod?, rebuildingHistory: Bool) {
        // Consume requests before publication. A synchronous observer may queue
        // a new mutation while these values publish; never erase that request
        // at the end of the rebuild.
        reviewRefreshPending = false
        reviewLiveTailRefreshPending = false
        let revision = evidenceRevision
        let canPatch = !rebuildingHistory && reviewEvidenceRevision == revision
        reviewEvidenceRevision = revision
        if let requestedPeriod, requestedPeriod != .day { reviewPeriod = requestedPeriod }
        guard let usage else {
            clearReviewData()
            return
        }

        // A ticker-only live tail changes at most today's evidence. Keep the
        // stable period/index data and replace that one day rather than walking
        // every day and every history row on the main actor.
        if canPatch, requestedPeriod == nil, !reviewDays.isEmpty {
            refreshReviewLiveTail(usage: usage)
            return
        }

        let calendar = Calendar.current
        let snapshot = effectiveUsageSnapshot ?? AppUsageSnapshot(archive: usage)
        let anchor = reviewAnchor ?? calendar.startOfDay(for: now())
        reviewAnchor = anchor

        refreshHistory(snapshot: snapshot, calendar: calendar, fully: true)

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
        reviewEntriesByDay = rollup.entriesByDay
        reviewLogTotalEntries = rollup.totalLogEntries
        reviewAppGroups = rollup.exactAppGroups
        reviewDayTotals = rollup.dayTotals
        reviewSummary = rollup.summary
        reviewWorkTypeShares = Self.reviewWorkTypes(from: rollup.days)
        // The multi-day form, so a thread crossing midnight is counted once.
        reviewQuality = DashboardStats(sessions: engine.archive, usage: usage)
            .focusQuality(for: rollup.days.map(\.date))

        let bounds = periodStats.bounds(for: reviewPeriod, containing: anchor)
        reviewFocusSessions = reviewFocusEntries(
            in: DateInterval(start: bounds.start, end: bounds.end))
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
        noteReviewReadModelRebuild()
    }

    /// Exact day-scoped usage entries. The already-published period index is
    /// reused where it applies; a reachable History row outside that period is
    /// rebuilt from the same effective usage snapshot instead of losing detail.
    private func reviewAppEntries(on day: Date,
                                  calendar: Calendar) -> [LogEntry] {
        if let published = reviewEntriesByDay.first(where: { key, _ in
            calendar.isDate(key, inSameDayAs: day)
        })?.value {
            return published
        }
        guard let usage else { return [] }
        let stats = DashboardStats(sessions: engine.archive, usage: usage,
                                   usageSnapshot: effectiveUsageSnapshot,
                                   calendar: calendar, now: now)
        var entries: [LogEntry] = []
        for rank in stats.rankedApps(for: day) {
            entries.append(contentsOf: stats.sessions(for: day, bundleID: rank.bundleID)
                .map { LogEntry(session: $0, day: calendar.startOfDay(for: day)) })
        }
        return entries.sorted { left, right in
            if left.session.start != right.session.start {
                return left.session.start > right.session.start
            }
            if left.session.end != right.session.end {
                return left.session.end > right.session.end
            }
            return left.session.id > right.session.id
        }
    }

    /// Focus stretches for an arbitrary Review/History day. Archive entries
    /// retain their stored identifiers; an active stretch is a read-only live
    /// projection keyed by its real thread identity and is never persisted.
    private func reviewFocusEntries(in interval: DateInterval) -> [ReviewFocusEntry] {
        var entries = engine.archive.records.compactMap { record -> ReviewFocusEntry? in
            guard record.workType.countsAsFocus else { return nil }
            let seconds = record.workSeconds(in: (start: interval.start, end: interval.end))
            guard seconds > 0 else { return nil }
            return ReviewFocusEntry(
                id: "archive-\(record.id.uuidString)",
                sourceRecordID: record.id,
                threadID: record.threadID,
                name: record.name.isEmpty ? record.workType.displayName : record.name,
                workType: record.workType,
                start: max(record.start, interval.start),
                end: min(record.end, interval.end),
                seconds: seconds)
        }
        if let running = storyRunningSpan {
            let seconds = storyRunningFocusSeconds(in: interval)
            if seconds > 0 {
                entries.append(ReviewFocusEntry(
                    id: "live-\(engine.activeThreadID.uuidString)",
                    sourceRecordID: nil,
                    threadID: engine.activeThreadID,
                    name: engine.sessionName.isEmpty
                        ? engine.activeWorkType.displayName : engine.sessionName,
                    workType: engine.activeWorkType,
                    start: max(running.start, interval.start),
                    end: min(running.end, interval.end),
                    seconds: seconds))
            }
        }
        return entries.sorted { left, right in
            left.start == right.start ? left.id > right.id
                                      : left.start > right.start
        }
    }

    /// Stable all-history indexing is rebuilt on evidence/navigation changes.
    /// A one-second live tail replaces its current-day row only, preserving the
    /// open History sheet without repeatedly walking every archived day.
    private func refreshHistory(snapshot: AppUsageSnapshot, calendar: Calendar,
                                fully: Bool) {
        if fully {
            let previousNewest = historyDays.first?.date
            let previousOldest = historyDays.last?.date
            let rebuilt = HistoryStats.build(sessionRecords: engine.archive.records,
                                             usage: snapshot.sessions, calendar: calendar)
            historyDays = storyHistoryDaysIncludingDecisionReceipts(
                storyHistoryDaysIncludingRunning(rebuilt.days), calendar: calendar)
            historyIntegrityNotices = historyNotices(for: snapshot, rebuilt: rebuilt)
            maintainHistoryRange(previousNewest: previousNewest,
                                 previousOldest: previousOldest, calendar: calendar)
            noteHistoryIndexRebuild()
            return
        }
        let previousNewest = historyDays.first?.date
        let previousOldest = historyDays.last?.date
        let interval = liveHistoryBounds(calendar: calendar)
        let rebuilt = HistoryStats.build(
            sessionRecords: engine.archive.records.filter { $0.end > interval.start && $0.start < interval.end },
            usage: snapshot.sessions.filter { $0.end > interval.start && $0.start < interval.end },
            calendar: calendar)
        // The builder deliberately clips each source record across all of its
        // days. Keep only the affected keys, then replace them exactly once.
        let current = storyHistoryDaysIncludingDecisionReceipts(
            storyHistoryDaysIncludingRunning(rebuilt.days), calendar: calendar).filter {
            $0.date >= interval.start && $0.date < interval.end
        }
        historyDays.removeAll { $0.date >= interval.start && $0.date < interval.end }
        historyDays.append(contentsOf: current)
        historyDays.sort { $0.date > $1.date }
        maintainHistoryRange(previousNewest: previousNewest,
                             previousOldest: previousOldest, calendar: calendar)
    }

    /// Every day touched by a changing live projection, not merely today. A
    /// paused overnight session can redistribute its clipped credit across both
    /// dates; a tracker tail can also start before midnight.
    private func liveHistoryBounds(calendar: Calendar) -> DateInterval {
        let moment = now()
        let starts = (tracker?.usageOverlaySessions() ?? []).map(\.start)
            + [storyRunningSpan?.start ?? moment, moment]
        let first = calendar.startOfDay(for: starts.min() ?? moment)
        let end = calendar.date(byAdding: .day, value: 1,
                                to: calendar.startOfDay(for: moment)) ?? moment
        return DateInterval(start: min(first, end), end: end)
    }

    private func historyNotices(for snapshot: AppUsageSnapshot,
                                rebuilt: HistoryBuildResult) -> [String] {
        var notices: [String] = []
        if snapshot.sessions.contains(where: { $0.end > $0.start && $0.start < snapshot.accurateFrom }) {
            notices.append("History includes preserved legacy app usage from before "
                           + "\(Tokens.longDate(snapshot.accurateFrom)); it may include unattended time.")
        }
        if rebuilt.droppedUsageSpans > 0 || rebuilt.droppedFocusSpans > 0 || rebuilt.droppedRestSpans > 0 {
            var dropped: [String] = []
            if rebuilt.droppedUsageSpans > 0 { dropped.append("\(rebuilt.droppedUsageSpans) app-usage records") }
            if rebuilt.droppedFocusSpans > 0 { dropped.append("\(rebuilt.droppedFocusSpans) focus records") }
            if rebuilt.droppedRestSpans > 0 { dropped.append("\(rebuilt.droppedRestSpans) rest records") }
            notices.append("History omitted \(dropped.joined(separator: " and ")) from derived day rows because each spans at least \(HistoryStats.maximumCalendarDaysPerRecord) calendar days. Source records remain preserved in local data.")
        }
        return notices
    }

    private func refreshReviewLiveTail(usage: AppUsageArchive) {
        let calendar = Calendar.current
        let snapshot = effectiveUsageSnapshot ?? AppUsageSnapshot(archive: usage)
        let anchor = reviewAnchor ?? calendar.startOfDay(for: now())
        reviewAnchor = anchor
        let periodStats = PeriodStats(sessions: engine.archive, usage: usage,
                                      usageSnapshot: snapshot, calendar: calendar, now: now)
        let bounds = periodStats.bounds(for: reviewPeriod, containing: anchor)
        refreshHistory(snapshot: snapshot, calendar: calendar, fully: false)
        let affected = liveHistoryBounds(calendar: calendar)
        let changedDays = reviewDays.map(\.date).filter {
            $0 >= affected.start && $0 < affected.end
        }
        guard !changedDays.isEmpty else {
            noteReviewReadModelRebuild()
            return
        }

        for date in changedDays {
            let current = periodStats.rollup(for: .day, containing: date)
            guard let day = current.days.first else { continue }
            let priorEntries = reviewEntriesByDay[date] ?? []
            let newEntries = current.entriesByDay[date] ?? []
            if let index = reviewDays.firstIndex(where: { $0.date == date }) {
                reviewDays[index] = day
            }
            reviewEntriesByDay[date] = newEntries
            reviewDayTotals[date] = current.dayTotals[date] ?? 0
            reviewLogTotalEntries += newEntries.count - priorEntries.count
            for entry in newEntries { historyAppNames[entry.session.bundleID] = entry.session.appName }
        }

        let allEntries = reviewEntriesByDay.values.flatMap { $0 }
        reviewLog = Array(allEntries.sorted { $0.session.start > $1.session.start }.prefix(500))
        reviewAppGroups = PeriodStats.appGroups(from: allEntries)
        let tracked = reviewDays.reduce(0) { $0 + $1.tracked }
        let active = reviewDays.filter { $0.tracked > 0 }
        reviewSummary = PeriodSummary(
            tracked: tracked, activeDays: active.count, totalDays: reviewDays.count,
            averagePerActiveDay: active.isEmpty ? 0 : tracked / Double(active.count),
            longest: allEntries.map(\.session).max { $0.attended < $1.attended })
        reviewWorkTypeShares = Self.reviewWorkTypes(from: reviewDays)

        // Period rows retain period bounds. Re-slicing an overnight entry to
        // today loses its prior-day work, even if the day index stays correct.
        reviewFocusSessions = reviewFocusEntries(in: DateInterval(start: bounds.start, end: bounds.end))
        let longestFocus = reviewFocusSessions.max { left, right in
            left.seconds == right.seconds ? left.start > right.start : left.seconds < right.seconds
        }
        reviewLongestFocusSeconds = longestFocus?.seconds ?? 0
        reviewLongestFocusName = longestFocus?.name
        noteReviewReadModelRebuild()
    }

    /// The selected day's evidence, or nil when Review has no canonical History
    /// row for it. A History selection may be outside the currently shown
    /// Week/Month, so its app and focus entries are rebuilt from the same
    /// authoritative snapshot rather than silently appearing empty.
    func reviewDayDetail(for date: Date, calendar: Calendar = .current) -> ReviewDayDetail? {
        let day = calendar.startOfDay(for: date)
        guard let historyDay = historyDays.first(where: {
            calendar.isDate($0.date, inSameDayAs: day)
        }) else { return nil }
        let periodDay = reviewDays.first { calendar.isDate($0.date, inSameDayAs: day) }
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let dayInterval = DateInterval(start: day, end: dayEnd)
        let appEntries = reviewAppEntries(on: day, calendar: calendar)
        let focusEntries = reviewFocusEntries(in: dayInterval)
        return ReviewDayDetail(day: historyDay,
                               periodDay: periodDay,
                               appEntries: appEntries,
                               focusEntries: focusEntries)
    }

    /// Whether the selected day still belongs to what Review is showing. Week
    /// and Month answer from the period's own days; History answers from the
    /// filtered rows, so a filter that hides the row also closes its detail.
    func reviewDayIsAvailable(_ date: Date,
                              section: ReviewSection,
                              calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        switch section {
        case .history:
            return filteredHistoryDays.contains { calendar.isDate($0.date, inSameDayAs: day) }
        case .week, .month:
            return reviewDays.contains { calendar.isDate($0.date, inSameDayAs: day) }
        }
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

    /// The period's strongest day by focused time, or nil when nothing was
    /// focused at all.
    var reviewBestDay: (day: Date, focused: TimeInterval)? {
        let ranked = reviewDays
            .map { (day: $0.date, focused: storyFocusedSeconds(on: $0.date)) }
            .filter { $0.focused > 0 }
        return ranked.max { $0.focused < $1.focused }
    }

    /// The first day of the shown Review period — what the month grid lays out.
    var reviewPeriodStart: Date {
        let calendar = Calendar.current
        let anchor = reviewAnchor ?? Date()
        let unit: Calendar.Component = reviewPeriod == .week ? .weekOfYear : .month
        return calendar.dateInterval(of: unit, for: anchor)?.start
            ?? calendar.startOfDay(for: anchor)
    }

    /// Focused seconds across the shown period, including the live local-day
    /// projection used by Story's Day and Month cell facts.
    var reviewFocusedSeconds: TimeInterval {
        storyFocusSummary.focused
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
        return Tokens.dateRange(bounds.start, finalDay, now: now(), calendar: calendar)
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
        reviewSummary.tracked > 0 || storyFocusSummary.focused > 0 || !reviewLog.isEmpty
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
        reviewEntriesByDay = [:]
        reviewLogTotalEntries = 0
        reviewAppGroups = []
        reviewDayTotals = [:]
        reviewSummary = PeriodRollup.empty.summary
        reviewLongestFocusSeconds = 0
        reviewLongestFocusName = nil
        reviewFocusSessions = []
        reviewWorkTypeShares = []
        reviewQuality = FocusQuality(byWorkType: [], insideSessionShare: 0,
                                     switchesPerSession: 0, sessionCount: 0)
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
