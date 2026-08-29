import Foundation

/// One range of evidence-backed statements for the Insights canvas. Optional
/// values are deliberate: absence means the source did not establish a claim,
/// never that the missing measure was zero.
struct InsightSurface: Equatable {
    let range: InsightRange
    let pace: Insight?
    let rhythm: Insight?
    let quality: Insight?
    let continuity: Insight?
    private let rangeEvidence: Bool

    var hasEvidence: Bool {
        pace != nil || rhythm != nil || quality != nil || continuity != nil
    }

    var hasRangeEvidence: Bool { rangeEvidence }

    static let insufficientEvidenceCopy =
        "Keep using FocusContinuity; patterns appear once there is enough comparable history."

    static func empty(range: InsightRange) -> InsightSurface {
        InsightSurface(range: range, pace: nil, rhythm: nil,
                       quality: nil, continuity: nil, rangeEvidence: false)
    }

    /// Builds presentation copy from canonical facts only. `DailyGoal` owns the
    /// historical sample gate, `Rhythm` owns the non-zero hourly evidence,
    /// `FocusQuality` owns focus composition, and the caller supplies an
    /// optional like-for-like previous-period total.
    static func make(range: InsightRange,
                     goal: GoalProgress,
                     rhythm: [RhythmHour],
                     rhythmPeak: String?,
                     quality: FocusQuality,
                     streak: Int,
                     activeDays: Int,
                     totalDays: Int,
                     tracked: TimeInterval,
                     comparableTracked: TimeInterval?) -> InsightSurface {
        let rhythmInsight = rhythmInsight(hours: rhythm, peak: rhythmPeak)
        let qualityInsight = qualityInsight(quality)
        return InsightSurface(
            range: range,
            pace: paceInsight(goal),
            rhythm: rhythmInsight,
            quality: qualityInsight,
            continuity: continuityInsight(
                range: range,
                streak: streak,
                activeDays: activeDays,
                totalDays: totalDays,
                tracked: tracked,
                comparableTracked: comparableTracked),
            rangeEvidence: rhythmInsight != nil || qualityInsight != nil || activeDays > 0)
    }

    static func showsRangeSelector(week: InsightSurface,
                                   month: InsightSurface) -> Bool {
        week.hasRangeEvidence && month.hasRangeEvidence
    }

    private static func paceInsight(_ goal: GoalProgress) -> Insight? {
        guard let typical = goal.typicalByNow,
              let difference = goal.aheadBy else { return nil }
        let headline: String
        if difference >= 60 {
            headline = "\(Tokens.preciseDuration(difference)) ahead of your usual pace"
        } else if difference <= -60 {
            headline = "\(Tokens.preciseDuration(-difference)) behind your usual pace"
        } else {
            headline = "On your usual pace"
        }
        return Insight(
            id: "pace",
            headline: headline,
            detail: "\(Tokens.preciseDuration(goal.achieved)) focused-active today; "
                + "\(Tokens.preciseDuration(typical)) is the personal median by this local time "
                + "across at least three authoritative active days.",
            symbolName: "gauge.with.dots.needle.50percent")
    }

    private static func rhythmInsight(hours: [RhythmHour], peak: String?) -> Insight? {
        let present = hours.filter { $0.seconds > 0 }
        guard !present.isEmpty, let peak else { return nil }
        let total = present.reduce(0) { $0 + $1.seconds }
        let bucket = present.count == 1 ? "recorded hourly bucket" : "recorded hourly buckets"
        return Insight(
            id: "rhythm",
            headline: "\(peak) was the busiest verified period",
            detail: "\(Tokens.preciseDuration(total)) at the Mac across "
                + "\(present.count) \(bucket), summed from canonical tracked app usage.",
            symbolName: "waveform.path.ecg")
    }

