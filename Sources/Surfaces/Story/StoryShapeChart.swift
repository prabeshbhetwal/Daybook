import SwiftUI

/// Eight equal-time columns show observed app-use coverage. An empty interval
/// stays at the baseline; the graph never claims to measure typing intensity.
struct StoryShapeChart: View {
    let bins: [SessionShape.Bin]
    let primaryApp: String?
    let tint: Color
    var height: CGFloat = 44
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bins) { bin in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(colour(bin))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, height * bin.fraction))
                        .frame(height: height, alignment: .bottom)
                        .help("\(Tokens.timeRange(bin.start, bin.end)): \(Tokens.preciseDuration(bin.recordedSeconds)) recorded app use")
                        .accessibilityLabel("\(Tokens.timeRange(bin.start, bin.end)), \(Tokens.spent(bin.recordedSeconds)) recorded app use")
                }
            }
            .frame(height: height)
            if !compact {
                Text("Recorded app use, not typing intensity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shape of recorded app use")
    }

    private func colour(_ bin: SessionShape.Bin) -> Color {
        guard bin.recordedSeconds > 0 else { return StoryStyle.line }
        return bin.dominantBundleID == primaryApp ? tint : Tokens.Palette.slate
    }
}
