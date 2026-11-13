import SwiftUI

/// A compact elapsed-time strip of the foreground app evidence. It is not a
/// typing waveform: filled runs are observed apps and outlined runs are
/// explicitly named gaps in the supplied session span. Every app wears the one
/// app-use accent; a thin divider in the card colour shows each switch, and a
/// run wide enough carries the app's icon.
///
/// The strip is drawn in cells, one per `cellPitch` points of width, each
/// taking the app that held the front for most of it. An interval per
/// rectangle was legible for a short session and a barcode for a long one —
/// several hundred slivers that overran the row. Exact intervals stay one
/// click away under "Show intervals".
struct StoryShapeChart: View {
    let activity: RecordedActivity
    /// nil draws the strip 28 points high, read as the strip draws.
    var height: CGFloat?
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
    private static var cellPitch: CGFloat { 6.zoomed }
    /// A cell never spans less than this, so a short session shows a few
    /// honest cells rather than one per second.
    private static let minimumCellSeconds: TimeInterval = 10

    var body: some View {
        let summary = Self.summary(of: activity)
        // Read here, not in the reader's closure, so a zoom change draws the strip again.
        let pitch = Self.cellPitch
        VStack(alignment: .leading, spacing: 5.zoomed) {
            GeometryReader { geometry in
                let runs = SessionShape.runs(activity: activity,
                                             cellCount: cellCount(for: geometry.size.width, pitch: pitch))
                let cells = max(1, runs.reduce(0) { $0 + $1.cells })
                let unit = geometry.size.width / CGFloat(cells)
                // One band, clipped once. Runs abut and are told apart by a
                // 1pt divider; a corner radius on each run made every short
                // one a bead, and the row read as a string of them.
                HStack(spacing: 0) {
                    ForEach(runs) { run in
                        // The compact strip has no caption line, so its
                        // tooltip leads with the whole strip before the run.
                        runView(run, size: CGSize(width: unit * CGFloat(run.cells),
                                                  height: geometry.size.height),
                                help: compact ? "\(summary)\n\(detail(run))" : detail(run))
                            .frame(width: unit * CGFloat(run.cells))
                    }
                }
                .overlay(alignment: .leading) {
                    ForEach(AppMarkLayout.dividerCells(runs), id: \.self) { cell in
                        Rectangle().fill(StoryStyle.card)
                            .frame(width: 1) // zoom: fixed
                            .offset(x: unit * CGFloat(cell) - 0.5) // zoom: fixed
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay(alignment: .leading) {
                    ForEach(AppMarkLayout.streaks(runs), id: \.startCell) { streak in
                        if AppMarkLayout.showsIcon(width: unit * CGFloat(streak.cells),
                                                   height: geometry.size.height,
                                                   scale: ZoomModel.shared.scale) {
                            AppIcon(bundleID: streak.bundleID, size: AppMarkLayout.iconPoints.zoomed,
                                    appName: appNames[streak.bundleID] ?? "")
                                .frame(width: unit * CGFloat(streak.cells), height: geometry.size.height)
                                .offset(x: unit * CGFloat(streak.startCell))
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous))
                // No motion on the runs: they are data, and they change with
                // every app switch.
            }
            .frame(height: height ?? 28.zoomed)
            if !compact, let first = activity.intervals.first, let last = activity.intervals.last {
                HStack {
                    if let run = hovered.run {
                        Text(caption(run))
                            .lineLimit(1)
                    } else {
                        Text(Tokens.timeOfDayOnly(first.start))
                        Spacer(minLength: Tokens.Space.s)
                        Text(Tokens.timeOfDayOnly(last.end))
                    }
                }
                .font(Tokens.Typography.body.monospacedDigit())
                .foregroundStyle(StoryStyle.supportingInk)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: runsListedBelow ? .ignore : .contain)
        .accessibilityLabel("App use: recorded app use, not typing intensity")
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
            text += gaps == 1 ? " 1 gap with no app use recorded." : " \(gaps) gaps with no app use recorded."
        }
        return text
    }

    private func cellCount(for width: CGFloat, pitch: CGFloat) -> Int {
        let byWidth = Int(width / pitch)
        let byTime = Int(activity.elapsed / Self.minimumCellSeconds)
        return max(1, min(byWidth, byTime))
    }

    private func runView(_ run: SessionShape.Run, size: CGSize, help: String) -> some View {
        Rectangle()
            .fill(colour(run))
            .overlay {
                if run.isGap {
                    Rectangle()
                        .strokeBorder(Color.secondary.opacity(0.65), // ink: quiet, a drawn mark
                                      style: StrokeStyle(lineWidth: 1, dash: [2.zoomed, 2.zoomed]))
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
        run.isGap ? Tokens.Palette.untracked.opacity(0.22) : Tokens.Palette.appUse
    }

    private var appNames: [String: String] {
        Dictionary(activity.intervals.compactMap { interval in
            interval.bundleID.map { ($0, interval.appName ?? $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// "Mostly", because a run is the app that held the front for most of its
    /// cells; a briefer switch inside it is listed in the full report.
    private func detail(_ run: SessionShape.Run) -> String { Self.detail(run, names: appNames) }

    /// Also the run's accessibility label, so the app is named whether or not
    /// its icon fits in the run.
    static func detail(_ run: SessionShape.Run, names: [String: String]) -> String {
        let range = Tokens.timeRange(run.start, run.end)
        guard let bundleID = run.bundleID else {
            return "Mostly no app use recorded, \(range)"
        }
        return "Mostly \(names[bundleID] ?? bundleID), \(range), "
            + "\(Tokens.preciseDuration(run.recordedSeconds)) recorded app use"
    }
}

final class HoveredRunBox: ObservableObject {
    @Published var run: SessionShape.Run?
}
