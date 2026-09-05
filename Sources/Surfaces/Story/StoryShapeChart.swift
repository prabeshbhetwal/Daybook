import SwiftUI

/// A compact elapsed-time strip of the foreground app evidence. It is not a
/// typing waveform: coloured runs are observed apps and outlined runs are
/// explicitly named gaps in the supplied session span.
///
/// The strip is drawn in cells, one per `cellPitch` points of width, each
/// taking the app that held the front for most of it. An interval per
/// rectangle was legible for a short session and a barcode for a long one —
/// several hundred slivers that overran the row. Exact intervals stay one
/// click away under "Show intervals".
struct StoryShapeChart: View {
    let activity: RecordedActivity
    let appColourIndices: [String: Int]
    var height: CGFloat = 28
    var compact = false
    @StateObject private var intervalDetailsShown = BoolBox()

    /// Points per cell. Six keeps a run of one cell visible as a mark, not a
    /// hairline, at the strip's 28pt height.
    private static let cellPitch: CGFloat = 6
    /// A cell never spans less than this, so a short session shows a few
    /// honest cells rather than one per second.
    private static let minimumCellSeconds: TimeInterval = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                let runs = SessionShape.runs(activity: activity,
                                             cellCount: cellCount(for: geometry.size.width))
                let cells = max(1, runs.reduce(0) { $0 + $1.cells })
                let unit = geometry.size.width / CGFloat(cells)
                // One band, clipped once. Runs abut and are told apart by
                // colour; a corner radius on each run made every short one a
                // bead, and the row read as a string of them.
                HStack(spacing: 0) {
                    ForEach(runs) { run in
                        runView(run).frame(width: unit * CGFloat(run.cells))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: height)
            if !compact, let first = activity.intervals.first, let last = activity.intervals.last {
                HStack {
                    Text(Tokens.timeOfDayOnly(first.start))
                    Spacer(minLength: 8)
                    Text(Tokens.timeOfDayOnly(last.end))
                }
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                Button(intervalDetailsShown.value ? "Hide intervals" : "Show intervals") {
                    intervalDetailsShown.value.toggle()
                }
                .font(Tokens.Typography.metadata)
                .buttonStyle(StoryActionStyle())
                .accessibilityHint("Shows exact app activity and recording-gap times")
                if intervalDetailsShown.value {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(activity.intervals) { interval in
                            Text(detail(interval))
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App activity: recorded app use, not typing intensity")
    }

    private func cellCount(for width: CGFloat) -> Int {
        let byWidth = Int(width / Self.cellPitch)
        let byTime = Int(activity.elapsed / Self.minimumCellSeconds)
        return max(1, min(byWidth, byTime))
    }

    private func runView(_ run: SessionShape.Run) -> some View {
        Rectangle()
            .fill(colour(run))
            .overlay {
                if run.isGap {
                    Rectangle()
                        .strokeBorder(Color.secondary.opacity(0.65),
                                      style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .contentShape(Rectangle())
            .help(detail(run))
            .accessibilityLabel(detail(run))
    }

    private func colour(_ run: SessionShape.Run) -> Color {
        guard let bundleID = run.bundleID else { return Tokens.Palette.untracked.opacity(0.22) }
        return Tokens.Palette.app(rank: appColourIndices[bundleID] ?? colourIndices[bundleID] ?? 6)
    }

    private var appNames: [String: String] {
        Dictionary(activity.intervals.compactMap { interval in
            interval.bundleID.map { ($0, interval.appName ?? $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    private var colourIndices: [String: Int] {
        Dictionary(activity.intervals.compactMap { interval in
            interval.bundleID.flatMap { id in interval.colourIndex.map { (id, $0) } }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// "Mostly", because a run is the app that held the front for most of its
    /// cells; a briefer switch inside it is under "Show intervals".
    private func detail(_ run: SessionShape.Run) -> String {
        let range = Tokens.timeRange(run.start, run.end)
        guard let bundleID = run.bundleID else {
            return "Mostly no app recording, \(range)"
        }
        return "Mostly \(appNames[bundleID] ?? bundleID), \(range), "
            + "\(Tokens.preciseDuration(run.recordedSeconds)) recorded app use"
    }

    private func detail(_ interval: RecordedActivity.Interval) -> String {
        let range = Tokens.timeRange(interval.start, interval.end)
        if interval.isGap {
            return "Recording gap, \(range), \(Tokens.preciseDuration(interval.duration)), no app recording"
        }
        return "\(interval.appName ?? "Unknown app"), \(range), "
            + "\(Tokens.preciseDuration(interval.recordedSeconds)) recorded app use"
    }
}
