import SwiftUI

/// Settings → Privacy, under Use on-device AI: the switch that lets Apple Intelligence assign categories to
/// automatic sessions (ruling C20), with why it cannot be used when it cannot, the tally of how often its answer
/// matched the person's choice, and why its label file is not being written. `SettingsModel+AICategories`
/// works out every value; this only draws them.
extension SettingsGroups {
    static func aiSwitchUsable(_ model: SettingsModel) -> Bool { model.aiAssignDisabledReason == nil }

    @ViewBuilder var aiCategoryRows: some View {
        rowDivider
        toggleRow("Let AI assign categories to automatic sessions",
                  detail: model.aiAssignDisabledReason ?? (model.aiAssignsCategories
                      ? "Each category it sets carries a sparkle you can keep or change in the session report."
                      : "While off, the AI's choice shows only as a suggestion in the session report."),
                  isOn: $model.aiAssignsCategories)
            .disabled(!Self.aiSwitchUsable(model))
        if let tally = model.aiTallyText { explanation(tally) }
        explanation("Daybook keeps the AI's labels, fingerprints, answers and last 50 comparisons with your choices "
            + "in ai-labels.json beside your sessions, and no session names, notes, titles or addresses.")
        if let failure = model.aiLabelsFailure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Colour.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("AI categories error: \(failure)")
        }
    }
}
