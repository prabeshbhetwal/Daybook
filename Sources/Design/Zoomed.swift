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

extension Tokens {
    /// Native controls (check boxes, switches, pop-ups, sliders, progress
    /// bars) are drawn at fixed control sizes, not at a font size, so the zoom
    /// moves them along the size scale: one smaller below 100%, one larger
    /// above 110%. Read these while a view draws, like a length.
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
