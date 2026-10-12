import SwiftUI

/// Under the category tidy-up on today's tile: an unnamed session with a name
/// on offer, one of the person's earlier names or a fresh one the on-device
/// model worded. Name it renames the session (with Undo on
/// its card); Keep as is stops the offer for that session. `NameSuggester`
/// decides what is offered and when it is asked; this only draws the answer,
/// and draws nothing while there is none.
struct NameSuggestionNotice: View {
    @ObservedObject var suggester: NameSuggester

    var body: some View {
        if let offer = suggester.current {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                caption(offer)
                // Fixed to their words: at 140% the first drew as "Nam…".
                HStack(spacing: Tokens.Space.s) {
                    Button("Name it") { suggester.accept() }
                        .buttonStyle(StoryActionStyle(tint: Tokens.Palette.workType(offer.session.workType)))
                        .fixedSize()
                        .accessibilityHint("Names this session “\(offer.name)”. Undo puts it back.")
                    Button("Keep as is") { suggester.keep() }
                        .buttonStyle(StoryLinkStyle(tint: StoryStyle.supportingInk))
                        .fixedSize()
                        .padding(.leading, Tokens.Space.s)
                }
            }
            .accessibilityElement(children: .contain)
        }
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
