import SwiftUI

/// Under the category tidy-up on today's tile: an unnamed session the
/// on-device model has a name for. Name it renames the session (with Undo on
/// its card); Keep as is stops the offer for that session. `NameSuggester`
/// decides what is offered and when it is asked; this only draws the answer,
/// and draws nothing while there is none.
struct NameSuggestionNotice: View {
    @ObservedObject var suggester: NameSuggester

    var body: some View {
        if let offer = suggester.current {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Label {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text("Name \(offer.lead) “\(offer.name)”?")
                            .font(Tokens.Typography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Suggested by on-device AI")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(StoryStyle.supportingInk)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(StoryStyle.supportingInk)
                        .accessibilityHidden(true)
                }
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
}
