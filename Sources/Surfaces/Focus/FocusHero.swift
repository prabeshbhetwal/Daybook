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
        return FocusOperationFailureState(message: correctionError,
                                          hasOriginBoundRetry: correctionRetry != nil)
    }
}

struct FocusOperationFailureState: Equatable {
    let message: String
    let hasOriginBoundRetry: Bool
}

struct CompactGoalPresentation: Equatable {
    let visible: String
    let accessibility: String

    init(_ goal: GoalProgress) {
        let achieved = Tokens.preciseDuration(goal.achieved)
        let target = Tokens.preciseDuration(goal.goal)
        let shortPace: String
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
            shortPace = "Pace unavailable"
            fullPace = "Pace comparison appears after enough comparable history."
        }
        visible = "Today · \(achieved) / \(target) · \(shortPace)"
        accessibility = "Daily goal. \(achieved) of \(target). \(fullPace)"
    }
}

/// The shared operational hero. Desktop and menu-bar surfaces use the same
/// state branches and actions; `compact` changes measure and spacing only.
struct FocusHero: View {
    @ObservedObject var store: SessionStore
    var intentFocused: FocusState<Bool>.Binding
    var compact = false
    var wide = true

    private var composition: FocusSurfaceComposition { store.focusSurfaceComposition }
    private var mode: FocusSurfaceMode { composition.mode }

    var body: some View {
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
    }

    @ViewBuilder private var ordinaryBody: some View {
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

    // MARK: - Idle

    private var idleBody: some View {
        VStack(alignment: compact ? .leading : .center,
               spacing: compact ? Tokens.Space.s : Tokens.Space.l) {
            VStack(alignment: compact ? .leading : .center, spacing: Tokens.Space.xs) {
                Text(mode.primaryPrompt)
                    .font(compact ? Tokens.Typography.sectionTitle
                                  : Tokens.Typography.pageTitle)
                Text("Choose an activity or write your own. Start when you're ready.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(compact ? .leading : .center)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                ActivityChooser(store: store, intentFocused: intentFocused, compact: compact) { performPrimaryAction() }
                    .padding(.horizontal, Tokens.Space.m)
                    .padding(.vertical, compact ? 8 : 10)
                    .background(Tokens.Colour.elevated,
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                                     style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                         style: .continuous)
                            .strokeBorder(Tokens.Colour.line)
                    )
                HStack(spacing: Tokens.Space.s) {
                    if compact {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Work type").font(.caption).foregroundStyle(.secondary)
                            WorkTypePicker(selection: $store.workType)
                        }
                    } else {
                        Text("Work type").font(.caption).foregroundStyle(.secondary)
                        WorkTypePicker(selection: $store.workType)
                    }
                    Spacer(minLength: Tokens.Space.s)
                    StartButton(title: "Start focus", fills: false) {
                        performPrimaryAction()
                    }
                    .fixedSize()
                }
                Text("Names you start will appear in the activity menu next time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            FocusActionButton(title: "Away", symbol: "door.right.hand.open") {
                store.markAway()
            }
            FocusActionButton(title: "Stop", symbol: "stop.fill") {
                store.stop()
            }
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
            FocusActionButton(title: "Stop", symbol: "stop.fill") {
                store.stop()
            }
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
            FocusActionButton(title: "Stop", symbol: "stop.fill") {
                store.stop()
            }
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
                .foregroundStyle(quiet ? AnyShapeStyle(.secondary)
                                       : AnyShapeStyle(Tokens.Colour.focus))
            Text(Tokens.clock(store.elapsed))
                .font(Tokens.Typography.liveTimer)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .accessibilityLabel("Elapsed \(Tokens.preciseDuration(store.elapsed))")
            VStack(alignment: compact ? .leading : .center, spacing: 2) {
                Text(store.activeIntent)
                    .font(compact ? .callout.weight(.medium) : .title3.weight(.medium))
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
            Text("Name or reclassify this automatic session, or discard it.")
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
        .buttonStyle(.plain)
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
            Text(presentation.visible)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(store.goal.isMet
                                 ? AnyShapeStyle(Tokens.Colour.progress)
                                 : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
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
                                         ? AnyShapeStyle(Tokens.Colour.progress)
                                         : AnyShapeStyle(.secondary))
                }
            }
            .frame(maxWidth: 360, alignment: .center)
            .accessibilityElement(children: .combine)
        }
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

    /// Executes the tested state-to-primary-action contract. Secondary actions
    /// stay explicit beside their buttons because they do not vary by mode.
    private func performPrimaryAction() {
        switch mode.primaryAction {
        case .start:
            store.start()
        case .pause:
            store.togglePause()
        case .resume:
            store.isAway ? store.endAway() : store.togglePause()
        case nil:
            break
        }
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
                .font(.caption.weight(.semibold))
            Text(failure.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if failure.hasOriginBoundRetry {
                Button("Retry saving") { store.retryLastCorrection() }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.attention.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Change not saved")
    }
}

/// A word-labelled action keeps the Focus panel understandable without relying
/// on tooltip-only icon controls. Only the state-appropriate primary action is
/// filled; Away and Stop remain quiet secondary choices.
private struct FocusActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(prominent ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: 30)
                .background(prominent ? AnyShapeStyle(Tokens.Colour.focus)
                                      : AnyShapeStyle(Tokens.Colour.elevated),
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                                 style: .continuous))
                .foregroundStyle(prominent ? AnyShapeStyle(Tokens.Colour.onFocus)
                                           : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
