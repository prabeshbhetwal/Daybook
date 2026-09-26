import SwiftUI

enum StoryRenderEvidence: String, Hashable {
    case dayStory
    case periodChild
    case historyDetail
    case insightPeriod
    case insightStrongestDay
    case insightEmptyPeriod
    case activityQuietChoice
    case firstRunWelcome
    case firstRunFirstSession
    case firstRunMacSaw
    case firstRunReadingDay
    case firstRunRail
    case firstRunSteppingAway
    case firstRunAutomation
    case firstRunLookingBack
    case firstRunAwards
    case firstRunMenuBar
    case firstRunSettings
    case firstRunFinish
}

extension StoryRenderEvidence {
    /// One case per welcome chapter, so a render proof can say which chapter
    /// drew rather than only that something did. An in-process accessibility
    /// walk cannot see SwiftUI, so this is the seam the checks use.
    static func firstRun(_ chapter: FirstRunChapter) -> StoryRenderEvidence {
        switch chapter {
        case .welcome: return .firstRunWelcome
        case .firstSession: return .firstRunFirstSession
        case .macSaw: return .firstRunMacSaw
        case .readingDay: return .firstRunReadingDay
        case .rail: return .firstRunRail
        case .steppingAway: return .firstRunSteppingAway
        case .automation: return .firstRunAutomation
        case .lookingBack: return .firstRunLookingBack
        case .awards: return .firstRunAwards
        case .menuBar: return .firstRunMenuBar
        case .settings: return .firstRunSettings
        case .finish: return .firstRunFinish
        }
    }
}

struct StoryRenderEvidenceKey: PreferenceKey {
    static let defaultValue: Set<StoryRenderEvidence> = []
    static func reduce(value: inout Set<StoryRenderEvidence>,
                       nextValue: () -> Set<StoryRenderEvidence>) {
        value.formUnion(nextValue())
    }
}

extension View {
    /// Deterministic offscreen evidence attached to the actual conditional
    /// content branch. Production ignores the preference; verification can
    /// prove the branch rendered without relying on permanent chrome.
    func storyRenderEvidence(_ evidence: StoryRenderEvidence) -> some View {
        transformPreference(StoryRenderEvidenceKey.self) { value in
            value.insert(evidence)
        }
    }
}

/// A period's opening sentence, composed from figures the store already holds.
/// Every clause is gated on its own evidence, so an empty period says it is
/// empty rather than reading as a failure.
enum StoryNarrative {
    static func day(focused: TimeInterval, tracked: TimeInterval, sessions: Int,
                    rest: TimeInterval, isToday: Bool) -> String {
        if focused > 0 {
            let count = sessions == 1 ? "one focus session" : "\(sessions) focus sessions"
            return "\(isToday ? "You've logged" : "You logged") "
                + "\(Tokens.preciseDuration(focused)) across \(count)."
        }
        if tracked > 0 {
            return "You recorded \(Tokens.preciseDuration(tracked)) of app use, with no focus session."
        }
        if rest > 0 {
            return "You recorded \(Tokens.preciseDuration(rest)) as a break, with no focus session."
        }
        return isToday ? "Your day starts here." : "No activity was recorded on this day."
    }

    static func period(activeDays: Int,
                       totalDays: Int,
                       focused: TimeInterval,
                       tracked: TimeInterval = 0,
                       best: (day: Date, focused: TimeInterval)?,
                       unit: String) -> String {
        guard focused > 0 else {
            if tracked > 0 {
                return "You recorded \(Tokens.preciseDuration(tracked)) of app use this \(unit), with no focus session."
            }
            return "No focus was recorded this \(unit)."
        }
        var text = activeDays > 0
            ? "You focused on \(activeDays) of \(totalDays) days, \(Tokens.preciseDuration(focused)) in total"
            : "You focused for \(Tokens.preciseDuration(focused)) this \(unit)"
        if let best, best.focused > 0 {
            text += "; the strongest day was \(Tokens.longDate(best.day)) "
                + "with \(Tokens.preciseDuration(best.focused)) logged focus"
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
                .font(Tokens.Typography.microLabel.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            emphasised
                .font(StoryStyle.headline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: StoryStyle.headlineMeasure, alignment: .leading)
            if !facts.isEmpty {
                Text(facts.joined(separator: "  ·  "))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow). \(sentence) \(facts.joined(separator: ", "))")
    }

    /// The sentence with its key figure in the accent colour. `highlight` is
    /// matched literally inside the sentence, so a figure the sentence does not
    /// contain simply leaves the line unstyled rather than altering the words.
    private var emphasised: Text {
        guard let highlight, !highlight.isEmpty,
              let range = sentence.range(of: highlight) else { return Text(sentence) }
        return Text(String(sentence[sentence.startIndex..<range.lowerBound]))
            + Text(highlight).foregroundColor(StoryStyle.focus)
            + Text(String(sentence[range.upperBound...]))
    }
}

// MARK: - Day

struct DayStoryColumn: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        ProjectedDayStoryColumn(store: store,
                                projection: store.storyDayProjection(on: store.selectedDay))
    }
}

