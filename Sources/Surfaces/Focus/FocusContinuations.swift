import SwiftUI

/// One resumable action. Keeping the source identity explicit lets both Focus
/// surfaces render the same bounded order while choosing their own density.
enum FocusContinuationRow: Equatable, Identifiable {
    case thread(ThreadSummary)
    case quickStart(QuickStart)

    var id: String {
        switch self {
        case .thread(let thread): return "thread-\(thread.id.uuidString)"
        case .quickStart(let quick): return "quick-\(quick.id)"
        }
    }
}

/// Continuation selection is a presentation rule, not session accounting.
/// Recent threads are more faithful continuations than history-derived quick
/// starts, and the Focus surfaces are deliberately capped at three actions.
enum FocusContinuationSource {
    static func rows(threads: [ThreadSummary],
                     quickStarts: [QuickStart],
                     limit: Int,
                     excluding current: (name: String, workType: WorkType)? = nil) -> [FocusContinuationRow] {
        let count = min(3, max(0, limit))
        guard count > 0 else { return [] }
        if !threads.isEmpty {
            return threads.prefix(count).map(FocusContinuationRow.thread)
        }
        // While a session runs, the row for that same activity is the one
        // thing the list must not offer: "switch to what you are doing" is
        // not an action.
        let offered = quickStarts.filter { quick in
            guard let current else { return true }
            return !(quick.workType == current.workType
                     && quick.name.caseInsensitiveCompare(current.name) == .orderedSame)
        }
        return offered.prefix(count).map(FocusContinuationRow.quickStart)
    }
}

/// Up to three next actions below the hero. It intentionally chooses one
/// source: current-day threads when any exist, otherwise history-derived quick
/// starts. Mixing the two makes a continuation look equivalent to a guess.
///
/// Idle, a row starts work. Running, the same tap ends the current stretch
/// and begins the named one — so the section says "Switch to", the rows say
/// "Switch", and the activity already running is not among them. The panel
/// used to keep "Quick start · Start · Start · Start" under a live timer, an
/// idle panel wearing a clock.
struct FocusContinuations: View {
    @ObservedObject var store: SessionStore
    var limit = 3
    var compact = false

    private var isSwitching: Bool { !store.isIdle }

    var body: some View {
        let threads = store.continuableThreads
        let rows = FocusContinuationSource.rows(
            threads: threads, quickStarts: store.quickStarts, limit: limit,
            excluding: isSwitching ? (store.activeIntent, store.workType) : nil)
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            SectionHeader(title: rowsTitle(threads: threads), compact: compact)
                .padding(.bottom, Tokens.Space.xs)
            if rows.isEmpty {
                Text(isSwitching
                     ? "Names you start will be here to switch to next time."
                     : "Start a focus session and useful continuations will stay here on this Mac.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows) { row in continuation(row) }
            }
        }
    }

    private func rowsTitle(threads: [ThreadSummary]) -> String {
        if isSwitching { return "Switch to" }
        if !threads.isEmpty { return "Continue" }
        if !store.quickStarts.isEmpty { return "Quick start" }
        return "Your next focus"
    }

    @ViewBuilder private func continuation(_ row: FocusContinuationRow) -> some View {
        switch row {
        case .thread(let thread):
            let apps = store.threadApps(thread)
            continuationButton(enabled: !thread.isRunning,
                               action: { store.continueThread(thread) }) {
                FocusContinuationLabel(
                    title: thread.name.isEmpty ? thread.workType.displayName : thread.name,
                    detail: threadDetail(thread, apps: apps),
                    action: thread.isRunning ? .current
                        : isSwitching ? .switchTo : .duration(thread.totalWorked),
                    workType: thread.workType, compact: compact)
            }
        case .quickStart(let quick):
            continuationButton(enabled: true, action: { store.startQuick(quick) }) {
                FocusContinuationLabel(title: quick.name,
                                       detail: quick.workType.displayName,
                                       action: isSwitching ? .switchTo : .start,
                                       workType: quick.workType, compact: compact)
            }
        }
    }

    @ViewBuilder private func continuationButton<Label: View>(
        enabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if enabled {
            Button(action: action, label: label)
                .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.well))
        } else {
            label()
        }
    }

    private func threadDetail(_ thread: ThreadSummary, apps: ThreadApps) -> String {
        var parts = [thread.workType.displayName]
        if let primary = apps.primary { parts.append(primary.appName) }
        if thread.segments > 1 { parts.append("\(thread.segments) stretches") }
        return parts.joined(separator: " · ")
    }
}

/// What the row's trailing edge says the tap will do.
enum FocusContinuationAction: Equatable {
    case start
    case switchTo
    case duration(TimeInterval)
    case current
}

private struct FocusContinuationLabel: View {
    let title: String
    let detail: String
    let action: FocusContinuationAction
    let workType: WorkType
    let compact: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            // The work type as a tinted mark, the way the story colours it.
            Image(systemName: workType.symbolName)
                .font(Tokens.Typography.control.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Tokens.Palette.workType(workType))
                .frame(width: 30, height: 30)
                .background(Tokens.Palette.workType(workType).opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Tokens.Typography.rowTitle)
                    .lineLimit(1)
                Text(detail)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.s)
            trailing
        }
        .padding(.horizontal, Tokens.Space.s)
        .frame(minHeight: compact ? 40 : 46)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var trailing: some View {
        switch action {
        case .start, .switchTo:
            // A verb in a quiet pill: the row is the button, this says what
            // pressing it does.
            Text(action == .start ? "Start" : "Switch")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(Tokens.Colour.focus)
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.focus.opacity(0.12), in: Capsule())
        case .duration(let seconds):
            Text(Tokens.preciseDuration(seconds))
                .font(Tokens.Typography.metadata.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        case .current:
            Text("Current")
                .font(Tokens.Typography.metadata.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// A break reminder is supporting context, never a competing card.
struct FocusBreakLine: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        Label(store.breakLabel,
              systemImage: store.isBreakDue ? "figure.walk" : "eye")
            .font(Tokens.Typography.metadata)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(store.isBreakDue
                             ? AnyShapeStyle(Tokens.Colour.attention)
                             : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .accessibilityLabel("Break status: \(store.breakLabel)")
    }
}
