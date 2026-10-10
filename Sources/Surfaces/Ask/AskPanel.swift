import SwiftUI

enum AskLayout {
    /// The side panel's width at 100%.
    static let panelBaseWidth: CGFloat = 360 // zoom: fixed, the 100% size
    static var panelWidth: CGFloat { panelBaseWidth.zoomed }
}

/// Ask Daybook beside the reading workspace: the same chat the sheet shows,
/// under a header with its title, New chat and a close button. It stands at
/// window level, so it stays when the window moves between Story and History,
/// and a source opens History right beside the chat. The window gives it its
/// width (`AskLayout.panelWidth`) and its place; this view only fills it.
struct AskPanel: View {
    @ObservedObject var model: AskModel
    /// What a source, in the text or in the list, opens.
    let onFollow: (AskLink) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AskChatView(model: model, onFollow: onFollow, showsNewChat: false)
        }
        .background(StoryStyle.rail)
        // Escape with the cursor in the panel closes it, as it closes a sheet.
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ask Daybook")
        .storyRenderEvidence(.askPanel)
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s) {
            Text("Ask Daybook")
                .font(Tokens.Typography.heading)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tokens.Space.s)
            if !model.turns.isEmpty {
                Button("New chat") { model.newChat() }
                    .buttonStyle(StoryActionStyle())
                    .fixedSize()
            }
            IconButton(systemImage: "xmark", help: "Close Ask (⌘K)", action: onClose)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
    }
}
