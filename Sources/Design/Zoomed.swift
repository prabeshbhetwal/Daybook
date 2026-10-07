import CoreGraphics

/// A length written as `12.zoomed` is 12 points at 100% and scales with the
/// interface zoom. Read it while a view draws, never in an `init` or a stored
/// `let`, so the view is drawn again when the zoom changes.
extension BinaryInteger {
    var zoomed: CGFloat { CGFloat(Int(clamping: self)) * ZoomModel.shared.scale }
}

extension BinaryFloatingPoint {
    var zoomed: CGFloat { CGFloat(self) * ZoomModel.shared.scale }
}
