import SwiftUI

/// Per-day series behind the KPI cards' sparklines. One array per card, in
/// the same day order, so the cards can be laid out from one refresh.
struct KPISparks: Equatable {
    var tracked: [Double] = []
    var focused: [Double] = []
    var sessions: [Double] = []
    var quality: [Double] = []
}

// The dashboard's half of the store: timeline inspection, per-app history, the
// day selection and the thread actions. Split from `SessionStore.swift` for
// size only — same object, same rules.
extension SessionStore {

    // MARK: - The running thread

    /// Earlier stretches of the running thread, today. A break splits the
    /// record but not the work, so the clock carries them.
    func refreshThread() {
        guard engine.state != .idle else {
            threadBaseSeconds = 0
            threadSegments = 0
            threadStartedAt = nil
            return
        }
        let today = Date()
        let earlier = engine.archive.records(on: today).filter {
            $0.threadID == engine.activeThreadID && $0.workType.countsAsFocus
        }
        threadBaseSeconds = earlier.reduce(0) { $0 + $1.workSeconds(on: today, calendar: .current) }
        threadSegments = earlier.count + 1
        threadStartedAt = min(earlier.map(\.start).min() ?? engine.sessionStartDate,
                              engine.sessionStartDate)
    }

    /// The title band's second line for a past day: `Wednesday 20 August · 4
    /// sessions · goal met`, from that day's figures rather than today's.
    var selectedDaySummary: String {
        var parts = [Tokens.longDate(selectedDay)]
        let count = sessionsForSelectedDay
        if count > 0 { parts.append(count == 1 ? "1 session" : "\(count) sessions") }
        if focusedForSelectedDay > 0 {
            parts.append(focusedForSelectedDay >= engine.store.dailyGoal
                         ? "goal met" : "\(Tokens.duration(focusedForSelectedDay)) focused")
        } else if trackedForSelectedDay > 0 {
            parts.append("no focus sessions")
        }
        return parts.joined(separator: " · ")
    }

    /// `6h 55m on this today · 6 stretches since 9:10 am`, or nil for a first
    /// stretch. The thread's total lives here, under the clock, so it can
    /// never be mistaken for the timer — which is the current stretch.
    var threadSummaryLine: String? {
        guard state != .idle, threadSegments > 1, let began = threadStartedAt else { return nil }
        let at = Tokens.timeOfDay(began).replacingOccurrences(of: "since ", with: "")
        return "\(Tokens.duration(threadElapsed)) on this today · "
            + "\(threadSegments) stretches since \(at)"
    }

    /// What the away card says instead of the bare "still running": which work
    /// carries on and from where — or, when the user came back into different
    /// work, that the old thread waits in Continue today. Nil when idle.
    var continuationNote: String? {
        guard state != .idle else { return nil }
        if !engine.returnKeepsThread {
            return "Not counted. You're in \(engine.currentAppName) now — "
                + "\(activeIntent) stays in Continue today."
        }
        return "Not counted. \(activeIntent) continues — "
            + "\(Tokens.duration(threadElapsed)) so far."
    }

    /// Whether an app belongs to the running piece of work: its primary app or
    /// one of its side apps today. The engine asks when the user returns from
    /// an absence in a different app than they left in.
    func runningThreadUses(_ bundleID: String?) -> Bool {
        guard let bundleID,
              let thread = threadsToday.first(where: \.isRunning) else { return true }
        let apps = threadApps(thread)
        return apps.primary?.bundleID == bundleID
            || apps.side.contains { $0.bundleID == bundleID }
    }

    // MARK: - Periods and the selected day

    /// Bounds of the selected period, for charts that must show empty days too.
    var periodBounds: (start: Date, end: Date)? {
        guard let usage else { return nil }
        let bounds = PeriodStats(sessions: engine.archive, usage: usage)
            .bounds(for: period, containing: selectedDay)
        // `end` is exclusive; charts want the last day that exists.
        return (bounds.start, bounds.end.addingTimeInterval(-1))
    }

    var period: TrackingPeriod {
        get { engine.store.trackingPeriod }
        set {
            engine.store.trackingPeriod = newValue
            refreshDashboard()
        }
    }

