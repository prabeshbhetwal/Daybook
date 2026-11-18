import SwiftUI

/// What a session's time was spent on, phase by phase, drawn as the app strip is drawn: one band
/// clipped once, runs in proportion to their time, a 1-point divider in the card colour between
/// them, and no motion. Focused work that counted fills with the session's colour, other counted
/// time with the same colour at a quiet strength, and time the session did not count (a watching
/// pause, away) is outlined, as the app strip draws its gaps. A run wide enough carries its
/// purpose's symbol. The phases come worked out from `StorySessionDetail.phases`; nothing here
/// reckons time beyond each run's share of the width.
struct SessionPhaseStrip: View {
    let shape: SessionActivityShape
    let tint: Color               // the session's Tokens.Palette.workType
    var height: CGFloat?          // nil: 28.zoomed, as StoryShapeChart

    enum Fill: Equatable { case solid, quiet, outlined }

    /// The app strip's own threshold: shorter, a strip turns seconds of evidence into noise.
    static let minimumElapsed: TimeInterval = 120
    /// The share of the session's colour a counted phase of unfocused work takes.
    static let quietStrength = 0.5

    static func shows(_ shape: SessionActivityShape?, lasted elapsed: TimeInterval) -> Bool {
        elapsed >= minimumElapsed && !(shape?.phases.isEmpty ?? true)
    }

    /// The strip where `shows` allows it, else nothing.
    @ViewBuilder static func ifShown(_ shape: SessionActivityShape?, lasted elapsed: TimeInterval, tint: Color) -> some View {
        if let shape, shows(shape, lasted: elapsed) { SessionPhaseStrip(shape: shape, tint: tint) }
    }

    static func fill(_ phase: SessionPhase) -> Fill {
        guard phase.counted else { return .outlined }
        if case .purpose(let purpose) = phase.activity, purpose.isFocused { return .solid }
        return .quiet
    }

    var body: some View {
        let phases = shape.phases
        let total = max(1, phases.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) })
        VStack(alignment: .leading, spacing: 5.zoomed) {
            GeometryReader { geometry in
                let widths = phases.map { geometry.size.width * CGFloat($0.end.timeIntervalSince($0.start) / total) }
                HStack(spacing: 0) {
                    ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                        run(phase, width: widths[index], height: geometry.size.height)
                    }
                }
                .overlay(alignment: .leading) {
                    ForEach(1..<max(1, phases.count), id: \.self) { index in
                        Rectangle().fill(StoryStyle.card)
                            .frame(width: 1) // zoom: fixed
                            .offset(x: widths[..<index].reduce(0, +) - 0.5) // zoom: fixed
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous))
            }
            .frame(height: height ?? 28.zoomed)
            if let note = SessionPhaseText.fidelityNote(shape) {
                Text(note)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phases: what the session's time was spent on")
        .accessibilityValue(SessionPhaseText.summary(shape))
    }

    private func run(_ phase: SessionPhase, width: CGFloat, height: CGFloat) -> some View {
        let fill = Self.fill(phase)
        return Rectangle()
            .fill(colour(fill))
            .overlay {
                switch fill {
                case .solid: EmptyView()
                // The edge in the full colour keeps a quiet run apart from the card.
                case .quiet: Rectangle().strokeBorder(tint, lineWidth: 1)
                case .outlined:
                    Rectangle()
                        .strokeBorder(Color.secondary.opacity(0.65), // ink: quiet, a drawn mark, as the app strip's gaps
                                      style: StrokeStyle(lineWidth: 1, dash: [2.zoomed, 2.zoomed]))
                }
            }
            .overlay {
                if case .purpose(let purpose) = phase.activity,
                   AppMarkLayout.showsIcon(width: width, height: height, scale: ZoomModel.shared.scale) {
                    Image(systemName: purpose.symbolName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: AppMarkLayout.iconPoints.zoomed, height: AppMarkLayout.iconPoints.zoomed)
                        .foregroundStyle(iconInk(fill))
                }
            }
            .frame(width: width)
            .help(SessionPhaseText.phaseLine(phase))
    }

    private func colour(_ fill: Fill) -> Color {
        switch fill {
        case .solid: return tint
        case .quiet: return tint.opacity(Self.quietStrength)
        case .outlined: return Tokens.Palette.untracked.opacity(0.22)
        }
    }

    private func iconInk(_ fill: Fill) -> Color {
        switch fill {
        case .solid: return StoryStyle.card
        case .quiet: return .primary
        case .outlined: return StoryStyle.supportingInk
        }
    }
}