    private static func qualityInsight(_ quality: FocusQuality) -> Insight? {
        guard quality.sessionCount > 0,
              let leading = quality.byWorkType.first,
              leading.seconds > 0,
              leading.share > 0 else { return nil }
        let percent = percentageText(leading.share)
        let sessionWord = quality.sessionCount == 1 ? "focus session" : "focus sessions"
        let supplies = quality.sessionCount == 1 ? "supplies" : "supply"
        var details = [
            "\(quality.sessionCount) recorded \(sessionWord) \(supplies) the work-type composition"
        ]
        if quality.insideSessionShare > 0 {
            details.append(
                "\(percentageText(quality.insideSessionShare)) of tracked time "
                    + "fell inside a focus session")
        }
        if quality.switchesPerSession > 0 {
            details.append(
                "\(rateText(quality.switchesPerSession)) app switches per recorded focus session")
        }
        return Insight(
            id: "quality",
            headline: "\(leading.workType.displayName) was \(percent) of focused time",
            detail: details.joined(separator: "; ") + ".",
            symbolName: "scope")
    }

    private static func percentageText(_ share: Double) -> String {
        let percentage = share * 100
        if percentage > 0 && percentage < 1 { return "<1%" }
        return "\(Int(percentage.rounded()))%"
    }

    private static func rateText(_ value: Double) -> String {
        if value > 0 && value < 0.1 { return "<0.1" }
        return String(format: "%.1f", value)
    }

    private static func continuityInsight(range: InsightRange,
                                          streak: Int,
                                          activeDays: Int,
                                          totalDays: Int,
                                          tracked: TimeInterval,
                                          comparableTracked: TimeInterval?) -> Insight? {
        guard activeDays > 0 || streak > 0 else { return nil }
        let headline: String
        if activeDays > 0 {
            let dayCount: String
            if totalDays > 0 {
                dayCount = "\(activeDays) of \(totalDays) " + (totalDays == 1 ? "day" : "days")
            } else {
                dayCount = "\(activeDays) " + (activeDays == 1 ? "day" : "days")
            }
            headline = "\(dayCount) had tracked time \(range.periodPhrase)"
        } else {
            headline = streak == 1 ? "1-day current focus streak"
                                   : "\(streak)-day current focus streak"
        }

        var details: [String] = []
        if activeDays > 0 {
            details.append("An active day here is a complete post-accuracy day with "
                           + "non-zero canonical tracked time")
        }
        if streak > 0 {
            let streakText = streak == 1 ? "the current focus streak is 1 day"
                                         : "the current focus streak is \(streak) days"
            details.append(streakText + ", using the "
                           + "\(Tokens.preciseDuration(FocusConstants.streakMinimum)) minimum")
        }
        if let comparableTracked, tracked > 0, comparableTracked > 0 {
            let difference = tracked - comparableTracked
            if abs(difference) < 60 {
                details.append("tracked time matches the like-for-like previous period")
            } else {
                details.append(
                    "\(Tokens.preciseDuration(abs(difference))) "
                        + "\(difference > 0 ? "more" : "less") tracked than the "
                        + "like-for-like previous period")
            }
        }
        return Insight(id: "continuity", headline: headline,
                       detail: details.joined(separator: "; ") + ".",
                       symbolName: "link")
    }
}

extension SessionStore {
    func setInsightsVisible(_ visible: Bool) {
        insightsVisible = visible
        if visible && insightsRefreshPending { refreshInsights() }
    }

    func refreshInsights() {
        guard let usage else {
            insightWeekSurface = .empty(range: .week)
            insightMonthSurface = .empty(range: .month)
            insightsRefreshPending = false
            return
        }
        let calendar = Calendar.current
        let moment = now()
        let snapshot = effectiveUsageSnapshot ?? AppUsageSnapshot(archive: usage)
        let goal = DailyGoal(
            archive: engine.archive,
            goal: engine.store.dailyGoal,
            usage: snapshot.sessions,
            usageAccurateFrom: snapshot.accurateFrom,
            running: engine.runningSpan,
            runningWork: engine.elapsedToday(),
            calendar: calendar,
            now: { moment }).progress()
        let stats = DashboardStats(sessions: engine.archive, usage: usage,
                                   usageSnapshot: snapshot,
                                   calendar: calendar, now: { moment })
        let periodStats = PeriodStats(sessions: engine.archive, usage: usage,
                                      usageSnapshot: snapshot,
                                      calendar: calendar, now: { moment })
        insightWeekSurface = makeInsightSurface(
            range: .week, goal: goal, stats: stats, periodStats: periodStats,
            snapshot: snapshot, moment: moment, calendar: calendar)
        insightMonthSurface = makeInsightSurface(
            range: .month, goal: goal, stats: stats, periodStats: periodStats,
            snapshot: snapshot, moment: moment, calendar: calendar)
        insightsRefreshPending = false
    }

