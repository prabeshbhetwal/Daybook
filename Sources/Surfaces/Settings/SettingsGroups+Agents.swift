import SwiftUI

/// Settings → Away & Breaks → Apps working for you: what quiet means while
/// an agent, a render or a build works, and how Daybook can tell. Written for someone who has
/// never heard of a hook.
extension SettingsGroups {
    var agentsPanel: some View {
        SurfacePanel(title: "Apps working for you", layout: layout) {
            preferenceRow("While an app works for you", detail: agentPolicyDetail) {
                Picker("While an app works for you", selection: $model.agentQuietPolicy) {
                    ForEach(AgentQuietPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("While an app works for you")
            }
            rowDivider
            toggleRow("Notice apps working for you by themselves",
                      detail: "Needs no setup. When an app you used in this session keeps sending data, as an "
                        + "AI agent does with its AI service, or keeps the processor busy, as a render, an "
                        + "export or a build does, Daybook takes it that the work goes on. It only looks at "
                        + "how much, never at what. Syncing and backup apps you did not use do not count.",
                      isOn: $model.noticesAppsAtWork)
                .disabled(model.agentQuietPolicy == .ignore)
            rowDivider
            toggleRow("Count a coding app in front as you being here",
                      detail: "While an editor, a terminal or an AI app is the app in front, Daybook takes it "
                        + "that you are watching. It cannot see whether you walked away, so leave this off "
                        + "if you often go with that window still open.",
                      isOn: $model.countsAgentAppInFront)
                .disabled(model.agentQuietPolicy == .ignore)
            rowDivider
            toggleRow("Count a keep-awake app as you being here",
                      detail: "For apps such as Amphetamine, Caffeine or KeepingYouAwake. While one keeps your "
                        + "screen on, Daybook takes it that you are here, even when you are not: a lunch "
                        + "with it on counts too. Leave this off unless that is what you want.",
                      isOn: $model.countsKeepAwake)
                .disabled(model.agentQuietPolicy == .ignore)
            rowDivider
            preferenceRow("Let your agent tell Daybook when it works",
                          detail: "The most exact way, for agents that support it: Claude Code, Codex, Gemini "
                            + "CLI and Cursor. Copy the message and paste it into the agent; it sets itself "
                            + "up, and Daybook then knows each time it starts and finishes a step.") {
                Button(copiedAgentSetup ? "Copied" : "Copy Setup Message") {
                    model.copyAgentSetupMessage()
                    copiedAgentSetup = true
                }
            }
            explanation(agentExplanation)
        }
    }

    private var agentPolicyDetail: String {
        switch model.agentQuietPolicy {
        case .countAsWork:
            return "When an AI agent, a render or a build is busy on your task and you are only "
                + "watching, your session keeps counting. Once it stops, the usual rules for stepping "
                + "away apply."
        case .pauseQuietly:
            return "While you only watch an app work, your session stops counting, but you are not "
                + "asked whether you took a break. Type or click to carry on."
        case .ignore:
            return "Apps at work make no difference. If you do not type or click for a while, it counts "
                + "as time away and you are asked about it."
        }
    }

    /// The limits, said plainly: the screen has to be on, and a run left
    /// going overnight is not a night's work.
    private var agentExplanation: String {
        var text = "Daybook notices work going on only while the screen is on and unlocked; locking the "
            + "Mac or letting the screen sleep is still time away."
        if !FocusConstants.isNever(model.longAwayCap) {
            text += " After \(Tokens.duration(model.longAwayCap)) without a key or click, Daybook takes "
                + "it that you have left, even if an app is still busy."
        }
        return text
    }
}
