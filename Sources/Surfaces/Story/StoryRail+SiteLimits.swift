import SwiftUI

extension StoryRail {
    /// Today's site limits only, as with app limits: a past day shows what it recorded.
    var siteLimits: [(id: UUID, name: String, limit: TimeInterval)] {
        day == nil ? DailyGoalList.siteLimits(store.goalItems) : []
    }

    /// A kind of site kept under a limit. Nothing can count it yet, so it says
    /// so instead of "0m of 2h limit", which would read as kept.
    func siteLimitRow(_ item: (id: UUID, name: String, limit: TimeInterval)) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            Image(systemName: "globe")
                .font(Tokens.Typography.caption)
                .foregroundStyle(StoryStyle.supportingInk)
                .accessibilityHidden(true)
            Text(item.name)
                .font(Tokens.Typography.body)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Tokens.Space.s)
            Text(DailyGoalList.siteLimitUnavailable)
                .font(Tokens.Typography.caption)
                .fixedSize()
                .foregroundStyle(StoryStyle.supportingInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DurationText.spoken(in: "\(item.name): \(Tokens.duration(item.limit)) limit, \(DailyGoalList.siteLimitUnavailable.lowercased())"))
        .help("Daybook cannot yet tell which kind of site a browser shows, so this limit is not counted")
    }
}