    var insightsShowsRangeSelector: Bool {
        InsightSurface.showsRangeSelector(week: insightWeekSurface,
                                          month: insightMonthSurface)
    }

    func insightSurface(for requestedRange: InsightRange) -> InsightSurface {
        let requested = requestedRange == .week ? insightWeekSurface : insightMonthSurface
        if !insightsShowsRangeSelector {
            if insightWeekSurface.hasRangeEvidence { return insightWeekSurface }
            if insightMonthSurface.hasRangeEvidence { return insightMonthSurface }
        }
        if requested.hasEvidence { return requested }
        if insightWeekSurface.hasEvidence { return insightWeekSurface }
        if insightMonthSurface.hasEvidence { return insightMonthSurface }
        return requested
    }

    private func makeInsightSurface(range: InsightRange,
                                    goal: GoalProgress,
                                    stats: DashboardStats,
                                    periodStats: PeriodStats,
                                    snapshot: AppUsageSnapshot,
                                    moment: Date,
                                    calendar: Calendar) -> InsightSurface {
        let period = range.trackingPeriod
        let rollup = periodStats.rollup(for: period, containing: moment)
        let today = calendar.startOfDay(for: moment)
        let elapsedDays = rollup.days.filter { $0.date <= today }
        let firstCompleteAccurateDay = calendar.date(
            byAdding: .day, value: 1,
            to: calendar.startOfDay(for: snapshot.accurateFrom))
        let authoritativeDays = elapsedDays.filter { day in
            guard let firstCompleteAccurateDay else { return false }
            return day.date >= firstCompleteAccurateDay
        }
        let activeDays = authoritativeDays.filter { $0.tracked > 0 }.count
        let rhythm = insightRhythm(stats: stats, days: authoritativeDays,
                                   calendar: calendar)
        let quality = insightQuality(stats: stats, days: elapsedDays,
                                     moment: moment, calendar: calendar)
        let comparable = comparablePreviousTracked(
            period: period, periodStats: periodStats, stats: stats,
            snapshot: snapshot, moment: moment, calendar: calendar)
        return InsightSurface.make(
            range: range,
            goal: goal,
            rhythm: rhythm.hours,
            rhythmPeak: rhythm.peak,
            quality: quality,
            streak: streak,
            activeDays: activeDays,
            totalDays: authoritativeDays.count,
            tracked: authoritativeDays.reduce(0) { $0 + $1.tracked },
            comparableTracked: comparable)
    }

    private func insightRhythm(stats: DashboardStats,
                               days: [PeriodDay],
                               calendar: Calendar) -> (hours: [RhythmHour], peak: String?) {
        var byClockHour: [Int: TimeInterval] = [:]
        for day in days {
            guard let bounds = SessionRecord.dayBounds(day.date, calendar: calendar) else {
                continue
            }
            for hour in Rhythm.hours(segments: stats.timeline(for: day.date),
                                     window: (bounds.start, bounds.end),
                                     calendar: calendar) where hour.seconds > 0 {
                byClockHour[calendar.component(.hour, from: hour.hour), default: 0]
                    += hour.seconds
            }
        }
        var reference = DateComponents()
        reference.calendar = calendar
        reference.timeZone = calendar.timeZone
        reference.year = 2001
        reference.month = 1
        reference.day = 15
        let start = calendar.date(from: reference) ?? Date(timeIntervalSince1970: 0)
        let hours = (0..<24).compactMap { hour -> RhythmHour? in
            guard let date = calendar.date(byAdding: .hour, value: hour, to: start) else {
                return nil
            }
            return RhythmHour(hour: date,
                              seconds: byClockHour[hour] ?? 0,
                              colorIndex: 6)
        }
        let peak = Rhythm.peakLabel(hours) { Self.insightHourFormatter.string(from: $0) }
        return (hours, peak)
    }