struct ProjectedDayStoryColumn: View {
    @ObservedObject var store: SessionStore
    let projection: StoryDayProjection
    @StateObject private var disclosure = StoryDisclosureState()
    /// The measurement disclosure's key in the day's shared open set.
    static let summaryKey = "summary"

    var body: some View {
        // "How this day was measured" opens with everything else; it is the
        // first thing Expand all should not skip.
        let expandable = (projection.summaryFacts.isEmpty ? [] : [Self.summaryKey])
            + DayStory.expandableIDs(in: projection.chronology, fold: store.engine.store.quietFold)
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            if let note = projection.integrityNote { IntegrityNotice(note) }
            if !store.isTrackingEnabled, Calendar.current.isDateInToday(projection.date) {
                // Sessions are still logged, but nothing says which apps they
                // were in. Said here, once, rather than left to be inferred
                // from every card reading "no app recording".
                IntegrityNotice("App recording is off, so today's sessions carry no app evidence. "
                                + "Turn on Record app usage in Settings › Recording.")
            }
            StoryHeadline(eyebrow: Tokens.longDate(projection.date),
                          sentence: sentence,
                          facts: facts,
                          highlight: Tokens.preciseDuration(projection.focused))
            StoryCorrectionNotice(store: store)
            if !projection.summaryFacts.isEmpty {
                StoryDisclosure(title: "How this day was measured", isExpanded: Binding(
                    get: { disclosure.ids.contains(Self.summaryKey) },
                    set: { open in
                        if open { disclosure.ids.insert(Self.summaryKey) } else { disclosure.ids.remove(Self.summaryKey) }
                    })) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(projection.summaryFacts.enumerated()), id: \.offset) { _, fact in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").accessibilityHidden(true)
                                Text(fact)
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .coachAnchor(.measured)
                // On the header's line, at the far edge: the one control that
                // opens or closes the whole day.
                .overlay(alignment: .topTrailing) {
                    if !expandable.isEmpty {
                        StoryExpandAllControl(disclosure: disclosure, ids: expandable)
                            .frame(height: AccessibilityMetrics.minimumTargetSize)
                    }
                }
            } else if !expandable.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    StoryExpandAllControl(disclosure: disclosure, ids: expandable)
                }
            }
            DayStory(store: store, projection: projection, opened: disclosure)
                .coachAnchor(.storyColumn)
        }
        .accessibilityIdentifier("story-day-content-\(projection.id)")
        .storyRenderEvidence(.dayStory)
    }

    /// A focus-led sentence; the longer evidence narrative remains available
    /// below the chronology rather than overwhelming the headline.
    private var sentence: String {
        StoryNarrative.day(focused: projection.focused,
                           tracked: projection.tracked,
                           sessions: projection.focusSessionCount,
                           rest: projection.recordedBreakSeconds,
                           isToday: projection.isCurrentDay)
    }

    private var facts: [String] {
        var parts: [String] = []
        if projection.tracked > 0 {
            parts.append("\(Tokens.duration(projection.tracked)) recorded app use")
        }
        if projection.recordedBreakSeconds > 0 {
            parts.append("\(Tokens.duration(projection.recordedBreakSeconds)) recorded break")
        }
        let longest = projection.longestFocusStretch
        if longest > 0 { parts.append("longest stretch \(Tokens.preciseDuration(longest))") }
        return parts
    }
}

