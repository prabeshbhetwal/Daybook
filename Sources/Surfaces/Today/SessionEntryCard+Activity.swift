import SwiftUI

/// The open card's evidence: what the session's time was spent on, phase by phase, above the
/// recorded app use, and the depth word beside the duration.
extension SessionEntryCard {
    var activityDetail: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if let activity, let phases, SessionPhaseStrip.shows(phases, lasted: activity.elapsed) {
                sectionLabel("Phases")
                SessionPhaseStrip(shape: phases, tint: Tokens.Palette.workType(session.workType))
            }
            HStack(spacing: Tokens.Space.xs) {
                sectionLabel("Apps used")
                InfoMark(title: "Apps used", entries: StoryShapeChart.help(shape: shape, gap: gapNote))
                Spacer(minLength: 0)
            }
            if let activity {
                StoryShapeChart(activity: activity)
            }
            if let shapeCaption {
                Text(shapeCaption)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder var factualCaption: some View {
        if let shape {
            Text(shape)
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let shapeCaption {
            Text(shapeCaption)
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The row's second line after the times: how many stretches the session ran as.
    @ViewBuilder var stretchesCaption: some View {
        if session.stretches > 1 {
            Text("· \(session.stretches) stretches")
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .help("This session ran as \(session.stretches) separate stretches; "
                      + "the gaps between them are not counted.")
        }
    }

    /// The duration on the title line, with the depth word after it once the phases are read. VoiceOver
    /// hears the depth with the phases (`SessionPhaseText.summary`): this line is hidden from it.
    func withDepth(_ duration: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
            duration
            if let word = SessionPhaseText.depthWord(phases?.depth) {
                Text(word)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
            }
        }
    }

    /// The category beside the times, and the AI mark after it when Apple Intelligence set it (C17). An unnamed
    /// session is titled by its category already, so only the mark shows.
    @ViewBuilder var categoryChip: some View {
        if !session.name.isEmpty {
            Text(session.workType.displayName)
                .font(Tokens.Typography.caption)
                .padding(.horizontal, 7.zoomed)
                .padding(.vertical, 2.zoomed)
                .background(Tokens.Palette.workType(session.workType).opacity(0.14), in: RoundedRectangle(cornerRadius: 5.zoomed))
                .foregroundStyle(StoryStyle.workTypeInk(session.workType))
        }
        if aiMark { AIMark() }
    }

    /// The category as the row's VoiceOver sentence says it, with the mark's words when it shows.
    static func spokenCategory(_ type: WorkType, aiMark: Bool) -> String {
        aiMark ? "\(type.displayName), \(AIMark.spoken)" : type.displayName
    }
}
