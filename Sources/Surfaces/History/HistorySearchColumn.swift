import SwiftUI

/// The words over a search's results. Kept apart from the view so the checks
/// read them without rendering.
enum HistorySearchText {
    /// `Qwen · first used 24 August 2026`, `Search · “coding” · Deep work`.
    static func eyebrow(filter: HistoryFilter, appName: String?, lens: HistoryAppLens?) -> String {
        if let lens, let appName {
            guard let first = lens.usedByDay.keys.min() else { return appName }
            return "\(appName) · first used \(DateFormats.australian("d MMMM yyyy").string(from: first))"
        }
        return (["Search"] + subjects(filter: filter, appName: appName)).joined(separator: " · ")
    }

    /// `You used Qwen for 4m on 2 days`, the days being calendar days.
    static func lensSentence(appName: String, lens: HistoryAppLens) -> (sentence: String, highlight: String) {
        let total = lensTotal(lens)
        let days = lens.usedByDay.count == 1 ? "1 day" : "\(lens.usedByDay.count) days"
        return ("You used \(appName) for \(total) on \(days).", total)
    }

    static func lensTotal(_ lens: HistoryAppLens) -> String { lensParts(lens).total }

    /// The app's time in a session and outside sessions, and the total as
    /// the sum of the two printed parts, all to one precision: whole minutes,
    /// or, when neither part reaches a minute, as History's rows print a
    /// sub-minute figure (the total floored to the minute past one, as there).
    static func lensParts(_ lens: HistoryAppLens) -> (inside: String, outside: String, total: String) {
        let inside = StoryRailFigures.minutes(lens.inSession)
        let outside = StoryRailFigures.minutes(lens.outsideTotal)
        let parts = (lensFigure(lens.inSession, in: lens), lensFigure(lens.outsideTotal, in: lens))
        guard inside + outside == 0 else {
            return (parts.0, parts.1, Tokens.duration(TimeInterval((inside + outside) * 60)))
        }
        let seconds = (DurationText.wholeSeconds(lens.inSession) ?? 0)
            + (DurationText.wholeSeconds(lens.outsideTotal) ?? 0)
        return (parts.0, parts.1, HistorySessionRow.figure(seconds > 0 ? TimeInterval(seconds) : lens.total))
    }

    /// A part of the app's record at the record's precision (see `lensParts`).
    static func lensFigure(_ seconds: TimeInterval, in lens: HistoryAppLens) -> String {
        StoryRailFigures.minutes(lens.inSession) + StoryRailFigures.minutes(lens.outsideTotal) == 0
            ? HistorySessionRow.figure(seconds) : Tokens.duration(seconds)
    }

    /// `3m in a session, in 1 session`, then when it was last in front.
    static func lensFacts(_ lens: HistoryAppLens) -> [String] {
        var facts: [String] = []
        let count = lens.sessions.count
        if count == 0 {
            // Seconds in passing inside a session are not a session that used it.
            facts.append(lens.inSession > 0
                ? "no session used it for \(Int(HistoryAppLens.minimumUse)) seconds or more"
                : "none of it in a focus session")
        } else {
            // Time in a session includes its pauses, so it is not called focus.
            facts.append("\(lensParts(lens).inside) in a session, in \(count == 1 ? "1 session" : "\(count) sessions")")
        }
        if let last = lens.lastUsed {
            facts.append("last used \(DateFormats.australian("EEE d MMM").string(from: last)) at "
                         + Tokens.timeOfDayOnly(last))
        }
        return facts
    }

