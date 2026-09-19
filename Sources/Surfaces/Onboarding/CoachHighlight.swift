import SwiftUI

/// Where a coached part of the window is, reported up to whoever is drawing
/// the welcome.
///
/// A preference rather than a shared geometry object: the parts being pointed
/// at — the chrome's button, the strip's field, the rail — sit in different
/// branches of the tree, and none of them should have to know that a coach
/// exists. They mark themselves; the coach reads the marks.
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [CoachAnchor: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachAnchor: Anchor<CGRect>],
                       nextValue: () -> [CoachAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Mark this view as something the welcome can point at. Inert unless a
    /// welcome is running: it publishes a rectangle and changes nothing else.
    func coachAnchor(_ anchor: CoachAnchor) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [anchor: $0] }
    }
}

/// Where the ring goes, and how it stays on screen.
enum CoachRingGeometry {
    /// Enough to clear a capsule button without looking like a second control.
    static let inset: CGFloat = 7
    /// The stroke, and the least of it that must stay visible at a window edge.
    static let lineWidth: CGFloat = 3
    static let radius: CGFloat = Tokens.Radius.nested + inset

    /// The ring grows outward from what it rings, then is held inside the
    /// window. A control flush against an edge — the rail against the right,
    /// the chrome against the top — otherwise pushed its ring past the edge,
    /// where the window clipped it and the reader saw three sides of four.
    static func frame(around rect: CGRect, within bounds: CGRect) -> CGRect {
        let grown = rect.insetBy(dx: -inset, dy: -inset)
        let limit = bounds.insetBy(dx: lineWidth, dy: lineWidth)
        let held = grown.intersection(limit)
        return held.isNull || held.isEmpty ? .null : held
    }
}

/// A ring around the thing the current card is talking about, and a step
/// back for everything else.
///
/// Drawn outside the control and never over it, so the control stays visible,
/// hittable and unchanged. The welcome points at the app; it does not stand in
/// front of it. Hit testing is off throughout — a reader who ignores the card
/// and goes straight for the button must never be blocked by the ring around
/// it, nor by the wash around the ring.
///
/// The wash is what makes the ring findable. A 2pt line at half opacity was
/// missed on a page full of tiles; a page that has dropped back a step,
/// with one part of it left at full strength, is read at a glance. The wash
/// is the same one the app already draws under a sheet.
struct CoachRing: View {
    let rect: CGRect
    /// The overlay's own bounds, so the ring can be held inside them.
    let bounds: CGRect
    /// Off, the ring is drawn still: no settle, no breath. Verification uses
    /// it to tell a ring that does not draw from one that is mid-motion.
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var breathing = BoolBox()

    var body: some View {
        let frame = CoachRingGeometry.frame(around: rect, within: bounds)
        if !frame.isNull {
            ZStack {
                wash(cutOut: frame)
                RoundedRectangle(cornerRadius: CoachRingGeometry.radius, style: .continuous)
                    .strokeBorder(Tokens.Colour.focus, lineWidth: CoachRingGeometry.lineWidth)
                    .background(
                        RoundedRectangle(cornerRadius: CoachRingGeometry.radius, style: .continuous)
                            .fill(Tokens.Colour.focus.opacity(0.06))
                    )
                    .shadow(color: Tokens.Colour.focus.opacity(0.45), radius: 8)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    // Arrives fully formed, then breathes slowly, so it stays
                    // alive without demanding. There is no entrance motion:
                    // it settled in from slightly larger once, and for the
                    // first quarter second the ring and its cut-out disagreed
                    // — which is when a still captures, and when a reader who
                    // looked up at the wrong moment saw a hole with no ring.
                    .opacity(breathing.value ? 0.72 : 1)
                    .animation(reduceMotion || !animated ? nil
                               : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                               value: breathing.value)
            }
            .onAppear {
                guard animated, !reduceMotion else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { breathing.value = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// One path, filled even-odd: the window with a rounded hole where the
    /// ring is. No mask, no blend mode, no offscreen group — those leak, and
    /// a destination-out mask erased the ring drawn beside it.
    private func wash(cutOut frame: CGRect) -> some View {
        Path { path in
            path.addRect(bounds)
            path.addRoundedRect(in: frame,
                                cornerSize: CGSize(width: CoachRingGeometry.radius,
                                                   height: CoachRingGeometry.radius),
                                style: .continuous)
        }
        .fill(Color.black.opacity(0.16), style: FillStyle(eoFill: true))
    }
}
