import SwiftUI

/// Today's category goals in the menu-bar panel: one quiet row each, mark,
/// name, figures and a slim bar. The figures are the store's, the same ones
/// the Story rail's goal rows show. Draws nothing when no goal is set.
struct PopoverGoalsCard: View {
    @ObservedObject var store: SessionStore
    /// A renamed or re-iconed category redraws these rows on its own.
    @ObservedObject private var catalog = WorkTypeCatalog.shared
    var dense = false

    var body: some View {
        let goals = store.categoryGoals(on: store.now())
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                SectionHeader(title: "Today's goals", compact: true)
                ForEach(goals) { PopoverGoalRow(status: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: dense ? Tokens.Space.m : Tokens.Space.l,
                  radius: Tokens.Radius.popoverCard)
        }
    }
}

private struct PopoverGoalRow: View {
    let status: CategoryGoalStatus

    var body: some View {
        let achieved = Tokens.preciseDuration(status.achieved)
        let target = Tokens.preciseDuration(status.goal)
        let tint = Tokens.Palette.workType(status.type)
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: status.type.symbolName)
                    .font(Tokens.Typography.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 16.zoomed)
                Text(status.type.displayName)
                    .font(Tokens.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Tokens.Space.s)
                if status.isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(StoryStyle.successInk)
                }
                Text("\(achieved) / \(target)")
                    .font(Tokens.Typography.body.monospacedDigit())
                    .fixedSize()
                    .foregroundStyle(status.isMet ? AnyShapeStyle(StoryStyle.successInk)
                                                  : AnyShapeStyle(StoryStyle.supportingInk))
            }
            GeometryReader { geometry in
                Capsule().fill(StoryStyle.line)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(status.isMet ? StoryStyle.successInk : tint)
                            .frame(width: geometry.size.width * status.share)
                    }
            }
            .frame(height: 4.zoomed)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DurationText.spoken(
            in: "\(status.type.displayName): \(achieved) of a \(target) goal"
                + (status.isMet ? ". Goal met" : "")))
    }
}
