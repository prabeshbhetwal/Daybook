import SwiftUI

enum AskLayout {
    /// The side panel's width at 100%.
    static let panelBaseWidth: CGFloat = 360 // zoom: fixed, the 100% size
    static var panelWidth: CGFloat { panelBaseWidth.zoomed }

    /// Whether a screen with `visible` free can hold the window with the panel
    /// beside Story and History at `scale`: its minimum (the window's with the
    /// panel's width added) is not held to the screen by `InterfaceZoom`'s
    /// margin. Where it is held, the reading column would narrow until it
    /// overlapped itself, so Ask opens as a sheet there. The one place the rule lives.
    static func panelHasRoom(scale: CGFloat, visible: CGSize) -> Bool {
        let base = MainWindowView.contentBase(askPanelOpen: true)
        return InterfaceZoom.windowMinimum(base: base, scale: scale, visible: visible)
            == CGSize(width: base.width * scale, height: base.height * scale)
    }
}

/// Ask Daybook beside the reading workspace: the same chat the sheet shows,
/// under a header with its title, New chat and a close button. It stands at
/// window level, so it stays when the window moves between Story and History,
/// and a source opens History right beside the chat. The window gives it its
/// width (`AskLayout.panelWidth`) and its place; this view only fills it.
///
/// It is handed the window's model, not closures. A closure made afresh each
/// time the window draws is never equal to the last, so the chat was drawn
/// again on every tick of a running session's clock; two objects are equal
/// while they are the same, and the chat is drawn when `model` changes.
struct AskPanel: View {
    @ObservedObject var model: AskModel
    /// Where a source, in the text or in the list, opens, and what closes the panel.
    /// Not observed: the panel reads nothing of it.
    let navigation: MainWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AskChatView(model: model, onFollow: navigation.follow)
                // The panel is always narrow, so every source sets its role under its label.
                .environment(\.stacksAskSources, true)
        }
        .background(StoryStyle.rail)
        // Escape with the cursor in the panel closes it, as it closes a sheet.
        .onExitCommand(perform: navigation.closeAskPanel)
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
            AskNewChatButton(model: model)
            IconButton(systemImage: "xmark", help: "Close Ask (⌘K)", action: navigation.closeAskPanel)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
    }
}

/// The reading workspace, and Ask's side panel at its trailing edge when
/// `askModel` is given. The panel always has `AskLayout.panelWidth`; it is the
/// workspace that narrows when the window cannot hold both, as a window held to
/// a small screen at a high zoom cannot. Without `minWidth: 0` the workspace's
/// content minimum wins and pushes the panel past the window's edge.
struct ReadingWithAskPanel<Workspace: View>: View {
    let askModel: AskModel?
    let navigation: MainWindowModel
    @ViewBuilder let workspace: Workspace

    var body: some View {
        HStack(spacing: 0) {
            workspace
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .accessibilitySortPriority(1)
            if let askModel {
                Divider()
                AskPanel(model: askModel, navigation: navigation)
                    .frame(width: AskLayout.panelWidth)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}
