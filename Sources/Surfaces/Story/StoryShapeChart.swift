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
    /// Set where a list beneath names every interval, so VoiceOver hears the
    /// strip once as a summary rather than each run again.
    var runsListedBelow = false
    /// The run under the pointer, named beneath the strip the moment it is
    /// hovered — a tooltip arrives a second later, too late for a glance.
    @StateObject private var hovered = HoveredRunBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points per cell. Six keeps a run of one cell visible as a mark, not a
    /// hairline, at the strip's 28pt height.
    private static let cellPitch: CGFloat = 6
    /// A cell never spans less than this, so a short session shows a few
    /// honest cells rather than one per second.
    private static let minimumCellSeconds: TimeInterval = 10

    var body: some View {
        let summary = Self.summary(of: activity)
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
                        // The compact strip has no caption line, so its
                        // tooltip leads with the whole strip before the run.
                        runView(run, help: compact ? "\(summary)\n\(detail(run))" : detail(run))
                            .frame(width: unit * CGFloat(run.cells))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous))
                .animation(Tokens.Motion.animation(Tokens.Motion.settle, reduceMotion: reduceMotion),
                           value: activity.coverage)
            }
            .frame(height: height)
            if !compact, let first = activity.intervals.first, let last = activity.intervals.last {
                HStack {
                    if let run = hovered.run {
                        Text(caption(run))
                            .lineLimit(1)
                            .transition(.opacity)
                    } else {
                        Text(Tokens.timeOfDayOnly(first.start))
                        Spacer(minLength: 8)
                        Text(Tokens.timeOfDayOnly(last.end))
                    }
                }
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .animation(Tokens.Motion.animation(Tokens.Motion.tick, reduceMotion: reduceMotion),
                           value: hovered.run?.id)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: runsListedBelow ? .ignore : .contain)
        .accessibilityLabel("App activity: recorded app use, not typing intensity")
        .accessibilityValue(summary)
    }

    /// The strip in words: the apps that held the front longest, and how many
    /// gaps it has.
    static func summary(of activity: RecordedActivity) -> String {
        var totals: [String: TimeInterval] = [:]
        var names: [String: String] = [:]
        var gaps = 0
        for interval in activity.intervals {
            guard let bundleID = interval.bundleID else { gaps += 1; continue }
            totals[bundleID, default: 0] += interval.duration
            if names[bundleID] == nil { names[bundleID] = interval.appName ?? bundleID }
        }
        let ranked = totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var apps = ranked.prefix(3).map { "\(names[$0.key] ?? $0.key) \(Tokens.spent($0.value))" }
        if ranked.count > 3 {
            let more = ranked.count - 3
            apps.append(more == 1 ? "and 1 more app" : "and \(more) more apps")
        }
        var text = apps.isEmpty ? "No app use recorded." : apps.joined(separator: ", ") + "."
        if gaps > 0 {
            text += gaps == 1 ? " 1 gap with no app recording." : " \(gaps) gaps with no app recording."
        }
        return text
    }

    private func cellCount(for width: CGFloat) -> Int {
        let byWidth = Int(width / Self.cellPitch)
        let byTime = Int(activity.elapsed / Self.minimumCellSeconds)
        return max(1, min(byWidth, byTime))
    }

    private func runView(_ run: SessionShape.Run, help: String) -> some View {
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
            .onHover { inside in
                if inside { hovered.run = run } else if hovered.run?.id == run.id { hovered.run = nil }
            }
            .help(help)
            .accessibilityLabel(detail(run))
    }

    /// What the strip says while a run is under the pointer: the app, when,
    /// how long.
    private func caption(_ run: SessionShape.Run) -> String {
        let name = run.bundleID.map { appNames[$0] ?? $0 } ?? "Not recorded"
        return "\(name) · \(Tokens.timeRange(run.start, run.end)) · \(Tokens.preciseDuration(run.isGap ? run.end.timeIntervalSince(run.start) : run.recordedSeconds))"
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
    /// cells; a briefer switch inside it is listed in the full report.
    private func detail(_ run: SessionShape.Run) -> String {
        let range = Tokens.timeRange(run.start, run.end)
        guard let bundleID = run.bundleID else {
            return "Mostly no app recording, \(range)"
        }
        return "Mostly \(appNames[bundleID] ?? bundleID), \(range), "
            + "\(Tokens.preciseDuration(run.recordedSeconds)) recorded app use"
    }
}

final class HoveredRunBox: ObservableObject {
    @Published var run: SessionShape.Run?
}
