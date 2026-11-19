import SwiftUI

/// What the person did with the offer: the category it filed the session under, and the correction
/// Undo reverses.
struct CorrectionFiling: Equatable {
    let category: WorkType
    let correctionID: UUID

    /// This filing while its correction is still there to undo; nil once it was undone elsewhere
    /// (Edit > Undo, the day's banner), so a card never says "Filed under" about a change that is gone.
    func standing(in corrections: [SessionStoreCorrectionState]) -> CorrectionFiling? {
        corrections.contains { $0.id == correctionID } ? self : nil
    }
}

extension DaySession {
    /// The same row after its category changed, so a report open on it can show the change at once.
    func recategorised(as type: WorkType) -> DaySession {
        DaySession(id: id, threadID: threadID, name: name, workType: type, start: start, end: end,
                   worked: worked, stretches: stretches, spans: spans, recordIDs: recordIDs, isRunning: isRunning)
    }
}

/// At the top of a finished session's report: "You usually file this as Coding" with a button that
/// files it there, the way the person would by hand, so the category becomes theirs. Offered only for a
/// category Daybook chose; the person's own and a rule's are never questioned. Taking it says so here,
/// with Undo. `SessionStore.correctionSuggestion` decides what is offered; this draws the answer and
/// draws nothing while there is none.
struct CorrectionSuggestionRow: View {
    /// Only for the click and Undo; not observed, so the 1 Hz ticker does not redraw this.
    let store: SessionStore
    let session: DaySession
    let offer: WorkType?
    @Binding var filed: CorrectionFiling?

    @ViewBuilder var body: some View {
        if let filed {
            line("Filed under \(filed.category.displayName).", action: "Undo",
                 hint: "Puts the category back as it was.") { undo(filed) }
        } else if let offer {
            line("You usually file this as \(offer.displayName).", action: "Use \(offer.displayName)",
                 hint: "Files this session under \(offer.displayName). Undo appears here.") { file(offer) }
        }
    }

    private func line(_ text: String, action: String, hint: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(text)
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Space.s)
            Button(action, action: perform)
                .buttonStyle(StoryLinkStyle())
                .accessibilityHint(hint)
        }
        .accessibilityElement(children: .contain)
    }

    private func file(_ category: WorkType) {
        guard store.setWorkType(category, for: session), let correction = store.lastCorrection else { return }
        filed = CorrectionFiling(category: category, correctionID: correction.id)
        Announcement.post("Filed under \(category.displayName)")
    }

    private func undo(_ done: CorrectionFiling) {
        guard store.undoCorrection(expectedID: done.correctionID) else { return }
        filed = nil
        Announcement.post("Category put back")
    }
}
