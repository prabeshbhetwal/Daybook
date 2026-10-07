import SwiftUI

/// The app's signature element: the day's goal as a ring. Accent fill over a
/// well track, round caps, a label in the middle — the share, or a check once
/// the goal is met. Animates on change and nowhere else.
struct GoalRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: Double
    var diameter: CGFloat = 64.zoomed
    var lineWidth: CGFloat = 7.zoomed
    var label: String?
    var isMet: Bool = false
    /// What VoiceOver names the ring. Its value is the share, so the words
    /// stay true on a past day as well as today.
    var accessibilityTitle = "Daily goal"

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Colour.elevated, lineWidth: lineWidth)
            Circle()
                // Drawn clamped; `progress` itself may exceed 1 so the figures
                // beside it can say "160%" honestly.
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // The arc follows `progress` exactly on every draw; the settle
                // runs only when it has moved half a per cent. Keyed on the raw
                // share it restarted every second, for a change no eye could see.
                .animation(Tokens.Motion.animation(Tokens.Motion.settle, reduceMotion: reduceMotion),
                           value: (progress * 200).rounded())
            if isMet {
                Image(systemName: "checkmark")
                    .font(Tokens.Typography.fitted(diameter * 0.3, weight: .bold))
                    .foregroundStyle(.tint)
                    .transition(Tokens.Motion.transition(.scale.combined(with: .opacity),
                                                         reduceMotion: reduceMotion))
            } else if let label {
                Text(label)
                    .font(Tokens.Typography.ring)
                    .foregroundStyle(.primary)
                    .rollingDigits(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, lineWidth + 2.zoomed)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(Tokens.Motion.animation(Tokens.Motion.release, reduceMotion: reduceMotion),
                   value: isMet)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(DurationText.percent(progress, spoken: true))
    }
}
