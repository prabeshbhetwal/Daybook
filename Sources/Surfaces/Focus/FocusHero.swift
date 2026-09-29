import SwiftUI

/// The single action that dominates a Focus hero. Awaiting a decision has no
/// ordinary primary action because the evidence-preserving answer grid takes
/// over the whole control area.
enum FocusPrimaryAction: Equatable {
    case start
    case pause
    case resume
}

/// Presentation-level Focus state. Watching is intentionally distinct from a
/// manual pause even though both are represented by `SessionState.paused` in
/// Core: the user needs to know why the clock stopped without reinterpreting
/// any accounting state inside a view.
enum FocusSurfaceMode: Equatable {
    case idle
    case running
    case paused
    case watching
    case awaitingDecision

    init(state: SessionState) {
        switch state {
        case .idle:
            self = .idle
        case .running:
            self = .running
        case .paused(reason: .watching):
            self = .watching
        case .paused:
            self = .paused
        case .awaitingUserDecision:
            self = .awaitingDecision
        }
    }

    var primaryPrompt: String {
        switch self {
        case .idle: return "Ready to focus"
        case .running: return "Focus in progress"
        case .paused: return "Ready to continue?"
        case .watching: return "Watching quietly"
        case .awaitingDecision: return "What happened while you were away?"
        }
    }

    var primaryAction: FocusPrimaryAction? {
        switch self {
        case .idle: return .start
        case .running: return .pause
        case .paused, .watching: return .resume
        case .awaitingDecision: return nil
        }
    }

    var showsOrdinaryControls: Bool { self != .awaitingDecision }
}

/// One composition decision for every Focus consumer. This guards the content
/// outside the hero as well as the hero itself, so an unresolved away question
/// cannot be bypassed through a continuation or automatic-session correction.
struct FocusSurfaceComposition: Equatable {
    let mode: FocusSurfaceMode
    let showsContinuationSection: Bool
    let showsAutomaticSessionControls: Bool

    init(state: SessionState,
         hasPendingDecision: Bool,
         isAutomatic: Bool) {
        mode = hasPendingDecision ? .awaitingDecision : FocusSurfaceMode(state: state)
        showsContinuationSection = mode.showsOrdinaryControls
        showsAutomaticSessionControls = isAutomatic
            && mode != .idle
            && mode.showsOrdinaryControls
    }
}

extension SessionStore {
    /// Every Focus surface reads this same presentation boundary. `pendingAway`
    /// also covers the preview path whose engine state remains running.
    var focusSurfaceComposition: FocusSurfaceComposition {
        FocusSurfaceComposition(state: state,
                                hasPendingDecision: hasUnresolvedAwayDecision,
                                isAutomatic: isAutoSession)
    }

    var focusOperationFailure: FocusOperationFailureState? {
        guard pendingAwaySaveError == nil, let correctionError else { return nil }
        // History kept read-only refuses every write, so a retry can only
        // fail again; the message itself says where to look instead.
        return FocusOperationFailureState(message: correctionError,
                                          hasOriginBoundRetry: correctionRetry != nil
                                              && !engine.archive.isReadOnly)
    }

    /// Executes the tested state-to-primary-action contract. The hero's
    /// filled button and the Session menu both run this, so a command from
    /// the keyboard does exactly what the visible button does.
    func performFocusPrimaryAction() {
        switch focusSurfaceComposition.mode.primaryAction {
        case .start:
            start()
        case .pause:
            togglePause()
        case .resume:
            isAway ? endAway() : togglePause()
        case nil:
            break
        }
    }
}

struct FocusOperationFailureState: Equatable {
    let message: String
    let hasOriginBoundRetry: Bool
}

struct CompactGoalPresentation: Equatable {
    let visible: String
    let short: String
    let bare: String
    let accessibility: String

