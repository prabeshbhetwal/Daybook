import SwiftUI

/// The category chip a session card wears, for rows that name a session.
struct WorkTypeChip: View {
    let workType: WorkType

    var body: some View {
        Text(workType.displayName)
            .font(Tokens.Typography.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Tokens.Palette.workType(workType).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(StoryStyle.workTypeInk(workType))
            .accessibilityHidden(true)
    }
}
