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

    var period: TrackingPeriod {
        get { engine.store.trackingPeriod }
        set {
            engine.store.trackingPeriod = newValue
            refreshDashboard()
        }
    }

    /// What each day of the month containing `date` amounted to, keyed by start
    /// of day: tracked from the month rollup, with focus and session counts
    /// from Story's canonical accounting (including a clipped live stretch).
    /// Built once per shown month, when the calendar asks.
    func dayFacts(inMonthOf date: Date) -> [Date: DayFacts] {
        dayFacts(for: .month, containing: date)
    }

    /// Per-day focus, app use and session count for any period. The Week chart
    /// and the Month calendar read the same facts, so the two scopes cannot
    /// describe a day differently.
    func dayFacts(for period: TrackingPeriod, containing date: Date) -> [Date: DayFacts] {
        guard let usage else { return [:] }
        let calendar = Calendar.current
        let usageSnapshot = effectiveUsageSnapshot
        let days = PeriodStats(sessions: engine.archive, usage: usage,
                               usageSnapshot: usageSnapshot, calendar: periodCalendar)
            .days(for: period, containing: date)
        var facts: [Date: DayFacts] = [:]
        for day in days {
            let key = calendar.startOfDay(for: day.date)
            let focused = storyFocusedSeconds(on: key)
            let goalAchieved = focusedActiveSeconds(on: key,
                                                    usageSnapshot: usageSnapshot)
            let sessions = storySessionCount(on: key)
            if day.tracked > 0 || focused > 0 || sessions > 0 {
                facts[key] = DayFacts(tracked: day.tracked, focused: focused,
                                      sessions: sessions, goalAchieved: goalAchieved)
            }
        }
        return facts
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
                                                to: now()),
                  calendar.startOfDay(for: candidate) >= earliest else { return }
        }
        selectDay(offset: proposed)
    }

}