    private func insightQuality(stats: DashboardStats,
                                days: [PeriodDay],
                                moment: Date,
                                calendar: Calendar) -> FocusQuality {
        var typeSeconds: [WorkType: TimeInterval] = [:]
        var insideSeconds: TimeInterval = 0
        var trackedSeconds: TimeInterval = 0
        var switches: Double = 0
        var sessions = 0
        var qualityStats = stats
        qualityStats.activeWorkType = engine.activeWorkType
        for day in days {
            let running = engine.state != .idle && calendar.isDate(day.date, inSameDayAs: moment)
                ? engine.elapsedToday() : nil
            let quality = qualityStats.focusQuality(for: day.date, runningSeconds: running)
            let tracked = stats.trackedTotal(for: day.date)
            trackedSeconds += tracked
            insideSeconds += quality.insideSessionShare * tracked
            switches += quality.switchesPerSession * Double(quality.sessionCount)
            sessions += quality.sessionCount
            for share in quality.byWorkType {
                typeSeconds[share.workType, default: 0] += share.seconds
            }
        }
        let typeTotal = typeSeconds.values.reduce(0, +)
        let shares = WorkType.allCases.compactMap { type -> WorkTypeShare? in
            guard let seconds = typeSeconds[type], seconds > 0 else { return nil }
            return WorkTypeShare(workType: type, seconds: seconds,
                                 share: typeTotal > 0 ? seconds / typeTotal : 0)
        }
        .sorted { $0.seconds > $1.seconds }
        return FocusQuality(
            byWorkType: shares,
            insideSessionShare: trackedSeconds > 0 ? insideSeconds / trackedSeconds : 0,
            switchesPerSession: sessions > 0 ? switches / Double(sessions) : 0,
            sessionCount: sessions)
    }

    /// Compares the current calendar range-to-now with the same local day and
    /// clock position in the previous range. Full previous periods are not
    /// compared with partial current ones, and neither side crosses the usage
    /// accuracy epoch.
    private func comparablePreviousTracked(period: TrackingPeriod,
                                           periodStats: PeriodStats,
                                           stats: DashboardStats,
                                           snapshot: AppUsageSnapshot,
                                           moment: Date,
                                           calendar: Calendar) -> TimeInterval? {
        let currentBounds = periodStats.bounds(for: period, containing: moment)
        guard let previousReference = calendar.date(byAdding: .second, value: -1,
                                                    to: currentBounds.start) else { return nil }
        let previousBounds = periodStats.bounds(for: period, containing: previousReference)
        guard let firstCompleteAccurateDay = calendar.date(
            byAdding: .day, value: 1,
            to: calendar.startOfDay(for: snapshot.accurateFrom)),
              currentBounds.start >= firstCompleteAccurateDay,
              previousBounds.start >= firstCompleteAccurateDay else { return nil }

        let currentDay = calendar.startOfDay(for: moment)
        let dayOffset = calendar.dateComponents([.day],
                                                from: currentBounds.start,
                                                to: currentDay).day ?? 0
        guard let matchingDay = calendar.date(byAdding: .day, value: dayOffset,
                                              to: previousBounds.start),
              matchingDay < previousBounds.end else { return nil }
        var time = calendar.dateComponents([.hour, .minute, .second], from: moment)
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        let cutoff = min(
            previousBounds.end,
            calendar.nextDate(after: matchingDay.addingTimeInterval(-1),
                              matching: time,
                              matchingPolicy: .nextTime,
                              repeatedTimePolicy: .first,
                              direction: .forward) ?? previousBounds.end)
        guard cutoff > previousBounds.start else { return nil }

        var total: TimeInterval = 0
        var cursor = previousBounds.start
        var visited = 0
        while cursor < cutoff && visited < 40 {
            visited += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            if next <= cutoff {
                total += stats.trackedTotal(for: cursor)
            } else {
                total += stats.timeline(for: cursor).reduce(0) { result, segment in
                    let start = max(segment.start, cursor)
                    let end = min(segment.end, cutoff)
                    return end > start ? result + end.timeIntervalSince(start) : result
                }
            }
            cursor = next
        }
        return total
    }

    private static let insightHourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "ha"
        return formatter
    }()
}

private extension InsightRange {
    var trackingPeriod: TrackingPeriod {
        switch self {
        case .week: return .week
        case .month: return .month
        }
    }

    var periodPhrase: String {
        switch self {
        case .week: return "this week"
        case .month: return "this month"
        }
    }
}
