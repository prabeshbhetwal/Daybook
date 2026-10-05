import SwiftUI

enum StoryRenderEvidence: String, Hashable {
    case dayStory
    case historyJournal
    case historyTree
    case storyChromeControls
    case historyEmpty
    case historyIntegrityNotice
    case historyPeriodRail
    case historyDayRail
    case historySessionRail
    case historySearchRail
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
        .accessibilityLabel(DurationText.spoken(in: "\(eyebrow). \(sentence) \(facts.joined(separator: ", "))"))
        .accessibilityAddTraits(.isHeader)
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
                                projection: store.storyDayProjection(on: store.selectedDay),
                                context: .main)
    }
}

/// What already stands beside a day's story, so its opening does not say it
/// again. The Day view's rail shows the day's recorded app use; History's
/// picked-period card shows the date, focus, sessions and app use; a History
/// row shows the date, focus and sessions.
enum DayStoryContext {
    case main, underCard, underRow
}

struct ProjectedDayStoryColumn: View {
    @ObservedObject var store: SessionStore
    let projection: StoryDayProjection
    let context: DayStoryContext
    /// History reads the day: no Start again, Remove, Pause or Stop.
    var isHistory = false
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
            if context == .main {
                StoryHeadline(eyebrow: Tokens.longDate(projection.date),
                              sentence: sentence,
                              facts: facts,
                              highlight: Tokens.preciseDuration(projection.focused))
            } else if !facts.isEmpty {
                Text(facts.joined(separator: "  ·  "))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            DayStory(store: store, projection: projection, isHistory: isHistory, opened: disclosure)
                .coachAnchor(.storyColumn)
        }
        // Said from the column, which is always there: the notice itself
        // exists only while it has something to say.
        .announcesChanges(to: StoryCorrectionNotice.visibleError(in: store))
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
        if context == .underRow, projection.tracked > 0 {
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

    /// The failure the notice shows, when it shows one. Today's away prompt
    /// carries its own save error, so the notice stays out of its way.
    static func visibleError(in store: SessionStore) -> String? {
        guard let error = store.correctionError,
              !store.isToday || store.pendingAwaySaveError == nil else { return nil }
        return error
    }

    var body: some View {
        if let error = Self.visibleError(in: store) {
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
