import SwiftUI

/// The category editor's behaviour rows, apart from `CategoriesView.swift`: the daily goal, break reminders and
/// whether the category counts toward focus goals (ruling C20), which Break is never offered.
extension CategoryEditorForm {
    static func offersFocusSetting(for id: String?) -> Bool { id != WorkType.breakTime.rawValue }

    /// What the category means for the day: its own goal, and whether break
    /// reminders run during it.
    var behaviourRows: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.s) {
                Text("Daily goal")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                Picker("Daily goal", selection: $editor.dailyGoal) {
                    Text("None").tag(0.0)
                    ForEach(WorkTypeDefinition.goalOptions, id: \.self) { seconds in
                        Text(Tokens.duration(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .fixedSize()
                // A category that adds nothing to focus has no goal (`WorkType.dailyGoal`); the value is kept for later.
                .disabled(!editor.countsTowardFocus)
                .accessibilityLabel("Daily goal for this category")
                Text("Its own line under Focus time, beside the day's goal.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
            }
            Toggle("Remind me to take breaks during this category", isOn: $editor.remindsBreaks)
                .toggleStyle(.switch)
                .controlSize(Tokens.Zoom.controlSize(.mini))
            Text("Off, break reminders wait while a session of this category runs. "
                 + "Meetings starts off: nobody wants to be told to stand up mid-call.")
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
            if Self.offersFocusSetting(for: editor.selectedID) {
                Toggle("Counts toward focus goals", isOn: $editor.countsTowardFocus)
                    .toggleStyle(.switch)
                    .controlSize(Tokens.Zoom.controlSize(.mini))
                Text("Off, its sessions are still recorded but add nothing to focus time or goals.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
