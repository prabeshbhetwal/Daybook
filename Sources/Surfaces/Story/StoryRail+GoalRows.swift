import SwiftUI

/// The target rows under the ring: a category goal or an activity goal. Both
/// count what the ring counts, so a row never outruns it.
extension StoryRail {
    /// Activity goals for the day shown, each against its focus in any session.
    var activityTargets: [(id: UUID, purpose: AppPurpose, goal: TimeInterval, achieved: TimeInterval)] {
        store.activityTargets(on: day ?? store.selectedDay)
    }

    /// One quiet line: mark, name, figure, a thin bar.
    func goalTargetRow(symbol: String, tint: Color, name: String, goal: TimeInterval,
                       achieved: TimeInterval, help: String) -> some View {
        let share = goal > 0 ? min(1, achieved / goal) : 0
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: symbol)
                    .font(Tokens.Typography.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 14.zoomed)
                Text(name)
                    .font(Tokens.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Tokens.Space.s)
                Text(durations: share >= 1 ? "\(Tokens.duration(goal)) ✓"
                     : "\(Tokens.duration(achieved)) of \(Tokens.duration(goal))")
                    .font(Tokens.Typography.body.monospacedDigit())
                    .fixedSize()
                    .foregroundStyle(share >= 1 ? AnyShapeStyle(StoryStyle.successInk)
                                                : AnyShapeStyle(StoryStyle.supportingInk))
            }
            GeometryReader { geometry in
                Capsule().fill(StoryStyle.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: geometry.size.width * share)
                    }
            }
            .frame(height: 3.zoomed)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DurationText.spoken(in: "\(name): \(Tokens.duration(achieved)) of a \(Tokens.duration(goal)) goal"))
        .help(help)
        .accessibilityHint(help)
    }

    func activityTargetRow(_ item: (id: UUID, purpose: AppPurpose, goal: TimeInterval, achieved: TimeInterval)) -> some View {
        goalTargetRow(symbol: item.purpose.symbolName, tint: StoryStyle.focus, name: item.purpose.displayName,
                      goal: item.goal, achieved: item.achieved,
                      help: "Counts \(item.purpose.displayName.lowercased()) in any focus session, by the apps in front."
                          + (item.purpose == .coding ? " AI apps such as Claude and ChatGPT count as Writing & AI." : ""))
    }
}
