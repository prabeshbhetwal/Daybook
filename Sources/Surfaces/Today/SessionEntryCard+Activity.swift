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
            sectionLabel("App use")
            if let activity {
                StoryShapeChart(activity: activity)
            }
            factualCaption
        }
        .help(shape ?? "Shows recorded app use, not typing.")
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
}
