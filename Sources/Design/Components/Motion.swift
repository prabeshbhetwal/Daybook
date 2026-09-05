import SwiftUI

/// The feedback every control in the app gives, so that pressing anything
/// feels like pressing the same material. Two styles, one vocabulary:
/// `StoryPressStyle` dims (rows, cards, text actions); `PressableStyle` sinks
/// (filled and iconic controls). Both are inert under Reduce Motion.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PressableLabel<Label: View>: View {
    let label: Label
    let pressed: Bool
    @StateObject private var hovered = BoolBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label
            .scaleEffect(pressed ? Tokens.Motion.pressedScale
                         : hovered.value && enabled ? Tokens.Motion.hoverScale : 1)
            // A hover lifts a filled control a shade; a press settles it.
            .brightness(!enabled ? 0 : pressed ? -0.08 : hovered.value ? 0.05 : 0)
            .opacity(enabled ? 1 : 0.45)
            // Down is instant; up is the spring. The click is over before a
            // symmetric ease could show anything.
            .animation(Tokens.Motion.animation(pressed ? Tokens.Motion.press : Tokens.Motion.release,
                                               reduceMotion: reduceMotion),
                       value: pressed)
            .animation(Tokens.Motion.animation(Tokens.Motion.hover, reduceMotion: reduceMotion),
                       value: hovered.value)
            .onHover { hovered.value = $0 }
    }
}

extension View {
    /// A hover tint behind a row or text action. The tint fades in rather than
    /// appearing, and never appears under Reduce Motion's instant rule either
    /// way — a tint is state, not motion.
    func hoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }

    /// A figure that rolls to its next value instead of being replaced: a
    /// timer's seconds, a total after a refresh, the ring's percentage.
    func rollingDigits<Value: Equatable>(_ value: Value) -> some View {
        modifier(RollingDigits(value: value))
    }

    /// A glyph that becomes another glyph: pencil to tick, pin to pinned.
    /// macOS 14 crossfades symbols; 13 swaps them, which is still correct.
    @ViewBuilder func symbolSwap() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    /// A glyph that acknowledges a change of state with a small dip — the
    /// pin when pinned, the tick when the order is saved. macOS 14 only; on
    /// 13 the swap is the acknowledgement.
    @ViewBuilder func symbolNod<Value: Equatable>(on value: Value) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce.down.byLayer, value: value)
        } else {
            self
        }
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @StateObject private var hovered = BoolBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(hovered.value ? Tokens.Colour.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(Tokens.Motion.animation(Tokens.Motion.hover, reduceMotion: reduceMotion),
                       value: hovered.value)
            .onHover { hovered.value = $0 }
    }
}

private struct RollingDigits<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(Tokens.Motion.animation(Tokens.Motion.tick, reduceMotion: reduceMotion),
                       value: value)
    }
}