    /// Figures for the stat band, shaped by the selected period. Every card
    /// carries a context line; a bare number was the old row's failure.
    var statFigures: [StatFigure] {
        switch period {
        case .day:
            let sessions = isToday ? sessionsToday : sessionsForSelectedDay
            let focused = isToday ? todayTotal : focusedForSelectedDay
            let longest = isToday ? longestToday : longestForSelectedDay
            let longestName = isToday ? longestNameToday : longestNameForSelectedDay
            let tracked = trackedForSelectedDay
            // `trackedYesterday` is the day before the *selected* day.
            let delta = SessionStore.deltaLine(tracked, against: trackedYesterday,
                                               label: isToday ? "yesterday" : "the day before")
            let top = focusQuality.byWorkType.first
            // The first stretch's real start, not the hour-snapped window edge.
            let since = timelineSegments.first.map { Tokens.timeOfDay($0.start) }
            if let session = selectedSession {
                // Narrowed to one session: the two time figures are its own; the
                // count and the quality stay the day's, because a session has
                // no count and its quality is the day's to judge.
                let range = Tokens.timeRange(session.start, session.end)
                return [
                    StatFigure(label: "Tracked", value: Tokens.duration(sessionTracked),
                               detail: "hands-on inside this session",
                               spark: sparks.tracked, sparkTint: Tokens.Palette.app(rank: 0),
                               symbol: "clock", badge: "this session",
                               badgeTint: .accentColor),
                    StatFigure(label: "Focused", value: Tokens.duration(session.worked),
                               detail: (session.stretches == 1 ? "1 stretch · " : "\(session.stretches) stretches · ") + range,
                               spark: sparks.focused, sparkTint: .accentColor,
                               symbol: "scope", badge: session.name.isEmpty ? session.workType.displayName : session.name,
                               badgeTint: .accentColor),
                    StatFigure(label: "Sessions", value: "\(sessions)",
                               detail: longestName,
                               spark: sparks.sessions, sparkTint: Tokens.Palette.app(rank: 2),
                               symbol: "list.bullet.rectangle",
                               badge: longest > 0 ? "longest \(Tokens.preciseDuration(longest))" : nil),
                    StatFigure(label: "Quality",
                               value: top.map { "\(Int(($0.share * 100).rounded()))%" } ?? "—",
                               detail: focusQuality.sessionCount > 0
                                   ? String(format: "%.1f switches / stretch",
                                            focusQuality.switchesPerSession)
                                   : nil,
                               spark: sparks.quality, sparkTint: Tokens.Palette.app(rank: 3),
                               symbol: "sparkles",
                               badge: top?.workType.displayName)
                ]
            }
            return [
                // Label · badge / value / chart / footer — one anatomy per card.
                StatFigure(label: "Tracked", value: Tokens.duration(tracked),
                           detail: tracked > 0 ? since : nil,
                           spark: sparks.tracked, sparkTint: Tokens.Palette.app(rank: 0),
                           symbol: "clock",
                           badge: delta?.text,
                           badgeTint: delta?.up == true ? Tokens.Palette.app(rank: 1) : nil),
                StatFigure(label: "Focused", value: Tokens.duration(focused),
                           detail: sessions > 0
                               ? (sessions == 1 ? "in 1 focus session" : "in \(sessions) focus sessions")
                               : nil,
                           spark: sparks.focused, sparkTint: .accentColor,
                           symbol: "scope",
                           // Unclamped on purpose: a session counts reading and
                           // thinking, hands-on time does not, so focused can
                           // exceed tracked — and "100%" would hide that.
                           badge: tracked > 0 && focused > 0
                               ? "\(Int((focused / tracked * 100).rounded()))% of tracked"
                               : nil),
                StatFigure(label: "Sessions", value: "\(sessions)",
                           detail: longestName,
                           spark: sparks.sessions, sparkTint: Tokens.Palette.app(rank: 2),
                           symbol: "list.bullet.rectangle",
                           badge: longest > 0 ? "longest \(Tokens.preciseDuration(longest))" : nil),
                StatFigure(label: "Quality",
                           value: top.map { "\(Int(($0.share * 100).rounded()))%" } ?? "—",
                           detail: focusQuality.sessionCount > 0
                               ? String(format: "%.1f switches / stretch",
                                        focusQuality.switchesPerSession)
                               : nil,
                           spark: sparks.quality, sparkTint: Tokens.Palette.app(rank: 3),
                           symbol: "sparkles",
                           badge: top?.workType.displayName)
            ]
        case .week, .month:
            let delta = SessionStore.deltaLine(periodSummary.tracked,
                                               against: previousPeriodTracked,
                                               label: period == .week ? "last week" : "last month")
            return [
                StatFigure(label: "Tracked", value: Tokens.duration(periodSummary.tracked),
                           detail: periodSummary.activeDays > 0
                               ? "across \(periodSummary.activeDays) active days" : nil,
                           spark: sparks.tracked, sparkTint: Tokens.Palette.app(rank: 0),
                           symbol: "clock",
                           badge: delta?.text,
                           badgeTint: delta?.up == true ? Tokens.Palette.app(rank: 1) : nil),
                StatFigure(label: "Active days",
                           value: "\(periodSummary.activeDays) of \(periodSummary.totalDays)",
                           detail: period == .week ? "this week" : "this month",
                           symbol: "calendar"),
                // No sparkline here: the value is tracked time per active day,
                // and the only per-day series that matches is the one already
                // under Tracked. A focused-time strip under it read as the same
                // measure and was not.
                StatFigure(label: "Average / day",
                           value: Tokens.duration(periodSummary.averagePerActiveDay),
                           detail: "across active days",
                           symbol: "chart.bar"),
                StatFigure(label: "Longest stretch",
                           value: periodSummary.longest.map {
                               Tokens.preciseDuration($0.attended)
                           } ?? "—",
                           detail: periodSummary.longest.map {
                               Tokens.timeRange($0.start, $0.end)
                           },
                           symbol: "arrow.up.right",
                           badge: periodSummary.longest?.appName)
            ]
        }
    }

