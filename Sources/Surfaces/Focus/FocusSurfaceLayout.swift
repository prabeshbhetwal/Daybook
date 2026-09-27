import SwiftUI

/// Focus is an operational canvas, not a report. The measure is deliberate: the
/// quiet space around it supports concentration and is never filled with
/// secondary metrics or charts, in any session state.
enum FocusSurfaceLayout {
    static let operationalMeasure: CGFloat = 760

    static func permitsSupportingReport(state: SessionState) -> Bool { false }
}
