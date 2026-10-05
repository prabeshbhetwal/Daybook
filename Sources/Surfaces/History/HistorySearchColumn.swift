import SwiftUI

/// The words over a search's results. Kept apart from the view so the checks
/// read them without rendering.
enum HistorySearchText {
    /// `Qwen · first used 24 August 2026`, `Search · “coding” · Deep work`.
    static func eyebrow(filter: HistoryFilter, appName: String?, lens: HistoryAppLens?) -> String {
        if let lens, let appName {
            guard let first = lens.days.first?.day else { return appName }
            return "\(appName) · first used \(DateFormats.australian("d MMMM yyyy").string(from: first))"
        }
        return (["Search"] + subjects(filter: filter, appName: appName)).joined(separator: " · ")
    }

    /// `You used Qwen for 4m on 2 days.` The total is the sum of the two
    /// printed parts, each in whole minutes, so the figures add up on screen.
    static func lensSentence(appName: String, lens: HistoryAppLens) -> (sentence: String, highlight: String) {
        let total = lensTotal(lens)
        let days = lens.days.count == 1 ? "1 day" : "\(lens.days.count) days"
        return ("You used \(appName) for \(total) on \(days).", total)
    }

    static func lensTotal(_ lens: HistoryAppLens) -> String {
        let minutes = StoryRailFigures.minutes(lens.inSession) + StoryRailFigures.minutes(lens.outsideTotal)
        return minutes > 0 ? Tokens.duration(TimeInterval(minutes * 60))
            : Tokens.preciseDuration(lens.inSession + lens.outsideTotal)
    }

    /// `3m during focus, in 1 session`, then when it was last in front.
    static func lensFacts(_ lens: HistoryAppLens) -> [String] {
        var facts: [String] = []
        let count = lens.sessions.count
        if count == 0 {
            // Seconds in passing inside a session are not a session that used it.
            facts.append(lens.inSession > 0
                ? "no session used it for \(Int(HistoryAppLens.minimumUse)) seconds or more"
                : "none of it in a focus session")
        } else {
            let inside = TimeInterval(StoryRailFigures.minutes(lens.inSession) * 60)
            facts.append("\(Tokens.duration(inside)) during focus, in \(count == 1 ? "1 session" : "\(count) sessions")")
        }
        if let last = lens.lastUsed {
            facts.append("last used \(DateFormats.australian("EEE d MMM").string(from: last)) at "
                         + Tokens.timeOfDayOnly(last))
        }
        return facts
    }

    /// `You focused 18h 41m on “coding” across 12 days.`; a search that found
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
        if let appName { about += " with \(appName)" }
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

/// One bar per day from the first day on record to today. A day with a
/// figure can be clicked to bring it into view below.
struct HistoryResultChart: View {
    struct Value: Equatable {
        let primary: TimeInterval
        let secondary: TimeInterval
        var total: TimeInterval { primary + secondary }
    }

    let firstDay: Date
    let today: Date
    let values: [Date: Value]
    /// An app's use: in-session and outside parts, in the app-use colour.
    let isLens: Bool
    let onPick: (Date) -> Void

    static let height: CGFloat = 64

    static let maximumDays = 1_000

    // ponytail: one bar per day; past a year of record the bars thin to a
    // point, and weeks would read better.
    /// The newest `maximumDays` days, oldest first. Each step is the day's
    /// real end: where a clock skips midnight, start of day plus one day
    /// lands past the next day's start, and its bar would find no figure.
    private var days: [Date] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: today)
        let earliest = calendar.date(byAdding: .day, value: -(Self.maximumDays - 1), to: end) ?? end
        var cursor = calendar.startOfDay(for: max(firstDay, earliest))
        var result: [Date] = []
        while cursor <= end, result.count < Self.maximumDays {
            result.append(cursor)
            guard let next = calendar.dateInterval(of: .day, for: cursor)?.end else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return result
    }

    private var primaryColour: Color { isLens ? Tokens.Palette.app(rank: 1) : Tokens.Colour.focus }

    var body: some View {
        let days = self.days
        let peak = max(values.values.map(\.total).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Each day")
                .font(Tokens.Typography.metadata.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: days.count > 120 ? 1 : 2) {
                ForEach(days, id: \.self) { day in bar(day, peak: peak) }
            }
            .frame(height: Self.height, alignment: .bottom)
            HStack {
                Text(DateFormats.australian("d MMM").string(from: days.first ?? firstDay))
                Spacer(minLength: Tokens.Space.s)
                Text("Today")
            }
            .font(Tokens.Typography.microLabel)
            .foregroundStyle(.secondary)
            if isLens {
                HStack(spacing: Tokens.Space.m) {
                    swatch(primaryColour, "In a session")
                    swatch(primaryColour.opacity(0.42), "Outside sessions")
                }
            }
        }
        .padding(StoryStyle.tileInsets)
        .background(StoryStyle.card, in: RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous)
            .strokeBorder(Tokens.Colour.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Each day")
        .accessibilityValue(DurationText.spoken(in: spokenSummary))
    }

    @ViewBuilder private func bar(_ day: Date, peak: TimeInterval) -> some View {
        if let value = values[day], value.total > 0 {
            let height = max(4, Self.height * value.total / peak)
            VStack(spacing: 0) {
                Rectangle().fill(primaryColour.opacity(0.42))
                    .frame(height: height * value.secondary / value.total)
                Rectangle().fill(primaryColour)
                    .frame(height: height * value.primary / value.total)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onPick(day) }
            .help("\(DateFormats.australian("EEE d MMM").string(from: day)) · \(Tokens.preciseDuration(value.total))")
        } else {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(StoryStyle.line)
                .frame(maxWidth: .infinity)
                .frame(height: 2)
        }
    }

    private func swatch(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous).fill(colour).frame(width: 9, height: 9)
            Text(label).font(Tokens.Typography.microLabel).foregroundStyle(.secondary)
        }
    }

    private var spokenSummary: String {
        let used = values.filter { $0.value.total > 0 }
        guard let best = used.max(by: { $0.value.total < $1.value.total }) else { return "nothing recorded" }
        let count = used.count == 1 ? "1 day" : "\(used.count) days"
        return "\(count), the most on \(DateFormats.australian("EEEE d MMMM").string(from: best.key)), "
            + Tokens.duration(best.value.total)
    }
}