    /// What each day of the month containing `date` amounted to, keyed by start
    /// of day: tracked from the month rollup, focused and sessions from the
    /// archive. Built once per shown month, when the calendar asks.
    func dayFacts(inMonthOf date: Date) -> [Date: DayFacts] {
        guard let usage else { return [:] }
        let calendar = Calendar.current
        let days = PeriodStats(sessions: engine.archive, usage: usage)
            .days(for: .month, containing: date)
        var facts: [Date: DayFacts] = [:]
        for day in days {
            let key = calendar.startOfDay(for: day.date)
            let focused = engine.archive.workSeconds(on: key)
            let sessions = engine.archive.threadCount(on: key)
            if day.tracked > 0 || focused > 0 || sessions > 0 {
                facts[key] = DayFacts(tracked: day.tracked, focused: focused, sessions: sessions)
            }
        }
        return facts
    }

    /// The day's recorded breaks, for the timeline to name its gaps.
    func breakRecords(on day: Date) -> [SessionRecord] {
        engine.archive.records(on: day).filter { $0.workType == .breakTime }
    }

    /// Rows for the App share card: the day's ranks, or the period's groups
    /// in the same shape so one list view serves both.
    var appShareRanks: [AppRank] {
        if selectedSession != nil { return sessionAppRanks }
        if period == .day { return rankedApps }
        return periodAppGroups.prefix(8).map {
            AppRank(bundleID: $0.bundleID, appName: $0.appName, total: $0.total,
                    share: $0.share, longest: $0.longest)
        }
    }

    /// `+3h 5m vs yesterday`, or nil when there is no baseline — a delta
    /// against nothing is not information.
    static func deltaLine(_ value: TimeInterval, against baseline: TimeInterval,
                          label: String) -> (text: String, up: Bool)? {
        guard baseline > 0, value > 0 else { return nil }
        let delta = value - baseline
        guard abs(delta) >= 60 else { return ("same as \(label)", false) }
        return ((delta > 0 ? "+" : "−") + Tokens.duration(abs(delta)) + " vs \(label)",
                delta > 0)
    }

    /// What today's longest focus session was: the running one if it leads,
    /// else the archived record's intent. Nil when nothing has run.
    var longestNameToday: String? {
        let today = Date()
        let archived = engine.archive.longestThread(on: today)
        // The running thread's whole day: its archived stretches plus the live one.
        let running = engine.archive.threadWork(engine.activeThreadID, on: today) + engine.elapsedToday()
        if state != .idle, running > 0, running >= (archived?.seconds ?? 0) {
            return engine.sessionName.isEmpty ? engine.activeWorkType.displayName : engine.sessionName
        }
        guard let archived else { return nil }
        return archived.name.isEmpty ? archived.workType.displayName : archived.name
    }

    /// Calendar day-stepping, not 86 400-second arithmetic: on the two days a
    /// year that are 23 or 25 hours long, subtracting seconds lands the label
    /// on the wrong day for anyone browsing near midnight.
    var selectedDay: Date {
        let moment = now()
        return Calendar.current.date(byAdding: .day, value: -dayOffset, to: moment) ?? moment
    }
    var dayLabel: String { Tokens.dayLabel(selectedDay) }
    var isToday: Bool { dayOffset == 0 }
    var canStepForward: Bool { dayOffset > 0 }
    var canStepBack: Bool {
        guard let earliest = earliestDay else { return false }
        return Calendar.current.startOfDay(for: selectedDay) > earliest
    }

    func selectDay(offset: Int) {
        dayOffset = max(0, offset)
        clearTimelineSelection()
        clearSession()
        hoveredSession = nil
        refreshDashboard()
    }

    /// Negative steps go back in time. Bounded so navigation can never land on a
    /// day with no data behind it, or in the future.
    func stepDay(by delta: Int) {
        let proposed = dayOffset - delta
        guard proposed >= 0 else { return }
        if delta < 0, let earliest = earliestDay {
            let calendar = Calendar.current
            guard let candidate = calendar.date(byAdding: .day, value: -proposed,
                                                to: Date()),
                  calendar.startOfDay(for: candidate) >= earliest else { return }
        }
        selectDay(offset: proposed)
    }

    func goToToday() { selectDay(offset: 0) }
}
