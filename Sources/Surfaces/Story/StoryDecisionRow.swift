import SwiftUI

enum StoryDecisionScope {
    static func note(visible: DateInterval, full: DateInterval) -> String? {
        guard visible != full else { return nil }
        let calendar = Calendar.current
        let days = max(2, (calendar.dateComponents([.day],
            from: calendar.startOfDay(for: full.start),
            to: calendar.startOfDay(for: full.end.addingTimeInterval(-0.001))).day ?? 1) + 1)
        let scope = days == 2 ? "both days" : "all \(days) days"
        return "Changes apply to the full \(Tokens.preciseDuration(full.duration)) stretch across \(scope)."
    }
}

struct StoryDecisionRow: View {
    @ObservedObject var store: SessionStore
    let receipt: AwayDecisionReceipt
    let range: DateInterval

    var body: some View {
        if receipt.decision == .tookBreak, let record = receipt.insertedRecord.flatMap({ store.legacyBreakRecord(id: $0.id) }) {
            // A break is one row however it was recorded.
            StoryBreakRow(store: store,
                          rest: RestEntry(id: record.id, name: record.name, start: range.start, end: range.end),
                          receipt: receipt)
                .equatable()
        } else if receipt.isResolved {
            StorySavedActionRow(title: receipt.title, range: range,
                                // A decision can be undone except while the
                                // away question is waiting for its answer.
                                undoBlockReason: store.engine.canUndoAwayDecision(expectedID: receipt.id)
                                    ? nil : Self.awayQuestionFirst,
                                scopeNote: StoryDecisionScope.note(visible: range, full: receipt.range)) {
                store.undoAwayDecision(expectedID: receipt.id)
            }
        } else {
            VStack(alignment: .leading, spacing: 10.zoomed) {
                Text("How should this stretch be recorded?")
                    .font(Tokens.Typography.rowTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("\(Tokens.timeRange(range.start, range.end)) · \(Tokens.preciseDuration(range.duration)) is not counted. Later work is unchanged.")
                    .font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Tokens.Space.s) {
                    Button("Count as Focus") { answer(.mergeTime) }
                        .buttonStyle(StoryActionStyle(tint: StoryStyle.focus))
                    Button("Call It a Break") { answer(.tookBreak) }
                        .buttonStyle(StoryActionStyle())
                    Button("Leave Uncounted") { answer(.continueSession) }
                        .buttonStyle(StoryActionStyle())
                }
                .disabled(store.hasUnresolvedAwayDecision)
                .help(store.hasUnresolvedAwayDecision ? Self.awayQuestionFirst : "")
                .accessibilityHint(store.hasUnresolvedAwayDecision ? Self.awayQuestionFirst : "")
                if let note = StoryDecisionScope.note(visible: range, full: receipt.range) {
                    Text(note)
                        .font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
                }
            }
            .questionCard()
        }
    }

    private func answer(_ decision: UserDecision) {
        store.applyAwayDecision(decision, reviewing: true, expectedID: receipt.id)
    }

    /// Why a past interval's answers wait: the same words Remove uses.
    static let awayQuestionFirst = "Answer the away question first."
}

struct StorySavedActionRow: View {
    let title: String
    let range: DateInterval
    /// Set while Undo cannot act yet; the button says why.
    var undoBlockReason: String?
    var scopeNote: String?
    let undo: () -> Void
    @Environment(\.focusInterfaceDensity) private var density

    /// A span for what the action covered; one time for a correction, which
    /// happened at a moment.
    private var when: String {
        range.duration > 0 ? Tokens.timeRange(range.start, range.end) : DateFormats.clockTime(range.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
          HStack(spacing: 10.zoomed) {
            // One sentence to VoiceOver, not a tick and two fragments.
            HStack(spacing: 10.zoomed) {
                Image(systemName: "checkmark").font(Tokens.Typography.label)
                    .foregroundStyle(StoryStyle.successInk)
                Text(title).font(Tokens.Typography.label)
                    .lineLimit(1)
                    .help(title)
                Text(when)
                    .font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(when)")
            Spacer(minLength: Tokens.Space.s)
            Button("Undo", action: undo)
                .buttonStyle(StoryLinkStyle())
                .font(Tokens.Typography.label)
                .foregroundStyle(StoryStyle.action)
                .frame(minWidth: 36.zoomed, minHeight: AccessibilityMetrics.minimumTargetSize)
                .disabled(undoBlockReason != nil)
                .help(undoBlockReason ?? "")
                .accessibilityLabel("Undo \(title.lowercased())")
                .accessibilityHint(undoBlockReason ?? scopeNote ?? "Reverts only this action; later work is unchanged.")
          }
          if let scopeNote {
              Text(scopeNote).font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
                  .fixedSize(horizontal: false, vertical: true)
                  .padding(.leading, 22.zoomed)
          }
        }
        .padding(.horizontal, StoryStyle.entryInsets(for: density).leading)
        .padding(.vertical, Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.successWash,
                    in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous)
            .strokeBorder(StoryStyle.successInk.opacity(0.22)))
        // The row replaces the question in place, so a listener is told it
        // was saved; nothing else says so.
        .onAppear { Announcement.post("Saved. \(title), \(when)") }
    }
}
