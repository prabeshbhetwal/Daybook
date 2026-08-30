import SwiftUI

/// A period's opening sentence, composed from figures the store already holds.
/// Every clause is gated on its own evidence, so an empty period says it is
/// empty rather than reading as a failure.
enum StoryNarrative {
    static func period(activeDays: Int,
                       totalDays: Int,
                       focused: TimeInterval,
                       best: (day: Date, focused: TimeInterval)?,
                       unit: String) -> String {
        guard activeDays > 0, focused > 0 else {
            return "Nothing has been recorded this \(unit) yet."
        }
        var text = "You focused on \(activeDays) of \(totalDays) days, "
            + "\(Tokens.duration(focused)) in total"
        if let best, best.focused > 0 {
            text += ", and \(Tokens.weekdayName(best.day)) carried the \(unit)"
        }
        return text + "."
    }
}

/// The sentence a story opens with, and the plain figures under it. The
/// headline is the day's own summary, never a generated claim.
struct StoryHeadline: View {
    let eyebrow: String
    let sentence: String
    let facts: [String]
    /// The one figure the sentence is about, coloured where it appears.
    var highlight: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            emphasised
                .font(Tokens.Typography.storyHeadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
            if !facts.isEmpty {
                Text(facts.joined(separator: "  ·  "))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow). \(sentence)")
    }

    /// The sentence with its key figure in the accent colour. `highlight` is
    /// matched literally inside the sentence, so a figure the sentence does not
    /// contain simply leaves the line unstyled rather than altering the words.
    private var emphasised: Text {
        guard let highlight, !highlight.isEmpty,
              let range = sentence.range(of: highlight) else { return Text(sentence) }
        return Text(String(sentence[sentence.startIndex..<range.lowerBound]))
            + Text(highlight).foregroundColor(Tokens.Colour.focus)
            + Text(String(sentence[range.upperBound...]))
    }
}

// MARK: - Day

struct DayStoryColumn: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            StoryHeadline(eyebrow: Tokens.longDate(store.selectedDay),
                          sentence: sentence,
                          facts: facts,
                          highlight: Tokens.duration(focusedToday))
            DayStory(store: store)
            if let note = store.selectedDayIntegrityNote {
                Text(note)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tokens.Space.s)
            }
        }
    }

    /// The store's own first summary sentence, with its emphasis marks removed.
    private var sentence: String {
        let recap = DayRecapNarrative(sentences: store.summarySentences)
        return recap.lead ?? "Nothing has been recorded on this day."
    }

    private var focusedToday: TimeInterval {
        store.isToday ? store.todayTotal : store.focusedForSelectedDay
    }

    private var facts: [String] {
        var parts: [String] = []
        let tracked = store.isToday ? store.trackedToday : store.trackedForSelectedDay
        if tracked > 0 { parts.append("\(Tokens.duration(tracked)) on this Mac") }
        let rest = store.daySessions.compactMap { entry -> TimeInterval? in
            if case .rest(let rest) = entry { return rest.length }
            return nil
        }.reduce(0, +)
        if rest > 0 { parts.append("\(Tokens.duration(rest)) of rest") }
        let longest = store.isToday ? store.longestToday : store.longestForSelectedDay
        if longest > 0 { parts.append("longest stretch \(Tokens.preciseDuration(longest))") }
        return parts
    }
}

// MARK: - Week

struct WeekStoryColumn: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            StoryHeadline(eyebrow: store.reviewPeriodLabel,
                          sentence: sentence,
                          facts: facts,
                          highlight: Tokens.duration(store.reviewFocusedSeconds))
            WeekStoryChart(days: store.reviewDays,
                           average: store.reviewSummary.averagePerActiveDay,
                           selectedDay: navigation.storySelectedDay,
                           onPickDay: { navigation.selectStoryDay($0) })
            WorkTypeLegend(shares: store.reviewWorkTypeShares)
            if let day = navigation.storySelectedDay {
                StorySelectedDayCard(store: store, navigation: navigation, day: day)
            }
        }
    }

    private var sentence: String {
        StoryNarrative.period(activeDays: store.reviewSummary.activeDays,
                              totalDays: store.reviewSummary.totalDays,
                              focused: store.reviewFocusedSeconds,
                              best: store.reviewBestDay,
                              unit: "week")
    }

    private var facts: [String] {
        var parts: [String] = []
        let summary = store.reviewSummary
        if summary.activeDays > 0 {
            parts.append("\(Tokens.duration(summary.averagePerActiveDay)) average per active day")
        }
        if store.reviewLongestFocusSeconds > 0 {
            parts.append("longest stretch "
                         + Tokens.preciseDuration(store.reviewLongestFocusSeconds))
        }
        return parts
    }
}

/// The day chosen from a week bar or a month cell, with the one action that
/// opens it as its own story.
struct StorySelectedDayCard: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let day: Date

    private var facts: HistoryDay? {
        store.historyDays.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        SurfacePanel(showsHeader: false) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                Text(Tokens.longDate(day))
                    .font(Tokens.Typography.sectionTitle)
                Text(Tokens.duration(facts?.focused ?? 0))
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                    .foregroundStyle(Tokens.Colour.focus)
                Spacer(minLength: Tokens.Space.m)
                Button {
                    navigation.openStoryDay(day)
                } label: {
                    Text("Open as a story ›")
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .foregroundStyle(Tokens.Colour.focus)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(Tokens.longDate(day)) as a story")
            }
            Text(note)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var note: String {
        guard let facts else { return "Nothing was recorded on this day." }
        var parts: [String] = []
        parts.append(facts.sessions == 1 ? "1 session" : "\(facts.sessions) sessions")
        if facts.tracked > 0 { parts.append("\(Tokens.duration(facts.tracked)) on this Mac") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Month

struct MonthStoryColumn: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            StoryHeadline(eyebrow: store.reviewPeriodLabel,
                          sentence: sentence,
                          facts: facts,
                          highlight: Tokens.duration(store.reviewFocusedSeconds))
            MonthStoryGrid(store: store, navigation: navigation)
            if let day = navigation.storySelectedDay {
                StorySelectedDayCard(store: store, navigation: navigation, day: day)
            }
        }
    }

    private var sentence: String {
        StoryNarrative.period(activeDays: store.reviewSummary.activeDays,
                              totalDays: store.reviewSummary.totalDays,
                              focused: store.reviewFocusedSeconds,
                              best: store.reviewBestDay,
                              unit: "month")
    }

    private var facts: [String] {
        var parts: [String] = []
        let summary = store.reviewSummary
        if summary.activeDays > 0 {
            parts.append("\(Tokens.duration(summary.averagePerActiveDay)) average")
        }
        parts.append("\(summary.activeDays) of \(summary.totalDays) days had focus")
        return parts
    }
}
