import SwiftUI

private struct StoryEntryInitiallyOpenKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FocusExpandsEntryDetailsKey: EnvironmentKey {
    static let defaultValue = false
}

/// Which story rows are open. Owned by the column so the header's Expand all
/// and the rows' own chevrons move the same set.
final class StoryDisclosureState: ObservableObject {
    @Published var ids: Set<String> = []
}

/// One link that opens or closes every session and folded quiet run in the
/// day. It reads "Collapse all" only when everything it would open is open.
struct StoryExpandAllControl: View {
    @ObservedObject var disclosure: StoryDisclosureState
    let ids: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var allOpen: Bool { !ids.isEmpty && ids.allSatisfy(disclosure.ids.contains) }

    var body: some View {
        Button(allOpen ? "Collapse all" : "Expand all") {
            let opening = !allOpen
            withAnimation(Tokens.Motion.animation(opening ? Tokens.Motion.reveal : Tokens.Motion.dismiss,
                                                  reduceMotion: reduceMotion)) {
                if opening { disclosure.ids.formUnion(ids) } else { disclosure.ids.subtract(ids) }
            }
        }
        .buttonStyle(StoryLinkStyle())
        .disabled(ids.isEmpty)
        .help(allOpen ? "Close every session in the day" : "Open every session in the day")
        .accessibilityLabel(allOpen ? "Collapse all sessions" : "Expand all sessions")
    }
}

/// The live fields supplied to one session card. Kept as a value so the
/// explicit projected date and the visible controls cannot drift apart.
struct DayStorySessionPresentation: Equatable {
    let clock: String?
    let liveStatus: String?
    let pauseTitle: String
    let canControl: Bool

    static func make(session: DaySession,
                     isCurrentStoryDay: Bool,
                     store: SessionStore) -> DayStorySessionPresentation {
        let showsLiveState = session.isRunning && isCurrentStoryDay
        let canControl = session.isRunning && isCurrentStoryDay
            && store.engine.state != .idle
            && session.threadID == store.engine.activeThreadID
            && !store.hasUnresolvedAwayDecision
        return DayStorySessionPresentation(
            clock: showsLiveState ? Tokens.clock(session.worked) : nil,
            liveStatus: showsLiveState
                ? (store.pendingAway != nil ? "awaiting your decision"
                    : store.isPaused ? "paused" : "running now") : nil,
            pauseTitle: store.isAway ? "I'm back" : store.isPaused ? "Resume" : "Pause",
            canControl: canControl)
    }
}

extension EnvironmentValues {
    /// Opens session entries on appearance. Carries the reader's preference,
    /// and the snapshot harness sets it to show an opened entry.
    var storyEntryInitiallyOpen: Bool {
        get { self[StoryEntryInitiallyOpenKey.self] }
        set { self[StoryEntryInitiallyOpenKey.self] = newValue }
    }

    /// The reader's preference for whether entries open with their detail
    /// already showing.
    var focusExpandsEntryDetails: Bool {
        get { self[FocusExpandsEntryDetailsKey.self] }
        set { self[FocusExpandsEntryDetailsKey.self] = newValue }
    }
}

/// The day told top to bottom: every session, rest and unresolved gap as one
/// entry on a single rule. A gap is an entry too, so unrecorded time is part of
/// the day rather than a hole in it. Each entry opens in place — nothing here
/// navigates away.
struct DayStory: View {
    @ObservedObject var store: SessionStore
    var projection: StoryDayProjection? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Entries the reader has opened. A reading aid, not state the product
    /// remembers; the column owns it so its header can open them all.
    @ObservedObject var opened: StoryDisclosureState
    @Environment(\.storyEntryInitiallyOpen) private var entryInitiallyOpen
    @Environment(\.focusExpandsEntryDetails) private var expandsDetails
    @Environment(\.focusShowsTimelineLabels) private var showsTimes

    /// The gutter that carries the clock times, and the rule beside it.
    private let timeColumn: CGFloat = 62
    private let railColumn: CGFloat = 22

    private var moments: [StoryMoment] {
        (projection?.chronology ?? store.storyTimelineItems).compactMap { item in
            if case .moment(let moment) = item { return moment }
            return nil
        }
    }