    init(_ goal: GoalProgress) {
        let achieved = Tokens.preciseDuration(goal.achieved)
        let target = Tokens.preciseDuration(goal.goal)
        // Nil where there is nothing to compare against: a line reading
        // "Pace unavailable" states an absence the reader cannot act on.
        let shortPace: String?
        let fullPace: String
        if goal.isMet {
            shortPace = "Goal met"
            fullPace = "Daily goal met"
        } else if let ahead = goal.aheadBy {
            if ahead >= 60 {
                let duration = Tokens.preciseDuration(ahead)
                shortPace = "\(duration) ahead"
                fullPace = "\(duration) ahead of your usual pace"
            } else if ahead <= -60 {
                let duration = Tokens.preciseDuration(-ahead)
                shortPace = "\(duration) behind"
                fullPace = "\(duration) behind your usual pace"
            } else {
                shortPace = "Usual pace"
                fullPace = "On your usual pace"
            }
        } else {
            shortPace = nil
            fullPace = "Pace comparison appears after enough comparable history."
        }
        visible = shortPace.map { "Today · \(achieved) / \(target) · \($0)" }
            ?? "Today · \(achieved) / \(target)"
        // The same line with less room: first without the day, then without
        // the pace. The strip is today by definition, and the pace is in the
        // spoken label whichever is drawn.
        short = shortPace.map { "\(achieved) / \(target) · \($0)" } ?? "\(achieved) / \(target)"
        bare = "\(achieved) / \(target)"
        accessibility = "Daily goal. \(achieved) of \(target). \(fullPace)"
    }
}

/// The shared operational hero. Desktop and menu-bar surfaces use the same
/// state branches and actions; `compact` changes measure and spacing only.
/// Which part of the window's bar a hero draws: the row of controls in the
/// chrome, or the line under it that exists only while there is a question
/// or a note to show.
enum FocusHeroChromePart: Equatable {
    case row
    case underline
}

struct FocusHero: View {
    @ObservedObject var store: SessionStore
    var intentFocused: FocusState<Bool>.Binding
    var compact = false
    /// Whether this consumer has a window's worth of horizontal room. `compact`
    /// alone cannot say it: the menu-bar popover is compact and 340pt wide,
    /// while the window's session strip is compact and never narrower than
    /// 980pt. The flag existed unread until the strip started using it.
    var wide = true
    /// Whether the strip shows today's goal. The window turns it off where
    /// the rail's goal card already shows the same goal.
    var showsGoal = true
    /// nil draws the full hero; a part draws only that part of the chrome.
    var chromePart: FocusHeroChromePart?
    /// Start and Pause are one pill that changes its word.
    @Namespace private var primaryPill

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var composition: FocusSurfaceComposition { store.focusSurfaceComposition }
    private var mode: FocusSurfaceMode { composition.mode }
    /// The window's session strip: compact spacing, toolbar layout.
    private var isStrip: Bool { compact && wide }
    private var isQuiet: Bool { mode == .paused || mode == .watching }
    /// What the clocks roll on. Rolling on the seconds ran a digit animation
    /// every second in the corner of the reader's eye; the seconds now swap
    /// plainly and only a new minute rolls.
    private var elapsedMinutes: Int? { DurationText.wholeSeconds(store.elapsed).map { $0 / 60 } }

    var body: some View {
        switch chromePart {
        case .row: chromeRow
        case .underline: chromeUnderline
        case nil: fullBody
        }
    }

    private var fullBody: some View {
        VStack(alignment: compact ? .leading : .center,
               spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
            if mode.showsOrdinaryControls {
                ordinaryBody
            } else {
                decisionBody
            }
            if let failure = store.focusOperationFailure {
                FocusOperationFailure(store: store, failure: failure)
            }
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
        // Start, pause, resume: the controls for one state give way to the
        // controls for the next rather than snapping.
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: mode)
    }

    // MARK: - The chrome

