import SwiftUI

private final class LegacyClassificationDraft: ObservableObject {
    @Published var confirming = false
    var decision: UserDecision = .continueSession
    var target: SessionRecord?
    var original: SessionRecord?
}

/// Explicit classification, not a fabricated exact Undo of legacy evidence.
struct StoryLegacyBreakActions: View {
    @ObservedObject var store: SessionStore
    let rest: RestEntry
    @StateObject private var draft = LegacyClassificationDraft()

    var body: some View {
        let targets = store.legacyFocusTargets(for: rest)
        return Menu("Change how this counts") {
            Button("Leave uncounted") { choose(.continueSession) }
            if targets.isEmpty {
                Text("No focus session was recorded on this day.")
                Text("You can still leave this interval uncounted.")
            } else {
                Menu("Count as focus in…") {
                    ForEach(targets) { record in
                        Button(SessionStore.legacyFocusTargetLabel(record)) {
                            choose(.mergeTime, target: record)
                        }
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.hasUnresolvedAwayDecision)
        .help(store.hasUnresolvedAwayDecision ? StoryDecisionRow.awayQuestionFirst : "")
        .accessibilityLabel(rest.name.isEmpty || rest.name == "Break"
                            ? "Change how this break counts"
                            : "Change how \(rest.name) counts")
        .accessibilityHint(store.hasUnresolvedAwayDecision ? StoryDecisionRow.awayQuestionFirst : "")
        .confirmationDialog("Change this recorded interval?", isPresented: $draft.confirming, titleVisibility: .visible) {
            Button(draft.decision == .mergeTime ? "Count as focus" : "Leave uncounted") {
                store.reclassifyLegacyBreak(recordID: rest.id, decision: draft.decision, focusTargetID: draft.target?.id,
                                            expectedRecord: draft.original, expectedTarget: draft.target)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(scopeMessage)
        }
    }

    private func choose(_ decision: UserDecision, target: SessionRecord? = nil) {
        draft.decision = decision
        draft.target = target
        draft.original = store.legacyBreakRecord(id: rest.id)
        draft.confirming = true
    }

    private var scopeMessage: String {
        guard let record = store.legacyBreakRecord(id: rest.id) else { return "This record is no longer available." }
        let full = DateInterval(start: record.start, end: record.end)
        var text = "Changes the full \(Tokens.preciseDuration(full.duration)) recorded interval. "
        if let target = draft.target {
            text += "Attribute it to \(target.name.isEmpty ? "the unnamed session" : target.name) as \(target.workType.displayName). "
        } else { text += "Its break classification will be removed, with no focus time added. " }
        if let note = StoryDecisionScope.note(visible: DateInterval(start: rest.start, end: rest.end), full: full) {
            text += note + " "
        }
        return text + "Undo restores the original recorded break. App-use evidence is unchanged."
    }
}
