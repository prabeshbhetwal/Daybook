import SwiftUI

/// Under the category tidy-up on today's tile: an unnamed session with a name
/// on offer, one of the person's earlier names or a fresh one the on-device
/// model worded. Name it renames the session and says so here, with Undo,
/// because the session may be yesterday's and its own card is not on this
/// day; Keep as is stops the offer for that session. `NameSuggester` decides
/// what is offered and when it is asked; this only draws the answer, and
/// draws nothing while there is none.
struct NameSuggestionNotice: View {
    @ObservedObject var suggester: NameSuggester
    /// Only for Undo; not observed, so the 1 Hz ticker does not redraw this.
    let store: SessionStore
    /// The last name taken with Name it, and the correction Undo reverses. It
    /// stays under the next offer until that one is acted on, or Today is left.
    @State private var named: (name: String, correctionID: UUID)?

    var body: some View {
        if named != nil || suggester.current != nil {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                if let named { confirmation(named) }
                if let offer = suggester.current { offered(offer) }
            }
        }
    }

    private func confirmation(_ done: (name: String, correctionID: UUID)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text("Named “\(done.name)”.")
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Undo") { undo(done.correctionID) }
                .buttonStyle(StoryLinkStyle())
        }
        .accessibilityElement(children: .contain)
    }

    private func offered(_ offer: NameSuggestion) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            caption(offer)
            // Fixed to their words: at 140% the first drew as "Nam…".
            HStack(spacing: Tokens.Space.s) {
                Button("Name it") { named = suggester.accept() ?? named }
                    .buttonStyle(StoryActionStyle(tint: Tokens.Palette.workType(offer.session.workType)))
                    .fixedSize()
                    .accessibilityHint("Names this session “\(offer.name)”. Undo appears above.")
                Button("Keep as is") { named = nil; suggester.keep() }
                    .buttonStyle(StoryLinkStyle(tint: StoryStyle.supportingInk))
                    .fixedSize()
                    .padding(.leading, Tokens.Space.s)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Puts the name back. The session is not offered again this run: the
    /// suggester remembers what the person took.
    private func undo(_ id: UUID) {
        store.undoCorrection(expectedID: id)
        named = nil
    }

    /// The offer and where it came from. An earlier name is the person's own,
    /// picked by the ranking, so it claims no AI. A fresh one is the model's.
    @ViewBuilder private func caption(_ offer: NameSuggestion) -> some View {
        let words = offer.source == .earlier ? "From your earlier names" : "Suggested by on-device AI"
        let text = VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Name \(offer.lead) “\(offer.name)”?")
                .font(Tokens.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(words)
                .font(Tokens.Typography.caption)
                .foregroundStyle(StoryStyle.supportingInk)
        }
        if offer.source == .fresh {
            Label {
                text
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(StoryStyle.supportingInk)
                    .accessibilityHidden(true)
            }
        } else {
            text
        }
    }
}