    /// The bar's centre: what begins, pauses or ends a session, in one row
    /// that never changes height. Idle, the activity, its category and
    /// Start; live, the clock, the session's name and its controls, in the
    /// same place. Start is the pill that becomes Pause; the field gives way
    /// to the name; the clock slides in from the left.
    private var chromeRow: some View {
        HStack(spacing: Tokens.Space.m) {
            if mode == .idle {
                idleRowLead
                    .transition(Tokens.Motion.transition(
                        .opacity.combined(with: .scale(scale: 0.96)), reduceMotion: reduceMotion))
            } else {
                liveRowLead
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion), value: mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session controls")
    }

    /// Under the bar, only while there is something the row cannot hold: the
    /// away question, a note the reader is being held to, the automatic
    /// session's Adopt and Undo, a save that failed.
    private var chromeUnderline: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if !mode.showsOrdinaryControls { decisionBody }
            stripWrapLines
            if let failure = store.focusOperationFailure {
                FocusOperationFailure(store: store, failure: failure)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion), value: mode)
    }

    /// Whether the underline has anything to draw for this store.
    static func underlineHasContent(_ store: SessionStore) -> Bool {
        let composition = store.focusSurfaceComposition
        return !composition.mode.showsOrdinaryControls
            || detail(for: composition.mode, store: store) != nil
            || composition.showsAutomaticSessionControls
            || store.focusOperationFailure != nil
    }

    @ViewBuilder private var ordinaryBody: some View {
        if isStrip {
            stripRow
        } else {
            switch mode {
            case .idle:
                idleBody
            case .running:
                activeBody
            case .paused:
                pausedBody
            case .watching:
                watchingBody
            case .awaitingDecision:
                EmptyView()
            }
        }
    }

    // MARK: - The window strip

    /// The strip is a toolbar, not a page. Stacked, the same content stood
    /// 225pt tall in a 680pt window and left Pin and Close 468pt away from the
    /// controls they govern, with nothing in between. One row spends the width
    /// the window already has instead of height the day's story needs:
    /// the action cluster anchors the leading edge, the day's standing the
    /// trailing one, and the slack falls between them where slack belongs.
    private var stripRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.l) {
                if mode == .idle { idleRowLead } else { liveRowLead }
                Spacer(minLength: Tokens.Space.m)
                if showsGoal { goalSupport }
            }
            stripWrapLines
        }
    }

    @ViewBuilder private var idleRowLead: some View {
        if chromePart == nil {
            Text(mode.primaryPrompt)
                .font(Tokens.Typography.rowTitle)
                .fixedSize()
        }
        ActivityChooser(store: store, intentFocused: intentFocused, compact: true) {
            performPrimaryAction()
        }
        // A text field's ideal width is not its placeholder's, so the row
        // gave it 236pt and "Choose or type an activity" lost its last
        // letters behind the menu. The floor fits the prompt; priority makes
        // the row's slack go here before it goes to the spacer.
        .frame(minWidth: 280, idealWidth: 280, maxWidth: Tokens.formMeasure)
        .layoutPriority(1)
        // No visible "Work type" caption: between the activity and Start, a
        // named work type with its own symbol reads as what it is, and the
        // caption was the only 10pt step in the row.
        WorkTypePicker(selection: $store.workType)
        StartButton(title: "Start focus", fills: false) { performPrimaryAction() }
            .fixedSize()
            .matchedGeometryEffect(id: "primary", in: primaryPill)
            .help(startHelp)
    }

    @ViewBuilder private var liveRowLead: some View {
        Text(Tokens.clock(store.elapsed))
            .font(Tokens.Typography.rowTimer)
            .rollingDigits(elapsedMinutes)
            .foregroundStyle(isQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .fixedSize()
            .elapsedClockAccessibility(store.elapsed)
            .transition(Tokens.Motion.transition(
                .move(edge: .leading).combined(with: .opacity), reduceMotion: reduceMotion))
        VStack(alignment: .leading, spacing: 1) {
            Text(store.activeIntent)
                .font(Tokens.Typography.rowTitle)
                .lineLimit(1)
            Text(liveSubtitle)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .layoutPriority(1)
        .transition(Tokens.Motion.transition(
            .opacity.combined(with: .scale(scale: 0.96)), reduceMotion: reduceMotion))
        HStack(spacing: Tokens.Space.s) { liveControls }
            .fixedSize()
            .transition(Tokens.Motion.transition(.opacity, reduceMotion: reduceMotion))
    }

    /// A running clock says "running" without a caption. A stopped one is
    /// ambiguous, so paused, away and watching name themselves.
    private var liveSubtitle: String {
        var parts: [String] = []
        if isQuiet { parts.append(store.isAway ? "Away" : mode.primaryPrompt) }
        if mode == .awaitingDecision { parts.append("Away question below") }
        parts.append(store.workType.displayName)
        if let summary = store.threadSummaryLine { parts.append(summary) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var liveControls: some View {
        switch mode {
        case .running:
            FocusActionButton(title: "Pause", symbol: "pause.fill", prominent: true) {
                performPrimaryAction()
            }
            .matchedGeometryEffect(id: "primary", in: primaryPill)
            .help(pauseHelp)
            FocusActionButton(title: "Step away", symbol: "door.right.hand.open") { store.markAway() }
                .help(awayHelp)
            FocusActionButton(title: "Stop", symbol: "stop.fill") { store.stop() }
                .help(stopHelp)
        case .paused, .watching:
            FocusActionButton(title: store.isAway ? "I'm back" : "Resume",
                              symbol: "play.fill", prominent: true) {
                performPrimaryAction()
            }
            .matchedGeometryEffect(id: "primary", in: primaryPill)
            .help(resumeHelp)
            FocusActionButton(title: "Stop", symbol: "stop.fill") { store.stop() }
                .help(stopHelp)
        case .idle, .awaitingDecision:
            EmptyView()
        }
    }

    /// Only the sentences the row cannot carry without truncating them. A
    /// recording rule the user is being held to must never end in an ellipsis.
    private var stripDetail: String? { Self.detail(for: mode, store: store) }

    static func detail(for mode: FocusSurfaceMode, store: SessionStore) -> String? {
        switch mode {
        case .running: return store.isAutoSession ? "Started automatically" : nil
        case .paused: return store.isAway ? "Nothing is counted while you are away." : nil
        case .watching:
            return "The focus clock is paused while you watch. "
                + "This time is recorded as Watching, not focus."
        case .idle, .awaitingDecision: return nil
        }
    }

    @ViewBuilder private var stripWrapLines: some View {
        if let stripDetail {
            Text(stripDetail)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if composition.showsAutomaticSessionControls { automaticControls }
    }

    // MARK: - Idle

    private var idleBody: some View {
        VStack(alignment: compact ? .leading : .center,
               spacing: compact ? Tokens.Space.s : Tokens.Space.l) {
            VStack(alignment: compact ? .leading : .center, spacing: Tokens.Space.xs) {
                Text(mode.primaryPrompt)
                    .font(compact ? Tokens.Typography.sectionTitle
                                  : Tokens.Typography.pageTitle)
                // Only a page carries a subtitle. In the popover this sentence
                // restated the field's own placeholder directly above it.
                if !compact {
                    Text("Choose an activity or write your own. Start when you're ready.")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                ActivityChooser(store: store, intentFocused: intentFocused, compact: compact) {
                    performPrimaryAction()
                }
                if compact {
                    // The category in the app's own box, so it reads as part
                    // of the panel rather than a greyed AppKit control, with
                    // Start taking the rest of the row.
                    HStack(spacing: Tokens.Space.s) {
                        WorkTypePicker(selection: $store.workType, quiet: true)
                        StartButton(title: "Start focus", fills: true) { performPrimaryAction() }
                            .help(startHelp)
                    }
                } else {
                    HStack(spacing: Tokens.Space.s) {
                        Text("Category")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                        WorkTypePicker(selection: $store.workType)
                        Spacer(minLength: Tokens.Space.s)
                        StartButton(title: "Start focus", fills: false) {
                            performPrimaryAction()
                        }
                        .fixedSize()
                        .help(startHelp)
                    }
                }
                // A note about what happens after an action the reader has not
                // taken yet belongs on the page that has room to explain, not
                // under the button in a 340pt panel.
                if !compact {
                    Text("Names you start will appear in the activity menu next time.")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: Tokens.formMeasure)
            goalSupport
        }
    }

    // MARK: - Live and paused states

    private var activeBody: some View {
        operationalBody(title: mode.primaryPrompt,
                        detail: store.isAutoSession ? "Started automatically" : nil,
                        quiet: false) {
            FocusActionButton(title: "Pause", symbol: "pause.fill", prominent: true) {
                performPrimaryAction()
            }
            .help(pauseHelp)
            FocusActionButton(title: "Step away", symbol: "door.right.hand.open") {
                store.markAway()
            }
            .help(awayHelp)
            FocusActionButton(title: "Stop", symbol: "stop.fill") {
                store.stop()
            }
            .help(stopHelp)
        }
    }

    private var pausedBody: some View {
        operationalBody(
            title: store.isAway ? "Away" : mode.primaryPrompt,
            detail: store.isAway
                ? "Nothing is counted while you are away."
                : "The focus clock is paused.",
            quiet: true
        ) {
            FocusActionButton(title: store.isAway ? "I'm back" : "Resume",
                              symbol: "play.fill", prominent: true) {
                performPrimaryAction()
            }
            .help(resumeHelp)
            FocusActionButton(title: "Stop", symbol: "stop.fill") {
                store.stop()
            }
            .help(stopHelp)
        }
    }

    private var watchingBody: some View {
        operationalBody(
            title: mode.primaryPrompt,
            detail: "The focus clock is paused while you watch. This time is recorded as Watching, not focus.",
            quiet: true
        ) {
            FocusActionButton(title: "Resume", symbol: "play.fill", prominent: true) {
                performPrimaryAction()
            }
            .help(resumeHelp)
            FocusActionButton(title: "Stop", symbol: "stop.fill") {
                store.stop()
            }
            .help(stopHelp)
        }
    }

    private func operationalBody<Controls: View>(
        title: String,
        detail: String?,
        quiet: Bool,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(alignment: compact ? .leading : .center,
               spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
            Text(title)
                .font(Tokens.Typography.metadata.weight(.semibold))
                // The focus ink: system blue at this size was under 4.5:1
                // on the panel in both appearances.
                .foregroundStyle(quiet ? AnyShapeStyle(.secondary)
                                       : AnyShapeStyle(StoryStyle.focus))
            Text(Tokens.clock(store.elapsed))
                .font(Tokens.Typography.liveTimer)
                .monospacedDigit()
                .rollingDigits(elapsedMinutes)
                .foregroundStyle(quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .elapsedClockAccessibility(store.elapsed)
            VStack(alignment: compact ? .leading : .center, spacing: 2) {
                Text(store.activeIntent)
                    .font(compact ? Tokens.Typography.rowTitle : Tokens.Typography.sectionTitle)
                    .lineLimit(1)
                Label(store.workType.displayName, systemImage: store.workType.symbolName)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                if let summary = store.threadSummaryLine {
                    Text(summary)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(compact ? .leading : .center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Tokens.Space.s) {
                controls()
            }
            goalSupport
            if composition.showsAutomaticSessionControls {
                automaticControls
            }
        }
    }

    private var automaticControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Divider()
            // While running, "Started automatically" is the line above; paused,
            // nothing else says the session was automatic.
            Text(mode == .running ? "Name this session, reclassify it, or discard it."
                                  : "Name or reclassify this automatic session, or discard it.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            if compact {
                automaticIntentField
                HStack(spacing: Tokens.Space.s) {
                    WorkTypePicker(selection: $store.workType)
                    Spacer(minLength: Tokens.Space.xs)
                    automaticAdoptButton
                }
                automaticUndoButton
            } else {
                HStack(spacing: Tokens.Space.s) {
                    automaticIntentField
                    WorkTypePicker(selection: $store.workType)
                    automaticAdoptButton
                    automaticUndoButton
                }
            }
        }
        .frame(maxWidth: compact ? .infinity : 620, alignment: .leading)
    }

    private var automaticIntentField: some View {
        IntentField(text: $store.intent) { store.applyAutomaticSessionCorrection() }
            .focused(intentFocused)
            .padding(.horizontal, Tokens.Space.s)
            .frame(maxWidth: Tokens.formMeasure, minHeight: 30)
            .background(Tokens.Colour.elevated,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                             style: .continuous))
    }

    private var automaticAdoptButton: some View {
        FocusActionButton(title: store.startWouldContinue ? "Adopt session" : "Start new",
                          symbol: store.startWouldContinue
                              ? "checkmark" : "arrow.triangle.branch") {
            store.applyAutomaticSessionCorrection()
        }
    }

    private var automaticUndoButton: some View {
        Button(compact ? "Undo automatic session" : "Undo") {
            store.undoAutomaticSessionCorrection()
        }
        .buttonStyle(StoryPressStyle())
        .font(Tokens.Typography.metadata)
        .foregroundStyle(.secondary)
        .frame(minHeight: 28)
    }

    // MARK: - Awaiting decision

    @ViewBuilder private var decisionBody: some View {
        if let away = store.pendingAway {
            let expectedID = store.engine.pendingDecisionID
            VStack(alignment: .leading, spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
                Text(mode.primaryPrompt)
                    .font(compact ? Tokens.Typography.sectionTitle
                                  : Tokens.Typography.pageTitle)
                AwayAnswerGrid(away: away,
                               range: store.pendingAwayRange,
                               showsCaptions: !compact,
                               compact: compact,
                               note: store.continuationNote,
                               error: store.pendingAwaySaveError,
                               onRetry: { store.retryPendingAwayDecision(expectedID: expectedID) },
                               onAnswer: { store.resolve($0, expectedID: expectedID) },
                               onReason: { store.resolve(.tookBreak, label: $0, expectedID: expectedID) })
            }
            .frame(maxWidth: compact ? .infinity : 720, alignment: .leading)
        }
    }

    // MARK: - Goal support

    @ViewBuilder private var goalSupport: some View {
        if compact {
            let presentation = CompactGoalPresentation(store.goal)
            // Whichever of the three fits: the full line, the line without
            // "Today", the bare figures. Each is true; none of them is an
            // ellipsis where the pace should be.
            ViewThatFits(in: .horizontal) {
                goalText(presentation.visible)
                goalText(presentation.short)
                goalText(presentation.bare)
            }
            // Outranks the row's spacer. At equal priority the two split the
            // slack, and the goal was starved to its bare figures with 30pt
            // of room going spare beside it.
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibility)
        } else {
            HStack(spacing: Tokens.Space.s) {
                GoalRing(progress: store.goal.share,
                         diameter: 52,
                         lineWidth: 6,
                         label: "\(Int((min(store.goal.share, 9.99) * 100).rounded()))%",
                         isMet: store.goal.isMet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today · \(Tokens.preciseDuration(store.goal.achieved)) of "
                         + Tokens.preciseDuration(store.goal.goal))
                        .font(Tokens.Typography.metadata.weight(.medium).monospacedDigit())
                    Text(goalPaceLine)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(store.goal.isMet
                                         ? AnyShapeStyle(StoryStyle.successInk)
                                         : AnyShapeStyle(.secondary))
                }
            }
            .frame(maxWidth: 360, alignment: .center)
            .accessibilityElement(children: .combine)
        }
    }

    private func goalText(_ text: String) -> some View {
        Text(text)
            .font(Tokens.Typography.metadata)
            // The ink, not the swatch: system green text was about 2:1 in
            // the light appearance.
            .foregroundStyle(store.goal.isMet
                             ? AnyShapeStyle(StoryStyle.successInk)
                             : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var goalPaceLine: String {
        if store.goal.isMet { return "Daily goal met" }
        guard let ahead = store.goal.aheadBy else {
            return "Pace comparison appears after enough comparable history."
        }
        if ahead >= 60 { return "\(Tokens.duration(ahead)) ahead of your usual pace" }
        if ahead <= -60 { return "\(Tokens.duration(-ahead)) behind your usual pace" }
        return "On your usual pace"
    }

    /// Secondary actions stay explicit beside their buttons because they do
    /// not vary by mode.
    private func performPrimaryAction() {
        store.performFocusPrimaryAction()
    }

    // MARK: - Tooltips

    // Each names the Session menu shortcut that does the same thing, so the
    // keyboard route is discoverable from the pointer.

    private var startHelp: String {
        "Starts a focus session (\(SessionShortcut.start.glyphs))"
    }

    private var pauseHelp: String {
        "Pauses the focus clock (\(SessionShortcut.pauseOrResume.glyphs))"
    }

    private var resumeHelp: String {
        store.isAway
            ? "Ends your time away and starts the focus clock again (\(SessionShortcut.pauseOrResume.glyphs))"
            : "Starts the focus clock again (\(SessionShortcut.pauseOrResume.glyphs))"
    }

    /// Away is Pause that also stops recording app use: nobody is at the Mac.
    private var awayHelp: String {
        "Stops counting focus and app use until you're back (\(SessionShortcut.stepAway.glyphs))"
    }

    private var stopHelp: String {
        "Ends this session and records it. A stretch under "
            + "\(Int(store.engine.store.minimumRecordedSession)) seconds is not kept "
            + "(\(SessionShortcut.stop.glyphs))."
    }
}

private extension View {
    /// The live clock, spoken to the minute. Read to the second it changed
    /// while VoiceOver was still saying it; the trait tells VoiceOver the
    /// value moves on its own, so it is not announced as a change each time.
    func elapsedClockAccessibility(_ elapsed: TimeInterval) -> some View {
        accessibilityLabel("Elapsed")
            .accessibilityValue(Tokens.spokenElapsed(elapsed))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// General save/finalisation failures stay in every operational Focus
/// consumer. The retry remains bound to SessionStore's retained originating
/// action; this view never reconstructs a target from current state.
private struct FocusOperationFailure: View {
    @ObservedObject var store: SessionStore
    let failure: FocusOperationFailureState

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Label("Change not saved", systemImage: "exclamationmark.triangle")
                .font(Tokens.Typography.metadata.weight(.semibold))
            Text(failure.message)
                .font(Tokens.Typography.metadata)
                .fixedSize(horizontal: false, vertical: true)
            if failure.hasOriginBoundRetry {
                Button("Retry saving") { store.retryLastCorrection() }
                    .buttonStyle(StoryLinkStyle())
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            }
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.attention.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.well))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Change not saved")
    }
}

/// A word-labelled action keeps the Focus panel understandable without relying
/// on tooltip-only icon controls. Only the state-appropriate primary action is
/// filled; Step away and Stop remain quiet secondary choices.
private struct FocusActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Tokens.Typography.metadata.weight(prominent ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(prominent ? AnyShapeStyle(Tokens.Colour.focus)
                                      : AnyShapeStyle(Tokens.Colour.elevated),
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                                 style: .continuous))
                .foregroundStyle(prominent ? AnyShapeStyle(Tokens.Colour.onFocus)
                                           : AnyShapeStyle(.primary))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}
