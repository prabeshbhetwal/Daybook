import SwiftUI

/// The category chip a session card wears, for rows that name a session.
struct WorkTypeChip: View {
    let workType: WorkType

    var body: some View {
        Text(workType.displayName)
            .font(Tokens.Typography.caption)
            .padding(.horizontal, 7.zoomed)
            .padding(.vertical, 2.zoomed)
            .background(Tokens.Palette.workType(workType).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous))
            .foregroundStyle(StoryStyle.workTypeInk(workType))
            .accessibilityHidden(true)
    }
}
