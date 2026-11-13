import SwiftUI
import AppKit

/// How a text box says it holds the cursor: the focus blue as a border, thicker,
/// and a soft halo of it. Lifted from History's search field so the Settings
/// search, the away prompt's name box, the activity field and Ask's question
/// field answer focus the same way.
private struct FieldFocusChrome: ViewModifier {
    let focused: Bool
    let cornerRadius: CGFloat
    let fill: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            // The halo sits on the fill alone, so the text never blurs with it.
            .background(shape.fill(fill)
                .shadow(color: StoryStyle.focus.opacity(focused ? 0.28 : 0), radius: 6.zoomed))
            .overlay(shape.strokeBorder(focused ? StoryStyle.focus : Tokens.Colour.line,
                                        lineWidth: focused ? 1.5.zoomed : 1))
            .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                       value: focused)
    }
}

/// The ring a row wears while the keyboard is on it: the system's own focus
/// colour, drawn along the row's rounded shape. The system ring is a square
/// drawn around the button, and sat over a rounded row like a broken outline.
private struct KeyboardFocusRing: ViewModifier {
    let focused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if focused {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3.zoomed)
            }
        }
    }
}

extension View {
    /// The fill, border and halo of a text box, in its focused state or not.
    /// `fill` is the box's own surface; the corner defaults to a nested panel's.
    func fieldFocusChrome(_ focused: Bool,
                          cornerRadius: CGFloat = Tokens.Radius.nested,
                          fill: Color = Tokens.Colour.elevated) -> some View {
        modifier(FieldFocusChrome(focused: focused, cornerRadius: cornerRadius, fill: fill))
    }

    /// A focus ring along a rounded row, for a row the keyboard is on.
    func keyboardFocusRing(_ focused: Bool, cornerRadius: CGFloat) -> some View {
        modifier(KeyboardFocusRing(focused: focused, cornerRadius: cornerRadius))
    }
}
