import CoreGraphics
import Observation

/// The one interface zoom every window reads. A view that reads `percent` or
/// `scale` while it draws is drawn again when the zoom changes, so a change
/// reaches every open window together. Read and written on the main thread.
@Observable final class ZoomModel {
    static let shared = ZoomModel()

    private(set) var percent = InterfaceZoom.defaultPercent

    /// Exactly 1 at 100%, so an unzoomed length is the literal it was written as.
    var scale: CGFloat { CGFloat(percent) / 100 }

    /// Takes the step nearest `requested`; a request for the step already
    /// held changes nothing and redraws nothing.
    func apply(percent requested: Int) {
        let step = InterfaceZoom.snapped(requested)
        guard step != percent else { return }
        percent = step
    }
}
