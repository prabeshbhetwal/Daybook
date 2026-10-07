import Dispatch
import Observation

/// Tells a window or panel its zoom changed, for what SwiftUI does not
/// redraw by itself: an AppKit frame. `onChange` runs on the main queue once
/// per change and stops when the follower is released.
///
/// Observation reports a change before the new value is stored, so a
/// handler called from there would read the old zoom. The call hops to the
/// main queue first, where the new value is in, and tracking is armed again
/// only then; a second change in between is still one call, and it reads the
/// latest zoom.
///
/// Made and released on the main thread, and called there: the hop's closure
/// holds it, which is what `@unchecked Sendable` lets it.
final class ZoomFollower: @unchecked Sendable {
    private let onChange: () -> Void

    init(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        arm()
    }

    private func arm() {
        withObservationTracking {
            _ = ZoomModel.shared.percent
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                // A released follower ends the chain here: it is not armed again.
                guard let self else { return }
                self.onChange()
                self.arm()
            }
        }
    }
}
