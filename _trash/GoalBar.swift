import SwiftUI

/// The day against its target. One line, no card — the same rule the rest of
/// this app follows: a figure sits beside the evidence for it.
///
/// The pace note appears only when there is a personal median behind it. For a
/// first week of use there is none, and the bar simply says nothing rather than
/// comparing today against a number invented from two days of history.
struct GoalBar: View {
    let progress: GoalProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Tokens.Space.s) {
                Text(Tokens.duration(progress.achieved))
                    .font(.callout.weight(.medium).monospacedDigit())
                // "of 4h" alone left the reader to infer what 4h was. It is the
                // goal, and saying so costs one word.
                Text("of \(Tokens.duration(progress.goal)) goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if progress.isMet {
                    Label("Goal met", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .labelStyle(.titleAndIcon)
                } else if let pace = paceNote {
                    Text(pace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(progress.isMet ? AnyShapeStyle(.tint)
                                             : AnyShapeStyle(Color.accentColor.opacity(0.8)))
                        // Clamped for drawing only; `share` itself stays
                        // uncapped so the figures can exceed the goal honestly.
                        .frame(width: geometry.size.width * min(1, max(0, progress.share)))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(progress.share * 100)) percent of today's goal")
        // No `.help` here either. The caller attaches an instant explanation
        // that can also name the comparison figure, which this view knows but
        // a second overlapping tooltip has no business repeating.
    }

    private var paceNote: String? {
        guard let ahead = progress.aheadBy else { return nil }
        if ahead >= 60 { return "\(Tokens.duration(ahead)) ahead of usual" }
        if ahead <= -60 { return "\(Tokens.duration(-ahead)) behind usual" }
        return "on your usual pace"
    }
}
