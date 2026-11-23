import SwiftUI

extension SplitOffer {
    /// What the offer says under its title: when the work changed, what it changed to, and what the part
    /// after would be filed under. The totals do not move, and it says so.
    var sentence: String {
        let moment = DateFormats.clockTime(at)
        var text = purpose.map { "From \(moment) this was mostly \($0.inSentence)." }
            ?? "From \(moment) the work changed."
        text += " Splitting makes that part a session of its own, and your totals stay the same."
        if case .chosen(let type, _) = choice { text += " It would be filed under \(type.displayName)." }
        return text
    }
}

/// At the top of a finished session's report: "Split here?" for a session that held two pieces of work, with
/// Split and Keep Together, and "Merge Back" on the tail of a split. A tail that is not clearly focused work
/// asks for its category first (default the session's own), so what it is filed under is the person's choice.
/// Either action changes the session the report is open on, so the card closes; the day's notice and
/// Edit > Undo take it back. `SessionStore` decides what is offered; this draws it, and nothing when there is none.
struct SplitOfferRow: View {
    /// Only for the clicks; not observed, so the 1 Hz ticker does not redraw this.
    let store: SessionStore
    let offer: SplitOffer?
    let mergeBack: MergeBackOffer?
    let onChanged: () -> Void
    @State private var picked: WorkType
    @State private var kept = false

    init(store: SessionStore, offer: SplitOffer?, mergeBack: MergeBackOffer?, onChanged: @escaping () -> Void) {
        self.store = store
        self.offer = offer
        self.mergeBack = mergeBack
        self.onChanged = onChanged
        if case .ask(let preset)? = offer?.choice { _picked = State(initialValue: preset) }
        else { _picked = State(initialValue: WorkType.startable.first ?? .deepWork) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            if let offer, !kept { splitOffer(offer) }
            if let mergeBack { mergeBackOffer(mergeBack) }
        }
    }

    private func splitOffer(_ offer: SplitOffer) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("Split here?").font(Tokens.Typography.rowTitle)
                    Text(offer.sentence)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Tokens.Space.s)
                Button("Keep Together") { keepTogether(offer) }
                    .buttonStyle(StoryLinkStyle(tint: StoryStyle.supportingInk))
                    .accessibilityHint("Leaves this session whole and does not offer this split again.")
                Button("Split") { split(offer) }
                    .buttonStyle(StoryLinkStyle())
                    .accessibilityHint("Splits this session at \(DateFormats.clockTime(offer.at)). Undo is in the Edit menu.")
            }
            if case .ask = offer.choice {
                HStack(spacing: Tokens.Space.s) {
                    Text("File the second part under")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                    WorkTypePicker(selection: $picked)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func mergeBackOffer(_ offer: MergeBackOffer) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(offer.headName.isEmpty ? "This was split from the session before it."
                 : "This was split from “\(offer.headName)”.")
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Space.s)
            Button("Merge Back") { merge(offer) }
                .buttonStyle(StoryLinkStyle())
                .accessibilityHint("Joins the two parts into one session again. Undo is in the Edit menu.")
        }
        .accessibilityElement(children: .contain)
    }

    private func split(_ offer: SplitOffer) {
        let choice: WorkType? = { if case .ask = offer.choice { return picked } else { return nil } }()
        guard store.acceptSplit(offer, as: choice) else { return }
        Announcement.post("Session split in two")
        onChanged()
    }

    private func keepTogether(_ offer: SplitOffer) {
        store.declineSplit(offer)
        kept = true
        Announcement.post("Session kept together")
    }

    private func merge(_ offer: MergeBackOffer) {
        guard store.mergeBack(tailID: offer.tailID) else { return }
        Announcement.post("Sessions merged")
        onChanged()
    }
}
