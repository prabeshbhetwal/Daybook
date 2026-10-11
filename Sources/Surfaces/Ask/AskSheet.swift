import SwiftUI

/// Ask Daybook as a sheet over the window: the chat, under the sheet's own
/// title and close button. The side panel shows the same `AskChatView`. Like
/// the panel it is handed objects, not closures, so the window drawing again
/// does not draw the chat again (see `AskPanel`).
struct AskSheet: View {
    @ObservedObject var model: AskModel
    /// Where a source opens. The sheet closes first, and ⌘K brings the chat back.
    /// Not observed: the sheet reads nothing of it.
    let navigation: MainWindowModel

    var body: some View {
        AskChatView(model: model, onFollow: navigation.follow)
    }
}
