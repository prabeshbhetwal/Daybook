import SwiftUI

extension SettingsGroups {
    /// Ask Daybook in General: whether it can run on this Mac, the bar's
    /// button, and a way in for someone who has not met ⌘K. On a Mac that can
    /// never run it, the status says why and the controls rest.
    var askPanel: some View {
        SurfacePanel(title: "Ask Daybook", layout: layout) {
            explanation("Ask a question about your focus history, such as when your most focused day was. "
                        + AskModel.status)
            rowDivider
            toggleRow("Show Ask in the toolbar",
                      detail: "The Ask button beside Settings. ⌘K opens Ask either way.",
                      isOn: $model.showsAskButton)
                .disabled(!AskModel.isOffered)
            if model.canOpenAsk {
                Button("Open Ask") { model.openAsk() }
                    .buttonStyle(.bordered)
                    .controlSize(Tokens.Zoom.controlSize(.large))
                    .disabled(!AskModel.isOffered)
                    .accessibilityHint("Closes Settings and opens Ask Daybook")
            }
        }
    }
}
