import SwiftUI

extension SettingsGroups {
    /// Ask Daybook in General: whether it can run on this Mac, the bar's
    /// button, and a way in for someone who has not met ⌘K. On a Mac that can
    /// never run it, the status says why and the controls rest.
    var askPanel: some View {
        SurfacePanel(title: "Ask Daybook", layout: layout) {
            explanation(AskModel.status)
            rowDivider
            toggleRow("Show Ask in the toolbar", detail: "⌘K opens Ask either way.", isOn: $model.showsAskButton)
                .disabled(!AskModel.isOffered)
            rowDivider
            preferenceRow("Open Ask in", detail: "Small screens always use a sheet.") {
                // A pop-up like every other choice here: a segmented control
                // belongs in a toolbar, and its text did not follow the zoom.
                RowMenu("Open Ask in", selection: $model.askPlacement, options: [.sheet, .panel]) {
                    $0 == .sheet ? "Sheet" : "Side panel"
                }
                .disabled(!AskModel.isOffered)
                .accessibilityLabel("Open Ask in")
            }
            if model.canOpenAsk {
                Button("Open Ask") { model.openAsk() }
                    .buttonStyle(.bordered)
                    .disabled(!AskModel.isOffered)
                    .accessibilityHint("Closes Settings and opens Ask Daybook")
            }
        }
    }
}
