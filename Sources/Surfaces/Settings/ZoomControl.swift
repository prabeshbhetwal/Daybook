import SwiftUI

/// The Zoom row's control: a slider over the zoom steps, the percent it is at,
/// and a way back to 100%. Actual Size sits to the left and the percent keeps
/// room for three digits, so neither shifts the slider while it is dragged:
/// a slider that moved under the pointer would carry the drag with it.
struct ZoomControl: View {
    @ObservedObject var model: SettingsModel
    /// What the slider and the percent show: the pointer's position during a
    /// drag, the model's zoom otherwise.
    @State private var draft: Double
    @State private var isDragging = false

    init(model: SettingsModel) {
        self.model = model
        _draft = State(initialValue: model.interfaceZoom)
    }

    private var percent: Int { InterfaceZoom.nearestPercent(toScale: draft) }

    /// Hands the draft to the model, unless it is the step the model holds.
    private func commit() {
        guard percent != InterfaceZoom.nearestPercent(toScale: model.interfaceZoom) else { return }
        model.interfaceZoom = draft
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            if percent != InterfaceZoom.defaultPercent {
                Button("Actual Size") { model.interfaceZoom = 1 }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .accessibilityHint("Sets the zoom back to 100 percent")
            }
            // A drag commits on release: every window re-zooms at once, so the
            // slider would move under the pointer and the pointer would pick another step.
            Slider(value: $draft, in: 0.8...1.4, step: 0.1) {
                Text("Zoom")
            } minimumValueLabel: {
                Text("A")
                    .font(Tokens.Typography.caption)
                    .accessibilityHidden(true)
            } maximumValueLabel: {
                Text("A")
                    .font(Tokens.Typography.heading)
                    .accessibilityHidden(true)
            } onEditingChanged: { editing in
                isDragging = editing
                if !editing { commit() }
            }
            .labelsHidden()
            .frame(width: 200.zoomed)
            .accessibilityLabel("Zoom")
            .accessibilityValue("\(percent) percent")
            // A change outside a drag (a click, an arrow key, VoiceOver) applies at once.
            .onChange(of: draft) {
                if !isDragging { commit() }
            }
            // Actual Size, or any other change to the model, moves the slider.
            .onChange(of: model.interfaceZoom) {
                if !isDragging { draft = model.interfaceZoom }
            }
            Text("\(percent)%")
                .font(Tokens.Typography.body.monospacedDigit())
                .frame(minWidth: 40.zoomed, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
