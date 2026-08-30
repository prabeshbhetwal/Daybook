import SwiftUI

/// The app's signature element: the day's goal as a ring. Accent fill over a
/// well track, round caps, a label in the middle — the share, or a check once
/// the goal is met. Animates on change and nowhere else.
struct GoalRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: Double
    var diameter: CGFloat = 64
    var lineWidth: CGFloat = 7
    var label: String?
    var isMet: Bool = false
    /// The hero's 120pt ring wants a 22pt label; the default suits 56–64pt.
    var labelFont: Font = Tokens.Typography.ringLabel

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Surface.well, lineWidth: lineWidth)
            Circle()
                // Drawn clamped; `progress` itself may exceed 1 so the figures
                // beside it can say "160%" honestly.
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8),
                           value: progress)
            if isMet {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.3, weight: .bold))
                    .foregroundStyle(.tint)
            } else if let label {
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, lineWidth + 2)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent of today's goal")
    }
}
