import SwiftUI

/// One visit in the report's Recorded activity list: its colour, its time,
/// its app, the power reading when it changed, and how long it lasted. Every
/// column after the name keeps one x on every row.
struct ReportActivityRow: View {
    let interval: RecordedActivity.Interval
    let colourRank: Int
    let power: PowerReading?

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Circle()
                .fill(interval.isGap ? AnyShapeStyle(StoryStyle.line)
                                     : AnyShapeStyle(Tokens.Palette.app(rank: colourRank)))
                .frame(width: 8, height: 8)
            Self.column(Tokens.timeRange(interval.start, interval.end),
                        widest: ["12:00 am – 12:00 am", "12:00 pm – 12:00 pm"], alignment: .leading)
            let name = interval.isGap ? "Not recorded" : (interval.appName ?? interval.bundleID ?? "App")
            Text(name)
                .font(Tokens.Typography.body)
                .foregroundStyle(interval.isGap ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .help(name)
            Spacer(minLength: Tokens.Space.s)
            powerMark
            Self.column(Tokens.preciseDuration(interval.duration), widest: ["00h 00m"],
                        alignment: .trailing, durations: true)
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .combine)
    }

    /// A column as wide as its widest possible value, measured in the row's
    /// own font, so every row puts it at the same x at any text size. Sized
    /// to the text it held, a "48s" beside a "1m" moved the column left of it.
    private static func column(_ text: String, widest: [String], alignment: Alignment,
                               durations: Bool = false) -> some View {
        ZStack(alignment: alignment) {
            ForEach(widest, id: \.self) { Text($0).hidden() }
            if durations { Text(durations: text) } else { Text(text) }
        }
        .font(Tokens.Typography.body.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// The glyph centred in the widest glyph's space and the level
    /// right-aligned in "100%"'s, so icons and percent signs each line up.
    private var powerMark: some View {
        HStack(spacing: 4) {
            ZStack {
                Image(systemName: "battery.100percent").hidden()
                if let power {
                    Image(systemName: power.symbolName)
                        .foregroundStyle(power.symbolName == "bolt.fill" ? AnyShapeStyle(StoryStyle.successInk)
                                                                         : AnyShapeStyle(.secondary))
                }
            }
            Self.column(power?.level ?? "", widest: ["100%"], alignment: .trailing)
        }
        .font(Tokens.Typography.body)
        .help(power?.spoken ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(power?.spoken ?? "")
        .accessibilityHidden(power == nil)
    }
}
