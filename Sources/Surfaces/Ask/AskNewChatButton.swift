import SwiftUI

/// "New chat", in the header beside the close button, in the sheet as in the
/// side panel. It stands once the chat has a turn. The chat empties and
/// forgets what was typed (`AskChatView` watches for it).
struct AskNewChatButton: View {
    @ObservedObject var model: AskModel

    var body: some View {
        if !model.turns.isEmpty {
            Button("New chat") { model.newChat() }
                .buttonStyle(StoryActionStyle())
                .fixedSize()
                .storyRenderEvidence(.askNewChat)
        }
    }
}
