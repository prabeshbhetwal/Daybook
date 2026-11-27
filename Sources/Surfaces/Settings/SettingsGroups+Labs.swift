import SwiftUI

/// Labs: features still being tried out. Each is off until the person turns
/// it on, and the page says plainly that it may change or go.
extension SettingsGroups {
    var labs: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            LabsNotice()
            SurfacePanel(title: "Hand off to agent", layout: layout) {
                toggleRow("Hand off to agent", detail: Self.handOffDetail, isOn: $model.offersHandOff)
                rowDivider
                explanation(Self.handOffEnds(limit: model.agentUnattendedLimit))
            }
        }
    }

    static let handOffDetail = "Adds Hand Off beside Step Away. Your session keeps running "
        + "as your agent's time, even when its work happens in the cloud, and your own time stops."

    static func handOffEnds(limit: TimeInterval) -> String {
        let start = "Touching the keyboard or mouse brings you back. "
        if FocusConstants.isNever(limit) { return start + "With no unattended limit set, it runs until you return." }
        return start + "It ends on its own after \(Tokens.duration(limit)), your unattended agent limit in Away."
    }
}

/// The page's opening card: what Labs is, said once, above the features.
private struct LabsNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: "flask")
                .font(Tokens.Typography.heading)
                .foregroundStyle(StoryStyle.supportingInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("Still being tried out")
                    .font(Tokens.Typography.rowTitle)
                Text("Features here are early. They may change, or leave Daybook, as we learn how they hold up. "
                     + "Each one is off until you turn it on.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)) // ink: quiet, a fill behind text, not text
        .accessibilityElement(children: .combine)
    }
}
