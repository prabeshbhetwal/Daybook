import SwiftUI

/// The day in eight 3-hour columns: solid app-use blue for focus, stripes of
/// the same blue for other app use, the leading app's icon underneath, and an
/// outline for hours still to come. What it means is behind the tile's info
/// mark; the headline above it says when focus peaked.
struct TimeOfDayChart: View {
    let blocks: [RhythmBlock]
    var height: CGFloat = 60.zoomed
    /// The chart's width, measured, so the icons appear only where they fit.
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            HStack(alignment: .bottom, spacing: Tokens.Space.s) {
                ForEach(blocks) { block in
                    column(block)
                        .help(Self.detail(block))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.detail(block))
                }
            }
            .frame(height: height, alignment: .bottom)
            .overlay(alignment: .bottom) { Rectangle().fill(Tokens.Colour.line).frame(height: 1) } // zoom: fixed
            if showsIcons {
                HStack(spacing: Tokens.Space.s) {
                    ForEach(blocks) { block in
                        Group {
                            if block.seconds > 0, let bundleID = block.topBundleID {
                                AppIcon(bundleID: bundleID, size: AppMarkLayout.iconPoints.zoomed,
                                        appName: block.topAppName ?? "")
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: AppMarkLayout.iconPoints.zoomed)
                    }
                }
                .accessibilityHidden(true)
            }
            HStack(spacing: Tokens.Space.s) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    Color.clear.frame(height: 1).overlay(alignment: .leading) { // zoom: fixed
                        if index % 2 == 0 {
                            Text(DateFormats.hourLabel(block.start)).fixedSize()
                        }
                    }
                }
            }
            .padding(.top, Tokens.Space.s)
            .font(Tokens.Typography.caption)
            .foregroundStyle(StoryStyle.supportingInk)
            .accessibilityHidden(true)
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, new in width = new }
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus and app use by time of day")
    }

    @ViewBuilder private func column(_ block: RhythmBlock) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous)
        if block.isAhead {
            shape.strokeBorder(Tokens.Colour.line, style: StrokeStyle(lineWidth: 1, dash: [3.zoomed, 2.zoomed])) // zoom: fixed
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                HatchFill(ink: Tokens.Palette.appUse.opacity(0.45))
                    .frame(height: height * share(block.otherSeconds))
                Tokens.Palette.appUse
                    .frame(height: height * share(block.focusSeconds))
            }
            .frame(minHeight: 3.zoomed, alignment: .bottom)
            .background(alignment: .bottom) { shape.fill(Tokens.Colour.elevated).frame(height: 3.zoomed) }
            .clipShape(shape)
            .frame(maxWidth: .infinity)
        }
    }

    private func share(_ seconds: TimeInterval) -> CGFloat {
        CGFloat(min(1, seconds / scaleMaximum))
    }

    /// At least an hour, so one quiet block does not fill the chart.
    private var scaleMaximum: TimeInterval { max(3_600, blocks.map(\.seconds).max() ?? 0) }

    private var showsIcons: Bool {
        let count = CGFloat(blocks.count)
        guard count > 0, blocks.contains(where: { $0.seconds > 0 && $0.topBundleID != nil }) else { return false }
        let column = (width - Tokens.Space.s * (count - 1)) / count
        return AppMarkLayout.showsIcon(width: Double(column), scale: ZoomModel.shared.scale)
    }

    /// "12 am–3 am · 1h 10m focus · 15m other · top app: Claude", for the
    /// pointer and VoiceOver alike.
    static func detail(_ block: RhythmBlock) -> String {
        let range = Self.range(block)
        if block.isAhead { return "\(range) · still to come" }
        guard block.seconds > 0 else { return "\(range) · nothing recorded" }
        return "\(range) · \(Tokens.preciseDuration(block.focusSeconds)) focus · "
            + "\(Tokens.preciseDuration(block.otherSeconds)) other"
            + (block.topAppName.map { " · top app: \($0)" } ?? "")
    }

    static func range(_ block: RhythmBlock) -> String {
        "\(DateFormats.hourLabel(block.start))–\(DateFormats.hourLabel(block.end))"
    }

    /// "Most focus 12 am–3 am · Claude"; with no focus, the busiest block.
    static func headline(_ blocks: [RhythmBlock]) -> String? {
        guard let standout = Rhythm.standout(blocks) else { return nil }
        let lead = standout.isFocus ? "Most focus" : "Most app use"
        return "\(lead) \(range(standout.block))" + (standout.block.topAppName.map { " · \($0)" } ?? "")
    }

    static let help: [HelpEntry] = [
        HelpEntry("Columns", "Each column is 3 hours. Solid blue is app use during focus; "
                  + "striped blue is other app use."),
        HelpEntry("Icons", "The app used most in those hours."),
        HelpEntry("Outlines", "Hours still to come today."),
    ]
}
