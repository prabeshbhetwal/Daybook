import SwiftUI

/// Zoom In, Zoom Out and Actual Size in the View menu, with ⌘+, ⌘− and ⌘0.
/// Like the Session menu, it is mostly there for its key equivalents. Each
/// item writes `settings.interfaceZoom`, the one property the Settings slider,
/// the stored value and every window agree on. ⌘= and the keypad's + and −
/// reach the same items: AppKit matches them to these key equivalents.
struct ZoomCommands: Commands {
    /// Observed so the items re-enable as the zoom moves, whether from here
    /// or from the Settings slider.
    @ObservedObject var settings: SettingsModel

    /// Which items can act at `percent`: Zoom In and Zoom Out stop at the
    /// ends of the steps, and Actual Size has nothing to do at 100%.
    static func availability(percent: Int) -> (zoomIn: Bool, zoomOut: Bool, actualSize: Bool) {
        (zoomIn: InterfaceZoom.canStep(percent, by: 1),
         zoomOut: InterfaceZoom.canStep(percent, by: -1),
         actualSize: InterfaceZoom.snapped(percent) != InterfaceZoom.defaultPercent)
    }

    private var percent: Int { InterfaceZoom.nearestPercent(toScale: settings.interfaceZoom) }

    private func zoom(to percent: Int) { settings.interfaceZoom = Double(percent) / 100 }

    var body: some Commands {
        let enabled = Self.availability(percent: percent)
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { zoom(to: InterfaceZoom.stepped(percent, by: 1)) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!enabled.zoomIn)
            Button("Zoom Out") { zoom(to: InterfaceZoom.stepped(percent, by: -1)) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!enabled.zoomOut)
            Button("Actual Size") { zoom(to: InterfaceZoom.defaultPercent) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!enabled.actualSize)
        }
    }
}
