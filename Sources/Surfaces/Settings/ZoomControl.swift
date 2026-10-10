import SwiftUI

/// The Zoom row's control: a slider over the zoom steps, the percent it is at,
/// and a reset icon back to 100%. The percent keeps room for three digits and
/// the icon's slot is always there, so nothing shifts the slider while it is
/// dragged: a slider that moved under the pointer would carry the drag with it.
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
            // A drag commits on release: every window re-zooms at once, so the
            // slider would move under the pointer and the pointer would pick another step.
            Slider(value: $draft, in: 0.8...1.4, step: 0.1) {
                Text("Zoom")
            } minimumValueLabel: {
                // Decoration, so plain secondary ink: the slider would tint
                // its labels with the accent, which reads as a control.
                Text("A")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            } maximumValueLabel: {
                Text("A")
                    .font(Tokens.Typography.heading)
                    .foregroundStyle(Color.secondary)
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
                // The slider moves in steps, so each change under a drag is one step.
                if isDragging { model.playHaptic(.zoomStep) } else { commit() }
            }
            // The reset icon, ⌘0, or any other change to the model, moves the slider.
            .onChange(of: model.interfaceZoom) {
                if !isDragging { draft = model.interfaceZoom }
            }
            Text("\(percent)%")
                .font(Tokens.Typography.body.monospacedDigit())
                .frame(minWidth: 40.zoomed, alignment: .trailing)
                .accessibilityHidden(true)
            resetButton
        }
    }

    /// Back to 100%. At 100% it is invisible and out of reach but keeps its
    /// slot, so it never pushes the row about as it comes and goes.
    private var resetButton: some View {
        let atDefault = percent == InterfaceZoom.defaultPercent
        return Button { model.interfaceZoom = 1 } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(Tokens.Typography.label)
                .foregroundStyle(Color.secondary)
                .frame(width: AccessibilityMetrics.minimumTargetSize,
                       height: AccessibilityMetrics.minimumTargetSize)
        }
        .buttonStyle(StoryPressStyle(hovers: true,
                                     cornerRadius: AccessibilityMetrics.minimumTargetSize / 2))
        .help("Actual Size (⌘0)")
        .accessibilityLabel("Actual size")
        .accessibilityHint("Sets the zoom back to 100 percent")
        .opacity(atDefault ? 0 : 1)
        .disabled(atDefault)
        .accessibilityHidden(atDefault)
    }
}
