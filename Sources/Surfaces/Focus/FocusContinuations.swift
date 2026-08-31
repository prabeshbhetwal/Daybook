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
                     limit: Int) -> [FocusContinuationRow] {
        let count = min(3, max(0, limit))
        guard count > 0 else { return [] }
        if !threads.isEmpty {
            return threads.prefix(count).map(FocusContinuationRow.thread)
        }
        return quickStarts.prefix(count).map(FocusContinuationRow.quickStart)
    }
}

/// Up to three next actions below the hero. It intentionally chooses one
/// source: current-day threads when any exist, otherwise history-derived quick
/// starts. Mixing the two makes a continuation look equivalent to a guess.
struct FocusContinuations: View {
    @ObservedObject var store: SessionStore
    var limit = 3
    var compact = false

    var body: some View {
        let threads = store.continuableThreads
        let rows = FocusContinuationSource.rows(threads: threads,
                                                quickStarts: store.quickStarts,
                                                limit: limit)
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: rowsTitle(threads: threads),
                          trailing: rows.isEmpty ? nil : rowsCountLabel(threads: threads,
                                                                           rows: rows))
            if rows.isEmpty {
                Text("Start a focus session and useful continuations will stay here on this Mac.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    continuation(row)
                }
            }
        }
    }

    private func rowsTitle(threads: [ThreadSummary]) -> String {
        if !threads.isEmpty { return "Continue" }
        if !store.quickStarts.isEmpty { return "Quick start" }
        return "Your next focus"
    }

    private func rowsCountLabel(threads: [ThreadSummary], rows: [FocusContinuationRow]) -> String {
        if !threads.isEmpty {
            return rows.count == 1 ? "1 session" : "\(rows.count) sessions"
        }
        return rows.count == 1 ? "1 shortcut" : "\(rows.count) shortcuts"
    }

    @ViewBuilder private func continuation(_ row: FocusContinuationRow) -> some View {
        switch row {
        case .thread(let thread):
            let apps = store.threadApps(thread)
            continuationButton(enabled: !thread.isRunning,
                               action: { store.continueThread(thread) }) {
                FocusContinuationLabel(title: thread.name.isEmpty
                                           ? thread.workType.displayName : thread.name,
                                       detail: threadDetail(thread, apps: apps),
                                       value: thread.isRunning
                                           ? "Current" : Tokens.preciseDuration(thread.totalWorked),
                                       symbol: thread.workType.symbolName,
                                       compact: compact)
            }
        case .quickStart(let quick):
            continuationButton(enabled: true, action: { store.startQuick(quick) }) {
                FocusContinuationLabel(title: quick.name,
                                       detail: quick.workType.displayName,
                                       value: "Start",
                                       symbol: quick.workType.symbolName,
                                       compact: compact)
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
                .buttonStyle(.plain)
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

private struct FocusContinuationLabel: View {
    let title: String
    let detail: String
    let value: String
    let symbol: String
    let compact: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 22)
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
            Text(value)
                .font(Tokens.Typography.metadata.weight(.medium).monospacedDigit())
                .foregroundStyle(value == "Current" ? AnyShapeStyle(.secondary)
                                                     : AnyShapeStyle(Tokens.Colour.focus))
                .lineLimit(1)
        }
        .frame(minHeight: compact ? 34 : 42)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
