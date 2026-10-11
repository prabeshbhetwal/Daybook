import Foundation

/// What Ask's focus totals say beyond the headline: the time in each work
/// type, the current streak, and the line of a note that matched the words.
/// Every figure is read from the place its screen reads it.
extension SessionStore {
    /// The range's focus by work type, as History's cards split it: largest
    /// first, in the order History keeps.
    func askWorkTypes(_ range: AskRange) -> [AskShare] {
        historyCategories(for: HistoryPlace(level: range.level ?? .year, span: askInterval(range)))
            .map { AskShare(name: $0.workType.displayName, seconds: $0.seconds) }
    }

    /// The current streak and the day it began; nil when there is none. As
    /// the menu counts it, the running session's work counts toward today.
    /// The streak runs back from today when today has reached the minimum
    /// itself, else from yesterday, which a streak ending there still keeps.
    func askStreak() -> (days: Int, since: Date)? {
        let inFlight = engine.elapsedToday()
        let days = engine.currentStreak(includingToday: inFlight)
        guard days > 0 else { return nil }
        let calendar = periodCalendar
        let today = calendar.startOfDay(for: now())
        let reached = engine.archive.todayTotal() + inFlight >= engine.archive.streakMinimum
        guard let last = reached ? today : calendar.date(byAdding: .day, value: -1, to: today),
              let since = calendar.date(byAdding: .day, value: 1 - days, to: last) else { return nil }
        return (days: days, since: since)
    }

    /// The first note line, across the sessions newest first, that holds a
    /// word of `words`, as the journal picks the line a search shows.
    func askNoteLine(words: String, in clips: [AskClip]) -> String? {
        let folded = SearchWords.words(in: words)
        for clip in clips {
            if let line = noteLine(in: clip.hit.recordIDs, holding: folded) { return line }
        }
        return nil
    }

    /// The parts of a plain total the headline does not hold: its work types
    /// and, for all time, the streak.
    func askAddExtras(_ range: AskRange, to totals: inout AskTotals) {
        totals.workTypes = askWorkTypes(range)
        if range == .allTime, let streak = askStreak() {
            totals.streak = (days: streak.days, since: askDay(streak.since))
        }
    }
}
