import SwiftUI

/// A line for each stretch of what the Mac did: its key, its time, what it
/// was and for how long. A gap card lists its hole's stretches oldest first;
/// the day's Mac card lists the day's, newest first.
struct GapStretchList: View {
    let anatomy: GapAnatomy
    /// The stretches to list, in the order to list them.
    let stretches: [GapAnatomy.Stretch]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Tokens.Space.m,
             verticalSpacing: Tokens.Space.s) {
            ForEach(Array(stretches.enumerated()), id: \.offset) { _, stretch in
                GridRow {
                    GapSwatch(state: stretch.state)
                        .frame(width: 10.zoomed, height: 10.zoomed)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    Text(time(of: stretch.span))
                        .font(Tokens.Typography.body.monospacedDigit()).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2.zoomed) {
                        Text(stretch.title).font(Tokens.Typography.body)
                        if let detail = detail(of: stretch) {
                            Text(detail).font(Tokens.Typography.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(durations: Tokens.preciseDuration(stretch.span.duration))
                        .font(Tokens.Typography.body.monospacedDigit())
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// One time for a stretch that starts and ends in the same minute, such
    /// as a quit Daybook was back from in seconds, rather than "4:48 – 4:48".
    private func time(of span: DateInterval) -> String {
        let start = Tokens.timeOfDayOnly(span.start)
        return start == Tokens.timeOfDayOnly(span.end) ? start : Tokens.timeRange(span.start, span.end)
    }

    /// What a stretch adds beyond its name and time.
    private func detail(of stretch: GapAnatomy.Stretch) -> String? {
        switch stretch.state {
        case .locked:
            guard let dark = stretch.displayOff else { return nil }
            return dark == stretch.span ? "Display off throughout"
                : "Display off \(Tokens.timeRange(dark.start, dark.end))"
        case .uncertain:
            let found = stretch.foundAt.map { "; found when Daybook opened at \(Tokens.timeOfDayOnly($0))" }
            return "Some time in this window" + (found ?? "")
        case .unexplained:
            let inside = anatomy.starts.filter { stretch.span.start < $0.at && $0.at < stretch.span.end }
            guard !inside.isEmpty else { return nil }
            return inside.map { "\($0.title) at \(Tokens.timeOfDayOnly($0.at))" }.joined(separator: ", ")
        case .asleep, .off:
            return nil
        }
    }
}
