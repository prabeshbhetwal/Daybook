import SwiftUI

private final class LegacyClassificationDraft: ObservableObject {
    @Published var confirming = false
    var decision: UserDecision = .continueSession
    var target: SessionRecord?
    var original: SessionRecord?
}

/// Explicit classification, not a fabricated exact Undo of legacy evidence.
///
/// The store publishes every second while anything is live, and a menu whose
/// view is redrawn while it is open loses the item under the pointer. So the
/// store is held, not observed, and the view redraws only when what it shows
/// changes: the break, the archive behind its targets, or whether it is
/// blocked. Place it with `.equatable()`.
struct StoryLegacyBreakActions: View, Equatable {
    let store: SessionStore
    let rest: RestEntry
    /// The archive's revision, so the targets follow a change to it.
    let archiveRevision: Int
    let isBlocked: Bool
    @StateObject private var draft = LegacyClassificationDraft()

    init(store: SessionStore, rest: RestEntry) {
        self.store = store
        self.rest = rest
        archiveRevision = store.evidenceRevision.sessions
        isBlocked = store.hasUnresolvedAwayDecision
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.store === rhs.store && lhs.rest == rhs.rest
            && lhs.archiveRevision == rhs.archiveRevision && lhs.isBlocked == rhs.isBlocked
    }

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
        .disabled(isBlocked)
        .help(isBlocked ? StoryDecisionRow.awayQuestionFirst : "")
        .accessibilityLabel(rest.name.isEmpty || rest.name == "Break"
                            ? "Change how this break counts"
                            : "Change how \(rest.name) counts")
        .accessibilityHint(isBlocked ? StoryDecisionRow.awayQuestionFirst : "")
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
