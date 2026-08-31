import SwiftUI

/// A compact elapsed-time strip of the foreground app evidence. It is not a
/// typing waveform: coloured runs are observed apps and outlined runs are
/// explicitly named gaps in the supplied session span.
struct StoryShapeChart: View {
    let activity: RecordedActivity
    let appColourIndices: [String: Int]
    var height: CGFloat = 28
    var compact = false
    @StateObject private var intervalDetailsShown = BoolBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                let intervals = activity.intervals.filter { $0.duration > 0 }
                let gaps = max(0, intervals.count - 1)
                let available = max(0, geometry.size.width - CGFloat(gaps * 2))
                HStack(spacing: 2) {
                    ForEach(intervals) { interval in
                        intervalView(interval)
                            .frame(width: width(of: interval, available: available))
                    }
                }
            }
            .frame(height: height)
            if !compact, let first = activity.intervals.first, let last = activity.intervals.last {
                HStack {
                    Text(Tokens.timeOfDayOnly(first.start))
                    Spacer(minLength: 8)
                    Text(Tokens.timeOfDayOnly(last.end))
                }
                .font(.caption2.monospacedDigit())
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

    private func width(of interval: RecordedActivity.Interval, available: CGFloat) -> CGFloat {
        guard activity.elapsed > 0 else { return 0 }
        return max(2, available * CGFloat(interval.duration / activity.elapsed))
    }

    private func intervalView(_ interval: RecordedActivity.Interval) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(colour(interval))
            .overlay {
                if interval.isGap {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.secondary.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .contentShape(Rectangle())
            .help(detail(interval))
            .accessibilityLabel(detail(interval))
    }

    private func colour(_ interval: RecordedActivity.Interval) -> Color {
        guard let bundleID = interval.bundleID else { return Tokens.Palette.untracked.opacity(0.22) }
        return Tokens.Palette.app(rank: appColourIndices[bundleID] ?? interval.colourIndex ?? 6)
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