    /// `You focused 18h 41m on “coding” across 12 days.`, or `… in sessions
    /// that used Xcode across 3 days.` with an app picked; a search that found
    /// only breaks says how many.
    static func searchSentence(filter: HistoryFilter, appName: String?, entries: [JournalEntry])
        -> (sentence: String, highlight: String?) {
        let tally = HistoryTree.tally(entries)
        guard tally.sessions > 0 else { return (HistoryTree.matchSummary(entries) + ".", nil) }
        guard tally.worked > 0 else {
            return ("\(tally.sessions == 1 ? "1 session matches" : "\(tally.sessions) sessions match"), "
                    + "with no focus recorded.", nil)
        }
        let days = entries.filter { if case .day(let day) = $0 { return day.focused > 0 } else { return false } }.count
        let worked = Tokens.duration(tally.worked)
        var about = ""
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { about += " on “\(query)”" }
        if let type = filter.workType { about += query.isEmpty ? " on \(type.displayName)" : " in \(type.displayName)" }
        // The figure is the sessions' focus, not the app's: a session joins
        // with ten seconds of the app, so "with Safari" overstated it.
        if let appName { about += " in sessions that used \(appName)" }
        return ("You focused \(worked)\(about) across \(days == 1 ? "1 day" : "\(days) days").", worked)
    }

    /// `18 sessions · 1h 2m per session · 2 breaks`.
    static func searchFacts(_ entries: [JournalEntry]) -> [String] {
        let tally = HistoryTree.tally(entries)
        var facts: [String] = []
        if tally.sessions > 0 { facts.append(tally.sessions == 1 ? "1 session" : "\(tally.sessions) sessions") }
        if tally.sessions > 1, tally.worked > 0 {
            facts.append("\(Tokens.duration(tally.worked / Double(tally.sessions))) per session")
        }
        if tally.breaks > 0, tally.sessions > 0 { facts.append(tally.breaks == 1 ? "1 break" : "\(tally.breaks) breaks") }
        return facts
    }

    private static func subjects(filter: HistoryFilter, appName: String?) -> [String] {
        var parts: [String] = []
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("“\(query)”") }
        if let type = filter.workType { parts.append(type.displayName) }
        if let appName { parts.append(appName) }
        return parts
    }
}

/// History while a search or filter runs: a headline about the matches,
/// each day as a bar, and the matching days with their sessions on the
/// story's spine. A picked app on its own reads as that app's story,
/// with its use outside sessions listed where it fell.
struct HistorySearchColumn: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let entries: [JournalEntry]
    let lens: HistoryAppLens?

    private var appName: String? { store.historyFilter.appBundleID.map(store.historyAppName(for:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            headline
            HistoryResultChart(firstDay: store.historyTop().firstDay, today: store.now(),
                               values: chartValues, isLens: lens != nil,
                               onPick: { day in navigation.revealHistory(target: JournalEntry.dayID(day), focus: nil) })
            HistorySearchList(store: store, navigation: navigation, entries: entries, lens: lens, appName: appName)
        }
        .padding(.horizontal, HistoryRowLayout.inset)
    }

    private var headline: some View {
        let filter = store.historyFilter
        let eyebrow = HistorySearchText.eyebrow(filter: filter, appName: appName, lens: lens)
        if let lens, let appName {
            let line = HistorySearchText.lensSentence(appName: appName, lens: lens)
            return StoryHeadline(eyebrow: eyebrow, sentence: line.sentence,
                                 facts: HistorySearchText.lensFacts(lens), highlight: line.highlight)
        }
        let line = HistorySearchText.searchSentence(filter: filter, appName: appName, entries: entries)
        return StoryHeadline(eyebrow: eyebrow, sentence: line.sentence,
                             facts: HistorySearchText.searchFacts(entries), highlight: line.highlight)
    }

    /// Each day's figure: the app's time in and out of sessions, or the
    /// matched focus.
    private var chartValues: [Date: HistoryResultChart.Value] {
        var values: [Date: HistoryResultChart.Value] = [:]
        if let lens {
            for day in lens.days { values[day.day] = .init(primary: day.inSession, secondary: day.outside) }
        } else {
            for case .day(let day) in entries where day.focused > 0 {
                values[Calendar.current.startOfDay(for: day.date)] = .init(primary: day.focused, secondary: 0)
            }
        }
        return values
    }
}
