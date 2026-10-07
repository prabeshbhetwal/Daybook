import SwiftUI

/// The Zoom row's control: a slider over the zoom steps, the percent it is at,
/// and a way back to 100%. Actual Size sits to the left and the percent keeps
/// room for three digits, so neither shifts the slider while it is dragged:
/// a slider that moved under the pointer would carry the drag with it.
struct ZoomControl: View {
    @ObservedObject var model: SettingsModel

    private var percent: Int { InterfaceZoom.nearestPercent(toScale: model.interfaceZoom) }

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            if percent != InterfaceZoom.defaultPercent {
                Button("Actual Size") { model.interfaceZoom = 1 }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .accessibilityHint("Sets the zoom back to 100 percent")
            }
            Slider(value: $model.interfaceZoom, in: 0.8...1.4, step: 0.1) {
                Text("Zoom")
            } minimumValueLabel: {
                Text("A")
                    .font(Tokens.Typography.caption)
                    .accessibilityHidden(true)
            } maximumValueLabel: {
                Text("A")
                    .font(Tokens.Typography.heading)
                    .accessibilityHidden(true)
            }
            .labelsHidden()
            .frame(width: 200.zoomed)
            .accessibilityLabel("Zoom")
            .accessibilityValue("\(percent) percent")
            Text("\(percent)%")
                .font(Tokens.Typography.body.monospacedDigit())
                .frame(minWidth: 40.zoomed, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
