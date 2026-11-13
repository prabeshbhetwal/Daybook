import SwiftUI
import AppKit

/// One visit in the report's Recorded activity list, as the text it shows.
/// Built once for the list, so a row that scrolls into view formats nothing.
struct ReportActivityRowModel: Identifiable, Equatable {
    let id: String
    let interval: RecordedActivity.Interval
    let power: PowerReading?
    /// The app's name, or why a gap is there.
    let name: String
    let time: String
    let duration: String
}

/// The widths of the list's three aligned columns. Every row puts a column at
/// one x, whatever its own text, so they are worked out for the list.
struct ReportColumnWidths: Equatable {
    var time: CGFloat
    var level: CGFloat
    var duration: CGFloat
}

/// The rows of the Recorded activity list, latest first, and the column
/// widths they share.
struct ReportActivityList: Equatable {
    let rows: [ReportActivityRowModel]
    let widths: ReportColumnWidths

    /// The widest a column can read, so a short list lines up as a long one
    /// does. Each column is at least this wide, and wider if a row needs it.
    static let timeSamples = ["12:00 am – 12:00 am", "12:00 pm – 12:00 pm"]
    static let durationSamples = ["00h 00m"]
    static let levelSamples = ["100%"]

    /// `listed` is the report's visits and long gaps in time order. Each text
    /// is formatted once, and `measure` runs once per distinct shape of text
    /// (digits count alike in the rows' tabular figures), never once per row.
    static func make(listed: [RecordedActivity.Interval],
                     power: (RecordedActivity.Interval) -> PowerReading?,
                     gapTitle: (RecordedActivity.Interval) -> String,
                     measure: (String) -> CGFloat = ReportTextWidth.body) -> ReportActivityList {
        let rows = listed.reversed().map { interval in
            ReportActivityRowModel(
                id: interval.id, interval: interval, power: power(interval),
                name: interval.isGap ? gapTitle(interval) : (interval.appName ?? interval.bundleID ?? "App"),
                time: Tokens.timeRange(interval.start, interval.end),
                duration: Tokens.preciseDuration(interval.duration))
        }
        return ReportActivityList(
            rows: rows,
            widths: ReportColumnWidths(
                time: widest(floor: timeSamples, rows.map(\.time), measure),
                level: widest(floor: levelSamples, rows.compactMap { $0.power?.level }, measure),
                duration: widest(floor: durationSamples, rows.map(\.duration), measure)))
    }

    private static func widest(floor samples: [String], _ texts: [String],
                               _ measure: (String) -> CGFloat) -> CGFloat {
        var shapes = Set<String>()
        var widest: CGFloat = 0
        for text in samples + texts {
            guard shapes.insert(String(text.map { $0.isNumber ? "0" : $0 })).inserted else { continue }
            widest = max(widest, measure(text))
        }
        return widest
    }
}

/// Text widths in the face the rows are drawn in.
enum ReportTextWidth {
    /// The body size with tabular figures, at the current zoom. A point of
    /// slack, so a column never truncates by a fraction of a pixel.
    static func body(_ text: String) -> CGFloat {
        let font = Tokens.Typography.bodyDigitsNSFont
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 1
    }
}

/// One visit in the report's Recorded activity list: its mark, its time,
/// its app, the power reading when it changed, and how long it lasted. Every
/// column after the name keeps one x on every row. Equatable, so the 1 Hz
/// ticker redraws no row whose text has not changed.
struct ReportActivityRow: View, Equatable {
    let model: ReportActivityRowModel
    let widths: ReportColumnWidths

    private var interval: RecordedActivity.Interval { model.interval }

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Circle()
                .fill(interval.isGap ? AnyShapeStyle(StoryStyle.line)
                                     : AnyShapeStyle(Tokens.Palette.appUse))
                .frame(width: 8.zoomed, height: 8.zoomed)
            column(Text(model.time), width: widths.time, alignment: .leading)
            Text(model.name)
                .font(Tokens.Typography.body)
                .foregroundStyle(interval.isGap ? AnyShapeStyle(StoryStyle.supportingInk) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .help(model.name)
            Spacer(minLength: Tokens.Space.s)
            powerMark
            column(Text(durations: model.duration), width: widths.duration, alignment: .trailing)
        }
        .frame(minHeight: 26.zoomed)
        .accessibilityElement(children: .combine)
    }

    /// A column as wide as the list's widest value, in the row's own font, so
    /// every row puts it at the same x at any text size. Sized to the text it
    /// held, a "48s" beside a "1m" moved the column left of it.
    private func column(_ text: Text, width: CGFloat, alignment: Alignment) -> some View {
        text
            .font(Tokens.Typography.body.monospacedDigit())
            .foregroundStyle(StoryStyle.supportingInk)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    /// The glyph centred in the widest glyph's space and the level
    /// right-aligned in the list's widest, so icons and percent signs each
    /// line up.
    private var powerMark: some View {
        HStack(spacing: Tokens.Space.xs) {
            ZStack {
                Image(systemName: "battery.100percent").hidden()
                if let power = model.power {
                    Image(systemName: power.symbolName)
                        .foregroundStyle(power.symbolName == "bolt.fill" ? AnyShapeStyle(StoryStyle.successInk)
                                                                         : AnyShapeStyle(StoryStyle.supportingInk))
                }
            }
            column(Text(model.power?.level ?? ""), width: widths.level, alignment: .trailing)
        }
        .font(Tokens.Typography.body)
        .help(model.power?.spoken ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.power?.spoken ?? "")
        .accessibilityHidden(model.power == nil)
    }
}

extension SessionReport {
    /// A gap shorter than this is not listed. An app in front for under
    /// `AppUsageConstants.minimumSegment` is Cmd-Tab noise and not recorded,
    /// so each quick switch left a "Not recorded" row of a few seconds. The
    /// gap still counts as unrecorded in every total above the list.
    static let shortestListedGap: TimeInterval = 60

    /// Every recorded visit, and every gap of a minute or more, in order.
    var listedIntervals: [RecordedActivity.Interval] { Self.listing(intervals) }

    static func listing(_ intervals: [RecordedActivity.Interval]) -> [RecordedActivity.Interval] {
        intervals.filter { !$0.isGap || $0.duration >= shortestListedGap }
    }

    static func gapReasons(_ intervals: [RecordedActivity.Interval], store: SessionStore,
                           day: Date) -> [String: StoryGapReason] {
        let gaps = intervals.filter(\.isGap)
        let reasons = store.gapReasons(for: gaps.map { DateInterval(start: $0.start, end: $0.end) }, on: day)
        return Dictionary(zip(gaps.map(\.id), reasons), uniquingKeysWith: { first, _ in first })
    }
}