/// Feedback remains outside the corrected row, so converting it to rest cannot
/// remove the recovery action along with its former focus controls.
struct StoryCorrectionNotice: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        if let error = store.correctionError, !store.isToday || store.pendingAwaySaveError == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).fixedSize(horizontal: false, vertical: true)
                Button("Retry saving") { store.retryLastCorrection() }
                    .buttonStyle(StoryLinkStyle())
            }
            .font(Tokens.Typography.metadata)
            .padding(Tokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colour.attention.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.well))
        }
    }
}

// MARK: - Week

struct WeekStoryColumn: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            if let note = store.reviewIntegrityNote { IntegrityNotice(note) }
            StoryHeadline(eyebrow: store.reviewPeriodLabel,
                          sentence: sentence,
                          facts: facts,
                          highlight: Tokens.duration(store.reviewFocusedSeconds))
            WeekStoryChart(days: store.reviewDays,
                           facts: store.dayFacts(for: .week,
                                                 containing: store.reviewPeriodStart),
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
        StoryNarrative.period(activeDays: store.storyFocusSummary.activeDays,
                              totalDays: store.reviewSummary.totalDays,
                              focused: store.reviewFocusedSeconds,
                              tracked: store.reviewSummary.tracked,
                              best: store.reviewBestDay,
                              unit: "week")
    }

    private var facts: [String] {
        var parts: [String] = []
        let summary = store.storyFocusSummary
        if summary.activeDays > 0 {
            parts.append("\(Tokens.duration(summary.averagePerActiveDay)) per focused day")
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

    private var isExpanded: Bool {
        navigation.expandedStoryDay.map {
            Calendar.current.isDate($0, inSameDayAs: day)
        } ?? false
    }

    var body: some View {
        // Read once: today's projection is rebuilt on every read, and this
        // card read it seven times a render.
        let projection = store.storyDayProjection(on: day)
        return VStack(alignment: .leading, spacing: Tokens.Space.l) {
            SurfacePanel(showsHeader: false) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                    Text(Tokens.longDate(day))
                        .font(Tokens.Typography.sectionTitle)
                    Text(Tokens.duration(projection.focused))
                        .font(Tokens.Typography.metricValue.monospacedDigit())
                        .foregroundStyle(Tokens.Colour.focus)
                    Spacer(minLength: Tokens.Space.m)
                    Button {
                        navigation.toggleExpandedStoryDay(day)
                    } label: {
                        Text(isExpanded ? "Hide story" : "Open as a story ›")
                            .font(Tokens.Typography.metadata.weight(.semibold))
                            .foregroundStyle(StoryStyle.action)
                    }
                    .buttonStyle(StoryPressStyle())
                    .accessibilityLabel(isExpanded
                        ? "Hide \(Tokens.longDate(day)) story"
                        : "Open \(Tokens.longDate(day)) as a story")
                }
                Text(note(projection))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isExpanded {
                ProjectedDayStoryColumn(store: store, projection: projection)
                    .id(projection.id)
                    .accessibilityIdentifier("story-period-child-content-\(projection.id)")
                    .storyRenderEvidence(.periodChild)
            }
        }
    }

    private func note(_ projection: StoryDayProjection) -> String {
        guard facts != nil || !projection.chronology.isEmpty else {
            return "Nothing was recorded on this day."
        }
        var parts: [String] = []
        parts.append(projection.focusSessionCount == 1
                     ? "1 session" : "\(projection.focusSessionCount) sessions")
        if projection.tracked > 0 {
            parts.append("\(Tokens.duration(projection.tracked)) recorded app use")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Month

struct MonthStoryColumn: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            if let note = store.reviewIntegrityNote { IntegrityNotice(note) }
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
        StoryNarrative.period(activeDays: store.storyFocusSummary.activeDays,
                              totalDays: store.reviewSummary.totalDays,
                              focused: store.reviewFocusedSeconds,
                              tracked: store.reviewSummary.tracked,
                              best: store.reviewBestDay,
                              unit: "month")
    }

    private var facts: [String] {
        var parts: [String] = []
        let summary = store.storyFocusSummary
        if summary.activeDays > 0 {
            parts.append("\(Tokens.duration(summary.averagePerActiveDay)) per focused day")
        }
        if summary.longestStretch > 0 {
            parts.append("longest stretch \(Tokens.preciseDuration(summary.longestStretch))")
        }
        return parts
    }
}
