import SwiftUI

/// Ask Daybook as a sheet over the window: the chat, under the sheet's own
/// title and close button. The side panel shows the same `AskChatView`.
struct AskSheet: View {
    let model: AskModel
    /// What a source opens. The sheet closes first, and ⌘K brings the chat back.
    let onFollow: (AskLink) -> Void

    var body: some View {
        AskChatView(model: model, onFollow: onFollow)
    }
}
