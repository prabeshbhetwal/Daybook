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

/// A ring around the thing the current card is talking about.
///
/// Drawn outside the control and never over it, so the control stays visible,
/// hittable and unchanged. The welcome points at the app; it does not stand in
/// front of it. Hit testing is off throughout — a user who ignores the card and
/// goes straight for the button must never be blocked by the ring around it.
struct CoachRing: View {
    let rect: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var breathing = BoolBox()

    /// Enough to clear a capsule button without looking like a second control.
    private static let inset: CGFloat = 7
    private static let radius: CGFloat = Tokens.Radius.nested + Self.inset

    var body: some View {
        let frame = rect.insetBy(dx: -Self.inset, dy: -Self.inset)
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .strokeBorder(StoryStyle.focus, lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .fill(StoryStyle.focus.opacity(0.07))
            )
            .frame(width: max(0, frame.width), height: max(0, frame.height))
            .position(x: frame.midX, y: frame.midY)
            .opacity(breathing.value ? 0.55 : 1)
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                       value: breathing.value)
            .onAppear { if !reduceMotion { breathing.value = true } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
