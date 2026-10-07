import CoreGraphics
import SwiftUI

/// A length written as `12.zoomed` is 12 points at 100% and scales with the
/// interface zoom. Read it while a view draws, never in an `init` or a stored
/// `let`, so the view is drawn again when the zoom changes.
extension BinaryInteger {
    var zoomed: CGFloat { CGFloat(Int(clamping: self)) * ZoomModel.shared.scale }
}

extension BinaryFloatingPoint {
    var zoomed: CGFloat { CGFloat(self) * ZoomModel.shared.scale }
}

extension View {
    /// What every window and panel root sets, so its controls and any text
    /// that names no role of its own follow the zoom without being touched
    /// one by one: the root control size, and the control role's type (13pt
    /// regular at 100%, the macOS default). Never the menu bar label, which
    /// stays the size of the menu bar.
    func zoomRoot() -> some View {
        controlSize(Tokens.Zoom.rootControlSize)
            .font(Tokens.Typography.control)
    }
}

extension Tokens {
    /// Native controls (check boxes, switches, pop-ups, sliders, progress
    /// bars) are drawn at fixed control sizes, not at a font size, so the zoom
    /// moves them along the size scale: one smaller below 100%, one larger
    /// above 110%. Read these while a view draws, like a length. The bezel
    /// grows; the title of a pop-up or bordered button does not, since AppKit
    /// draws it at its own size whatever the font (`.extraLarge` keeps it
    /// too, so the band stops at one step).
    enum Zoom {
        private static let sizes: [ControlSize] = [.mini, .small, .regular, .large, .extraLarge]

        /// What a window or panel root sets, so every control in it follows
        /// the zoom without being touched one by one.
        static var rootControlSize: ControlSize { controlSize(.regular) }

        /// `requested` moved by the zoom's step, stopping at both ends of the scale.
        static func controlSize(_ requested: ControlSize) -> ControlSize {
            guard let index = sizes.firstIndex(of: requested) else { return requested }
            let shift = InterfaceZoom.controlSizeShift(forPercent: ZoomModel.shared.percent)
            return sizes[min(max(index + shift, 0), sizes.count - 1)]
        }
    }
}
