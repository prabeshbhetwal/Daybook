import SwiftUI

/// Settings → Sessions: the goal and its rewards, how a session starts and
/// ends, and the sessions Daybook starts by itself. Categories sit between,
/// in their own file. Nothing here is about how Daybook looks or sounds
/// (General) or what it keeps (Privacy & Data).
extension SettingsGroups {
    var focus: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            goalPanel
            dailyGoalsPanel
            startingAndEndingPanel
        }
    }

    private var goalPanel: some View {
        SurfacePanel(title: "Goal", layout: layout) {
            preferenceRow("Daily goal", detail: "Counts focus only while you're at the Mac.") {
                RowMenu("Daily goal", selection: $model.dailyGoal,
                        options: FocusConstants.dailyGoalOptions) { Tokens.duration($0) }
            }
            rowDivider
            preferenceRow("Usual pace compares with") {
                RowMenu("Usual pace compares with", selection: $model.paceWindowDays,
                        options: FocusConstants.paceWindowOptions) { "last \($0) days" }
            }
            rowDivider
            preferenceRow("Streak counts a day after") {
                ThresholdControl(label: "Streak counts a day after", selection: $model.streakMinimum,
                                 options: FocusConstants.streakMinimumOptions)
            }
            rowDivider
            toggleRow("Celebrate milestones", detail: "Goal, streak and pace.", isOn: $model.rewardsEnabled)
        }
    }

    private var startingAndEndingPanel: some View {
        SurfacePanel(title: "Starting and ending", layout: layout) {
            preferenceRow("New sessions start as") {
                RowMenu("New sessions start as", selection: $model.defaultWorkType,
                        items: WorkType.startable.map { .option($0, $0.displayName, systemImage: $0.symbolName) })
            }
            rowDivider
            preferenceRow("Suggest activities from") {
                RowMenu("Suggest activities from", selection: $model.suggestionWindowDays,
                        options: FocusConstants.suggestionWindowOptions) { "last \($0) days" }
            }
            rowDivider
            preferenceRow("Keep sessions longer than", detail: "Shorter ones are never saved.") {
                RowMenu("Keep sessions longer than", selection: $model.minimumRecordedSession,
                        options: FocusConstants.minimumRecordedSessionOptions) { Tokens.preciseDuration($0) }
            }
            rowDivider
            preferenceRow("Offer to continue for", detail: "Counted from when a session ends.") {
                ThresholdControl(label: "Offer to continue for", selection: $model.continueWindow,
                                 options: FocusConstants.continueWindowOptions)
            }
        }
    }

    var automatic: some View {
        let rulesOn = model.activityRuleAutomationEnabled
        return VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Automatic sessions", layout: layout) {
                // While rules are on the guess is not in effect, so the switch
                // reads off. Only its reading changes: the stored choice is
                // kept for when rules are turned off again.
                toggleRow("Guess sessions from the app in front",
                          detail: rulesOn ? "Off while activity rules are on."
                                          : "Work apps start a session; break apps pause it.",
                          isOn: Binding(get: { model.autoSessionsEnabled && !rulesOn },
                                        set: { model.autoSessionsEnabled = $0 }))
                    .disabled(rulesOn)
                rowDivider
                preferenceRow("Stop a paused automatic session after") {
                    ThresholdControl(label: "Stop a paused automatic session after",
                                     selection: $model.autoSessionPauseLimit,
                                     options: FocusConstants.autoSessionPauseLimitOptions, allowsNever: true)
                }
            }
        }
    }

    /// Privacy & Data: whether app use is recorded at all. How much of it
    /// the Story shows is a display choice, in General.
    var tracking: some View {
        SurfacePanel(title: "App use", layout: layout) {
            toggleRow("Record app use", detail: "Off, Story shows sessions only.", isOn: $model.isTrackingEnabled)
        }
    }
}