    /// Every row that can be opened: each session, and each folded run of
    /// quiet rows. The same keys the rows themselves toggle.
    /// Everything on the day that opens: session cards, loose app use, the
    /// folded quiet runs, and the app use inside those runs, so Expand all
    /// leaves nothing closed.
    static func expandableIDs(in entries: [StoryTimelineItem], fold: Int = FocusConstants.defaultQuietFold) -> [String] {
        var ids: [String] = []
        for row in entries.groupingQuietRuns(minimumRun: fold == 0 ? Int.max : max(2, fold)) {
            switch row {
            case .item(let item):
                if case .moment(.entry(.session)) = item { ids.append(item.id) }
                if case .moment(.appUse) = item { ids.append(item.id) }
            case .quiet(let run):
                ids.append("quiet-" + run.id)
                for moment in run.moments {
                    if case .appUse = moment { ids.append(StoryTimelineItem.moment(moment).id) }
                }
            }
        }
        return ids
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let entries = projection?.chronology ?? store.storyTimelineItems
            let fold = store.engine.store.quietFold
            let rows = entries.groupingQuietRuns(minimumRun: fold == 0 ? Int.max : max(2, fold))
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let isFirst = index == 0
                let isLast = index == rows.count - 1
                switch row {
                case .item(let item):
                    timelineRow(item, isFirst: isFirst, isLast: isLast)
                case .quiet(let run):
                    quietRow(run, isFirst: isFirst, isLast: isLast)
                }
            }
            if entries.isEmpty { empty }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: openInitialEntries)
        .onChange(of: store.dayOffset) { _ in
            opened.ids.removeAll()
            openInitialEntries()
        }
        .onChange(of: projection?.id) { _ in
            opened.ids.removeAll()
            openInitialEntries()
        }
        .onChange(of: expandsDetails) { _ in
            opened.ids.removeAll()
            openInitialEntries()
        }
        .onChange(of: store.engine.activeThreadID) { _ in openRunningEntry() }
    }

    /// A run of quiet intervals as one row. Open, it shows every original row
    /// unchanged — the time is never hidden, only folded.
    @ViewBuilder private func quietRow(_ run: StoryQuietRun,
                                       isFirst: Bool, isLast: Bool) -> some View {
        let key = "quiet-" + run.id
        let isOpen = opened.ids.contains(key)
        storyRow(time: run.moments.first?.start ?? store.selectedDay,
                 tint: .secondary, dotSize: 5, isFirst: isFirst, isLast: isLast) {
            Button { toggle(key) } label: {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(run.summary)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Tokens.Space.xs)
                    Image(systemName: "chevron.down")
                        .font(Tokens.Typography.microLabel)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle(hovers: true))
            .accessibilityLabel(run.span.map { "\(run.summary), \(Tokens.timeRange($0.start, $0.end))" }
                                ?? run.summary)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(isOpen ? "Fold these intervals" : "Show these intervals")
        }
        if isOpen {
            ForEach(Array(run.moments.enumerated()), id: \.element.id) { index, moment in
                timelineRow(.moment(moment), isFirst: false,
                            isLast: isLast && index == run.moments.count - 1)
                    .transition(Tokens.Motion.transition(Tokens.Motion.unfold,
                                                         reduceMotion: reduceMotion))
            }
        }
    }

    @ViewBuilder private func timelineRow(_ item: StoryTimelineItem, isFirst: Bool, isLast: Bool) -> some View {
        switch item {
        case .moment(let moment):
                switch moment {
                case .entry(let entry):
                    row(entry, isFirst: isFirst, isLast: isLast)
                case .unrecorded(let span, let reason):
                    let power = store.ambientPowerSummary(within: span)
                    // The stretch before the hole says why it ended, when it
                    // ended for input or the lock screen.
                    let title = reason.title
                    storyRow(time: span.start, tint: .secondary, dotSize: 5,
                             isFirst: isFirst, isLast: isLast) {
                        HStack(alignment: .firstTextBaseline) {
                            // Nothing was recorded but the Mac's power, which
                            // is the one thing the row can honestly add.
                            Text(title + (power.map { " · \($0.headline)" } ?? ""))
                            Spacer(minLength: 8)
                            Text(Tokens.duration(span.duration)).monospacedDigit()
                        }
                        .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(title), \(Tokens.timeRange(span.start, span.end)). "
                                            + (power.map { "Power: \($0.headline). " } ?? "")
                                            + "This interval is not assumed to be work or rest.")
                    }
                case .appUse(let span, let seconds):
                    storyRow(time: span.start, tint: Tokens.Palette.app(rank: 1), dotSize: 7,
                             isFirst: isFirst, isLast: isLast) {
                        StoryLooseAppUse(store: store, span: span, seconds: seconds,
                                         isOpen: opened.ids.contains(item.id),
                                         onToggle: { toggle(item.id) })
                    }
                }
        case .pending(let range):
            if let away = store.pendingAway {
                let expectedID = store.engine.pendingDecisionID
                storyRow(time: range.start, tint: Tokens.Colour.attention, dotSize: 9,
                         isFirst: isFirst, isLast: isLast) {
                    AwayEntryCard(away: away, range: store.pendingAwayRange, note: store.continuationNote,
                                  error: store.pendingAwaySaveError,
                                  onRetry: { store.retryPendingAwayDecision(expectedID: expectedID) },
                                  onAnswer: { store.resolve($0, expectedID: expectedID) },
                                  onReason: { store.resolve(.tookBreak, label: $0, expectedID: expectedID) })
                }
            }
        case .decision(let receipt, let range):
            storyRow(time: range.start, tint: receipt.isResolved ? StoryStyle.successInk : Tokens.Colour.attention,
                     dotSize: 8, isFirst: isFirst, isLast: isLast) {
                StoryDecisionRow(store: store, receipt: receipt, range: range)
            }
        case .correction(let id, let title, let range):
            storyRow(time: range.start, tint: StoryStyle.successInk, dotSize: 8,
                     isFirst: isFirst, isLast: isLast) {
                StorySavedActionRow(title: title, range: range,
                                    scopeNote: store.correctionScopeNote(expectedID: id)) {
                    store.undoCorrection(expectedID: id)
                }
            }
        }
    }

    /// Opens what the reader asked to see already open. Only on first
    /// appearance: an entry the reader then closes must stay closed.
    private func openInitialEntries() {
        guard opened.ids.isEmpty else { return }
        let sessions = moments.compactMap { moment -> DaySession? in
            if case .entry(.session(let session)) = moment { return session }
            return nil
        }
        if expandsDetails {
            opened.ids.formUnion(sessions.map { StoryMoment.entry(.session($0)).id })
        } else if entryInitiallyOpen, let first = sessions.first {
            opened.ids.insert(StoryMoment.entry(.session(first)).id)
        } else { openRunningEntry() }
    }

    private func openRunningEntry() {
        for moment in moments {
            if case .entry(.session(let session)) = moment, session.isRunning {
                opened.ids.insert(moment.id)
            }
        }
    }

    // MARK: - One entry

    @ViewBuilder private func row(_ entry: DayEntry, isFirst: Bool, isLast: Bool) -> some View {
        switch entry {
        case .session(let session):
            let key = StoryMoment.entry(entry).id
            let isOpen = opened.ids.contains(key)
            let isCurrentStoryDay = projection?.isCurrentDay ?? store.isToday
            let live = DayStorySessionPresentation.make(
                session: session, isCurrentStoryDay: isCurrentStoryDay, store: store)
            let detail = isOpen
                ? (projection?.sessionDetails[session.id] ?? store.storySessionDetail(session,
                    on: projection?.date ?? store.selectedDay))
                : nil
            let recordIDs = session.recordIDs.isEmpty ? [session.id] : session.recordIDs
            let power = store.powerSummary(for: recordIDs,
                interval: DateInterval(start: session.start, end: max(session.start, session.end)))
            storyRow(time: session.start,
                     tint: Tokens.Palette.workType(session.workType),
                     dotSize: session.isRunning ? 13 : 11,
                     isFirst: isFirst, isLast: isLast) {
                SessionEntryCard(session: session,
                                 apps: detail?.apps ?? [],
                                 shape: detail?.text,
                                 shapeCaption: detail?.caption,
                                 activity: detail?.activity,
                                 appColourIndices: projection?.appColourIndices
                                    ?? store.storyAppColourIndices,
                                 canContinue: store.canContinue(session),
                                 // A stretch of the thread running now is neither continued
                                 // nor started again: it is already going.
                                 canStartNewSession: store.canStartNewSession(session)
                                    && !store.isThreadRunning(session.threadID),
                                 isOpen: isOpen,
                                 clock: live.clock,
                                 liveStatus: live.liveStatus,
                                 powerSummary: power,
                                 noteRecordIDs: recordIDs,
                                 metadataStore: store,
                                 onToggle: { toggle(key) },
                                 onRename: { store.renameSession(session, to: $0) },
                                 onWorkType: { store.setWorkType($0, for: session) },
                                 onContinue: { store.continueSession(session) },
                                 onStartNewSession: { store.startNewSession(from: session) },
                                 onRemove: store.canRemoveSession(session)
                                    ? { store.removeSession(session) } : nil,
                                 removeBlockReason: store.removalBlockReason(for: session),
                                 pauseTitle: live.pauseTitle,
                                 onPause: live.canControl ? { store.togglePause() } : nil,
                                 onEnd: live.canControl ? { store.stop() } : nil,
                                 minimumRecorded: store.engine.store.minimumRecordedSession)
            }
        case .rest(let rest):
            storyRow(time: rest.start,
                     tint: Tokens.Palette.workType(.breakTime),
                     dotSize: 7,
                     isFirst: isFirst, isLast: isLast) {
                RestEntryRow(store: store, rest: rest)
            }
        }
    }

    private func storyRow<Content: View>(time: Date,
                                         tint: Color,
                                         dotSize: CGFloat,
                                         isFirst: Bool,
                                         isLast: Bool,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if showsTimes {
              // Centred on the same line as the dot, whatever the dot's size,
              // rather than pushed down by a fixed padding that only matched
              // the small ones.
              Text(Tokens.timeOfDayOnly(time))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: timeColumn, height: DayStory.dotCentre * 2, alignment: .trailing)
                .accessibilityHidden(true)
            }
            rail(tint: tint, dotSize: dotSize, isFirst: isFirst, isLast: isLast)
                .frame(width: railColumn)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Tokens.Space.m)
        }
    }

    /// One continuous rule down the story, with this entry's dot on it. The
    /// first and last rows stop the rule at their own dot so the line has ends
    /// rather than running into the page.
    /// Where every dot's centre sits below the row's top, and the line the
    /// time label is centred on.
    static let dotCentre: CGFloat = 19

    private func rail(tint: Color, dotSize: CGFloat, isFirst: Bool, isLast: Bool) -> some View {
        GeometryReader { geometry in
            let dotCentre = DayStory.dotCentre
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Tokens.Colour.line)
                    .frame(width: 2)
                    .padding(.top, isFirst ? dotCentre : 0)
                    .padding(.bottom, isLast ? max(0, geometry.size.height - dotCentre) : 0)
                Circle()
                    .fill(tint)
                    .frame(width: dotSize, height: dotSize)
                    .background(Circle().fill(StoryStyle.canvas)
                        .frame(width: dotSize + 6, height: dotSize + 6))
                    .background {
                        if dotSize >= 13 {
                            Circle().fill(tint.opacity(0.16))
                                .frame(width: dotSize + 12, height: dotSize + 12)
                        }
                    }
                    .offset(y: dotCentre - dotSize / 2)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    /// Only today has something to suggest. A past day's headline already says
    /// nothing was recorded, and with recording off the banner above says so.
    @ViewBuilder private var empty: some View {
        if store.isToday {
            Text(store.isTrackingEnabled
                 ? "Start a focus session, or let app recording build the day's story."
                 : "Start a focus session to begin the day's story.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .padding(.vertical, Tokens.Space.m)
        }
    }

    private func toggle(_ id: String) {
        let opening = !opened.ids.contains(id)
        withAnimation(Tokens.Motion.animation(opening ? Tokens.Motion.reveal : Tokens.Motion.dismiss,
                                              reduceMotion: reduceMotion)) {
            if opening { opened.ids.insert(id) } else { opened.ids.remove(id) }
        }
    }
}

/// One focus session in the story. Closed it is a title, a type and a duration;
/// opened it shows the apps that made it up and what the app can say about its
/// shape. A running session carries the live clock instead of a total.
struct SessionEntryCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var unfold: AnyTransition {
        Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion)
    }

    let session: DaySession
    let apps: [AppRank]
    /// What the recording shows, when it shows anything.
    var shape: String?
    var shapeCaption: String?
    var activity: RecordedActivity?
    var appColourIndices: [String: Int] = [:]
    var canContinue = false
    var canStartNewSession = false
    let isOpen: Bool
    let clock: String?
    var liveStatus: String?
    var powerSummary: PowerContextSummary?
    var noteRecordIDs: [UUID] = []
    var metadataStore: SessionStore?
    let onToggle: () -> Void
    var onRename: ((String) -> Bool)?
    var onWorkType: ((WorkType) -> Bool)?
    var onContinue: (() -> Void)?
    var onStartNewSession: (() -> Void)?
    var onRemove: (() -> Void)?
    /// Set when Remove is shown but cannot act yet; the button says why.
    var removeBlockReason: String?
    var pauseTitle = "Pause"
    var onPause: (() -> Void)?
    var onEnd: (() -> Void)?
    /// The shortest stretch the archive keeps, for the Stop button's help.
    var minimumRecorded: TimeInterval = FocusConstants.minimumRecordedSession
    /// Renaming happens in the card, in place, rather than in a sheet.
    @StateObject private var editing = BoolBox()
    @StateObject private var draft = TextBox()
    @StateObject private var picking = BoolBox()
    @StateObject private var confirmingRemoval = BoolBox()
    @StateObject private var titleWidth = WidthBox()
    @FocusState private var renameFocused: Bool
    @FocusState private var renameActionFocused: Bool
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.openSessionReport) private var openSessionReport
    @Environment(\.sessionControlsVisible) private var sessionControlsVisible

    private var tint: Color { Tokens.Palette.workType(session.workType) }

    /// A tiny interval should remain readable as factual text. A chart shorter
    /// than two minutes turns a few seconds of evidence into visual noise.
    private var showsActivityStrip: Bool {
        guard let activity else { return false }
        return activity.hasRecordedActivity && activity.elapsed >= 120
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Button(action: onToggle) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text(session.workType.sessionTitle(named: session.name))
                            .font(Tokens.Typography.rowTitle)
                            .lineLimit(2)
                            // The pencil is placed by this width, so it sits
                            // at the end of the name and not after the wider
                            // category line beneath it.
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: TitleWidthKey.self, value: proxy.size.width)
                            })
                            // Room for the pencil beside a long name.
                            .padding(.trailing, isOpen && (onRename != nil || onWorkType != nil) ? 30 : 0)
                        HStack(spacing: Tokens.Space.s) {
                            // An unnamed session is titled by its category already.
                            if !session.name.isEmpty {
                                Text(session.workType.displayName)
                                    .font(Tokens.Typography.microLabel)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                                    .foregroundStyle(StoryStyle.workTypeInk(session.workType))
                            }
                            Text(liveStatus ?? Tokens.timeRange(session.start, session.end))
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                            if session.stretches > 1 {
                                Text("· \(session.stretches) stretches")
                                    .font(Tokens.Typography.metadata)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(StoryStyle.entryInsets(for: density))
                    .contentShape(Rectangle())
                }
                .buttonStyle(StoryPressStyle())
                // The card's one toggle for VoiceOver. The duration button
                // beside it opens the same detail and is hidden, so the card
                // is heard once and the running clock is not read every second.
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
                .accessibilityHint(isOpen ? "Hide this session's detail" : "Show this session's detail")
                .onPreferenceChange(TitleWidthKey.self) { titleWidth.value = $0 }
                // The pencil sits by the name it edits: rename and category
                // in one place, rather than two buttons in the action row.
                .overlay(alignment: .topLeading) {
                    if isOpen, onRename != nil || onWorkType != nil {
                        let insets = StoryStyle.entryInsets(for: density)
                        // Quiet: a small secondary glyph that only gains a
                        // disc under the pointer, so the name stays the
                        // loudest thing on its line.
                        Button {
                            if editing.value { finishRenaming() } else { beginEditing() }
                        } label: {
                            Image(systemName: editing.value ? "checkmark.circle.fill" : "pencil")
                                .font(.system(size: editing.value ? 15 : 12, weight: .medium))
                                .foregroundStyle(editing.value ? AnyShapeStyle(StoryStyle.action)
                                                               : AnyShapeStyle(.secondary))
                                // A full-size target around the same glyph;
                                // the offset below takes back the extra 3pt
                                // so the glyph stays where it was.
                                .frame(width: AccessibilityMetrics.minimumTargetSize,
                                       height: AccessibilityMetrics.minimumTargetSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(StoryPressStyle(hovers: true,
                                                     cornerRadius: AccessibilityMetrics.minimumTargetSize / 2))
                        .offset(x: insets.leading + titleWidth.value + Tokens.Space.xs - 3, y: insets.top - 4)
                        .help(editing.value ? "Done editing" : "Rename or change the category")
                        .accessibilityLabel(editing.value ? "Done editing" : "Edit name and category")
                        .focused($renameActionFocused)
                    }
                }
                Button(action: onToggle) {
                    HStack(alignment: .top, spacing: Tokens.Space.m) {
                        Spacer(minLength: Tokens.Space.s)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(clock ?? Tokens.preciseDuration(session.worked))
                                .font(Tokens.Typography.metadata.weight(clock == nil ? .regular : .semibold)
                                    .monospacedDigit())
                                .foregroundStyle(clock == nil ? AnyShapeStyle(.secondary)
                                                              : AnyShapeStyle(StoryStyle.workTypeInk(session.workType)))
                                .contentTransition(.numericText())
                            if let powerSummary {
                                Label(powerSummary.headline, systemImage: powerSummary.symbolName)
                                    .font(Tokens.Typography.microLabel.weight(.regular)).foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(Tokens.Typography.microLabel)
                            .foregroundStyle(.secondary)
                    }
                    .padding(StoryStyle.entryInsets(for: density))
                    .contentShape(Rectangle())
                }
                .buttonStyle(StoryPressStyle())
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isOpen { detail.transition(unfold) }
        }
        .background(StoryStyle.card,
                    in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous)
            .strokeBorder(clock != nil ? tint.opacity(0.30) : Tokens.Colour.line,
                          lineWidth: clock != nil ? 1.5 : 1))
        .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
        .accessibilityElement(children: .contain)
    }

    /// Everything the closed card shows, in one sentence: the hidden duration
    /// button's figures are said here instead.
    private var accessibilityLabel: String {
        var parts = [session.workType.sessionTitle(named: session.name),
                     session.workType.displayName]
        parts.append(session.isRunning
                     ? "\(liveStatus ?? "running"), started \(Tokens.timeOfDayOnly(session.start))"
                     : Tokens.timeRange(session.start, session.end))
        parts.append(Tokens.spent(session.worked))
        if session.stretches > 1 { parts.append("\(session.stretches) stretches") }
        if let powerSummary { parts.append(powerSummary.headline) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var detail: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Divider()
            if clock != nil {
                HStack(alignment: .center, spacing: 20) {
                    // With detail loaded and nothing to add (recording off:
                    // the day's banner says so), the line stays empty rather
                    // than promising recording that will not come.
                    Text(shapeCaption ?? (activity == nil
                                          ? "Recording will appear here as the session continues." : ""))
                        .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsActivityStrip, let activity {
                        StoryShapeChart(activity: activity, appColourIndices: appColourIndices,
                                        height: 28, compact: true)
                            .frame(width: 130)
                    }
                }
                reportLink()
            } else {
                HStack(alignment: .top, spacing: 20) {
                    appsDetail.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    if showsActivityStrip {
                        activityDetail.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                if !showsActivityStrip { factualCaption }
                if apps.count <= 4 { reportLink() }
            }
            actions
            metadataDetail
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 13)
    }

    private var appsDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !apps.isEmpty {
                sectionLabel("Apps in this stretch")
                ForEach(Array(apps.prefix(4).enumerated()), id: \.element.id) { index, app in
                    StoryAppRow(app: app, rank: appColourIndices[app.bundleID] ?? index)
                }
                if apps.count > 4 {
                    // The one door to the report, put where the question
                    // comes up: what were the other nine?
                    reportLink(prefix: "\(apps.count - 4) more app\(apps.count - 4 == 1 ? "" : "s")",
                               title: "See all")
                }
            }
        }
    }

    /// The single way into the full report. "See all" when it finishes the
    /// thought "N more apps"; "See full report" where nothing is cut short,
    /// so the report is reachable from every kind of card, running included.
    @ViewBuilder private func reportLink(prefix: String? = nil, title: String = "See full report") -> some View {
        if let openSessionReport {
            HStack(spacing: Tokens.Space.xs) {
                if let prefix {
                    Text(prefix)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                Button(title) { openSessionReport(session) }
                    .buttonStyle(StoryLinkStyle())
                    .accessibilityLabel("See the full report for this session")
            }
        }
    }

    private var activityDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("App activity")
            if let activity {
                StoryShapeChart(activity: activity, appColourIndices: appColourIndices)
            }
            factualCaption
        }
        .help(shape ?? "Only recorded app use is shown; no keyboard activity is inferred.")
    }

    @ViewBuilder private var factualCaption: some View {
        if let shape {
            Text(shape)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let shapeCaption {
            Text(shapeCaption)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Tokens.Typography.microLabel)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    /// The corrections that belong to this entry. Each one writes to the
    /// record, so only the actions the record can actually carry are offered.
    @ViewBuilder private var actions: some View {
        if onRename != nil || onWorkType != nil || onContinue != nil || noteTargetID != nil {
            Color.clear.frame(height: 2)
            if editing.value {
                // Name and category together: what the pencil opened.
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    if onRename != nil { renameField }
                    if let onWorkType { workTypeChoices(onWorkType) }
                }
            } else {
                HStack(spacing: Tokens.Space.m) {
                    if let onContinue, canContinue {
                        actionButton("Continue this", action: onContinue)
                    } else if let onStartNewSession, canStartNewSession {
                        actionButton("Start again", action: onStartNewSession)
                            .help("Starts a fresh session with this name and category.")
                    }
                    if let recordID = noteTargetID, let metadataStore {
                        actionButton(metadataStore.sessionMetadata(for: recordID)?.note == nil
                                     ? "Add note" : "Edit note") {
                            metadataStore.beginNoteEditing(for: recordID)
                        }
                    }
                    if onRemove != nil || removeBlockReason != nil {
                        Button("Remove") { confirmingRemoval.value = true }
                            .buttonStyle(StoryActionStyle(tint: Tokens.Colour.danger))
                            .disabled(onRemove == nil)
                            .help(removeBlockReason
                                  ?? "Takes this session out of the record. Its time reads as outside sessions; Undo puts it back.")
                            .accessibilityHint(removeBlockReason ?? "Removes this session; Undo is offered in the story.")
                            .confirmationDialog("Remove this session?", isPresented: $confirmingRemoval.value) {
                                Button("Remove session", role: .destructive) { onRemove?() }
                                Button("Keep", role: .cancel) {}
                            } message: {
                                Text("Every stretch of “\(session.workType.sessionTitle(named: session.name))” "
                                     + "leaves the record and its time reads as outside sessions. "
                                     + "App use stays. Undo is offered in the story.")
                            }
                    }
                    Spacer(minLength: 0)
                    // The strip, when it is up, already has these two.
                    if !sessionControlsVisible {
                        if let onPause { actionButton(pauseTitle, action: onPause) }
                        if let onEnd {
                            actionButton("Stop", action: onEnd)
                                .help("Ends this session and records it. A stretch under "
                                      + "\(Int(minimumRecorded)) seconds is not kept.")
                        }
                    }
                }
            }
            // Said where the decision is made: Remove states its own scope in
            // its confirmation, and a note belongs to one stretch.
            if editing.value {
                Text("Name and category changes apply to all stretches of this session, including other days.")
                    .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func beginEditing() {
        draft.text = session.name
        renameActionFocused = false
        renameFocused = false
        editing.value = true
        picking.value = true
    }

    private var noteTargetID: UUID? { noteRecordIDs.last }

    @ViewBuilder private var metadataDetail: some View {
        if let metadataStore,
           let error = metadataStore.powerMetadataError(for: noteRecordIDs) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(Tokens.Colour.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Session power metadata error. \(error)")
        }
        if let detail = powerSummary?.detail {
            Text(detail).font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Recorded power context. \(detail)")
        }
        if let metadataStore {
            ForEach(noteRecordIDs, id: \.self) { recordID in
                if let note = metadataStore.sessionMetadata(for: recordID)?.note,
                   !metadataStore.expandedNoteEditorIDs.contains(recordID) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text(note).font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button { metadataStore.beginNoteEditing(for: recordID) } label: {
                            Text("Edit")
                                .frame(minWidth: AccessibilityMetrics.minimumTargetSize,
                                       minHeight: AccessibilityMetrics.minimumTargetSize,
                                       alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(StoryPressStyle()).font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                            .accessibilityLabel("Edit note for stretch \(noteRecordIDs.firstIndex(of: recordID).map { $0 + 1 } ?? 1)")
                    }
                }
                if metadataStore.expandedNoteEditorIDs.contains(recordID) {
                    SessionNoteEditor(store: metadataStore, recordID: recordID)
                }
            }
        }
    }

    /// The kinds of work, offered in the card. Correcting a session to a break
    /// is offered too — the record should be able to say it was not work.
    private func workTypeChoices(_ pick: @escaping (WorkType) -> Bool) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            ForEach(WorkType.allCases) { type in
                let isCurrent = type == session.workType
                Button {
                    _ = pick(type)
                } label: {
                    // The current kind is marked by a tick as well as its
                    // tint, and drawn in the darker ink that reads on it.
                    Label(type.displayName, systemImage: isCurrent ? "checkmark" : type.symbolName)
                        .font(Tokens.Typography.microLabel)
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.vertical, Tokens.Space.xs)
                        .background(isCurrent ? Tokens.Palette.workType(type).opacity(0.18)
                                              : Tokens.Colour.elevated,
                                    in: Capsule())
                        .foregroundStyle(isCurrent ? AnyShapeStyle(StoryStyle.workTypeInk(type))
                                                   : AnyShapeStyle(.secondary))
                        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(StoryPressStyle())
                .disabled(isCurrent)
                .accessibilityLabel("Record this as \(type.displayName)")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private var renameField: some View {
        HStack(spacing: Tokens.Space.s) {
            TextField("Name this work", text: $draft.text)
                .textFieldStyle(.roundedBorder)
                .font(Tokens.Typography.metadata)
                .onSubmit(commitRename)
                .focused($renameFocused)
                .onAppear {
                    // The field must be installed before requesting focus.
                    // An eager true value is lost when the Rename button leaves
                    // the key-view loop during this same update.
                    DispatchQueue.main.async {
                        if editing.value { renameFocused = true }
                    }
                }
                .accessibilityLabel("Name this work")
            Button("Save name", action: commitRename)
                .font(Tokens.Typography.metadata.weight(.semibold))
                .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || draft.text.trimmingCharacters(in: .whitespacesAndNewlines) == session.name)
            Button("Done", action: finishRenaming)
                .font(Tokens.Typography.metadata)
        }
        .onExitCommand(perform: finishRenaming)
    }

    private func commitRename() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // A saved name keeps the editor open: the category may be next.
        if onRename?(trimmed) == true { draft.text = trimmed }
    }

    private func finishRenaming() {
        renameFocused = false
        editing.value = false
        picking.value = false
        DispatchQueue.main.async { renameActionFocused = true }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StoryActionStyle(tint: title == pauseTitle && onPause != nil
                                          ? StoryStyle.workTypeInk(session.workType) : nil))
    }
}

/// One editable string. `@State` is unavailable on this toolchain, so even a
/// single draft needs an object behind it.
final class TextBox: ObservableObject {
    @Published var text = ""
}

/// A measured width, for placing one view at the end of another's text.
final class WidthBox: ObservableObject {
    @Published var value: CGFloat = 0
}

private struct TitleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Rest is not work, so it is a quiet row rather than a card: named where the
/// user named it, and never coloured like a session.
struct RestEntryRow: View {
    @ObservedObject var store: SessionStore
    let rest: RestEntry

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Text(Self.label(rest.name))
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Space.s)
            Text(Tokens.preciseDuration(rest.length))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
            StoryLegacyBreakActions(store: store, rest: rest)
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Self.label(rest.name)), \(Tokens.spent(rest.length)), "
                            + Tokens.timeRange(rest.start, rest.end))
    }

    /// An unnamed break is already called one; only a name the user gave is
    /// worth putting before the explanation.
    static func label(_ name: String) -> String {
        name.isEmpty || name == "Break"
            ? "Recorded break, not counted as focus"
            : "\(name) — recorded break, not counted as focus"
    }
}

/// The unresolved gap, asked where it happened. The answers are the existing
/// canonical decisions; this is a placement, not a new verdict.
struct AwayEntryCard: View {
    let away: TimeInterval
    let range: (start: Date, end: Date)?
    let note: String?
    var error: String?
    var onRetry: (() -> Void)?
    let onAnswer: (UserDecision) -> Bool
    let onReason: (String) -> Bool

    var body: some View {
        AwayAnswerGrid(away: away, range: range, note: note, error: error, onRetry: onRetry,
                       onAnswer: onAnswer, onReason: onReason)
            .padding(Tokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colour.attention.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.attention.opacity(0.35)))
    }
}
