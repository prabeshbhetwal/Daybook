import SwiftUI

/// Watching or listening outside a session, on the day's timeline (plan Phase B Task 7). A row of its own,
/// so it is never read as a session, a break or focus.
struct LeisureBlockRow: View {
    let block: LeisureBlock
    let appName: String?

    private var length: TimeInterval { block.end.timeIntervalSince(block.start) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2.zoomed) {
                Text("Leisure outside a session").font(Tokens.Typography.label)
                Text([appName ?? block.activity.displayName, Tokens.timeRange(block.start, block.end)].joined(separator: ", "))
                    .font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
            }
            Spacer(minLength: Tokens.Space.s)
            Text(durations: Tokens.preciseDuration(length))
                .font(Tokens.Typography.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Never counted as focus or as a break")
    }
}
