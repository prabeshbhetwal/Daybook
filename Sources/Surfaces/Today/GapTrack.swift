import SwiftUI

/// A hole drawn to scale: each stretch's fill, a tick at each moment, the
/// times under them where they fit, and a dashed frame round a window an
/// event happened somewhere inside. The stretch list under it says the same
/// in words, so this stays out of VoiceOver's way.
struct GapTrack: View {
    let span: DateInterval
    let anatomy: GapAnatomy

    private var barTop: CGFloat { 4.zoomed }
    private var barHeight: CGFloat { 10.zoomed }
    private var labelTop: CGFloat { barTop + barHeight + 6.zoomed }
    private var labelWidth: CGFloat { 64.zoomed }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                GapBar(span: span, anatomy: anatomy)
                    .frame(height: barHeight)
                    .offset(y: barTop)
                ForEach(anatomy.stretches.filter { $0.state == .uncertain }.map(\.span), id: \.self) { window in
                    RoundedRectangle(cornerRadius: 5.zoomed)
                        .strokeBorder(StoryStyle.attentionInk,
                                      style: StrokeStyle(lineWidth: 1.5.zoomed, dash: [3.zoomed, 2.zoomed]))
                        .frame(width: x(window.end, width) - x(window.start, width) + 4.zoomed,
                               height: barHeight + 8.zoomed)
                        .offset(x: x(window.start, width) - 2.zoomed, y: barTop - 4.zoomed)
                }
                ForEach(anatomy.marks, id: \.self) { mark in
                    Capsule().fill(Color.primary.opacity(0.7))
                        .frame(width: 2.zoomed, height: barHeight + 8.zoomed)
                        .offset(x: x(mark, width) - 1.zoomed, y: barTop - 4.zoomed)
                }
                Group {
                    Text(Tokens.timeOfDayOnly(span.start))
                        .offset(y: labelTop)
                    Text(Tokens.timeOfDayOnly(span.end))
                        .frame(width: width, alignment: .trailing)
                        .offset(y: labelTop)
                    ForEach(labelled(width), id: \.self) { mark in
                        Text(Tokens.timeOfDayOnly(mark))
                            .frame(width: labelWidth)
                            .offset(x: x(mark, width) - labelWidth / 2, y: labelTop)
                    }
                }
                .font(Tokens.Typography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(height: labelTop + 14.zoomed)
        .accessibilityHidden(true)
    }

    private func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        guard span.duration > 0 else { return 0 }
        let fraction = date.timeIntervalSince(span.start) / span.duration
        return width * CGFloat(min(max(fraction, 0), 1))
    }

    /// The marks whose time fits between the ends' labels and its neighbours'.
    private func labelled(_ width: CGFloat) -> [Date] {
        var kept: [Date] = []
        var lastEdge = labelWidth * 1.2
        for mark in anatomy.marks {
            let position = x(mark, width)
            guard position >= lastEdge, width - position >= labelWidth * 1.2 else { continue }
            kept.append(mark)
            lastEdge = position + labelWidth
        }
        return kept
    }
}

/// Each stretch's fill, side by side, to scale.
struct GapBar: View {
    let span: DateInterval
    let anatomy: GapAnatomy

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(anatomy.stretches.enumerated()), id: \.offset) { _, stretch in
                    GapFill(state: stretch.state)
                        .frame(width: geometry.size.width
                               * CGFloat(stretch.span.duration / max(span.duration, 1)))
                }
            }
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// A state's fill: lighter for nearer the desk, darker for further away.
struct GapFill: View {
    let state: GapAnatomy.State

    var body: some View {
        switch state {
        case .unexplained, .uncertain: HatchFill()
        case .locked: StoryStyle.macLocked
        case .asleep: StoryStyle.macAsleep
        case .off: StoryStyle.macOff
        }
    }
}

/// The key beside a stretch's line: its fill, or for a window an event
/// happened somewhere inside, the dashed frame the track draws round it.
struct GapSwatch: View {
    let state: GapAnatomy.State

    var body: some View {
        if state == .uncertain {
            RoundedRectangle(cornerRadius: 3.zoomed)
                .strokeBorder(StoryStyle.attentionInk,
                              style: StrokeStyle(lineWidth: 1.5.zoomed, dash: [2.zoomed, 1.5.zoomed]))
        } else {
            GapFill(state: state).clipShape(RoundedRectangle(cornerRadius: 3.zoomed))
        }
    }
}

/// Diagonal stripes for time no event explains: drawn, not a flat grey, so
/// it never reads as a state of its own.
struct HatchFill: View {
    var body: some View {
        Canvas { context, size in
            let step = 4.zoomed
            var path = Path()
            var start = -size.height
            while start < size.width {
                path.move(to: CGPoint(x: start, y: size.height))
                path.addLine(to: CGPoint(x: start + size.height, y: 0))
                start += step
            }
            context.stroke(path, with: .color(StoryStyle.macHatch), lineWidth: 1.5.zoomed)
        }
        .background(StoryStyle.card)
    }
}
