import SwiftUI

/// Settings → Away & Breaks → AI agents: what quiet means while an agent
/// works, and how Daybook can tell it is working. Written for someone who has
/// never heard of a hook.
extension SettingsGroups {
    var agentsPanel: some View {
        SurfacePanel(title: "AI agents", layout: layout) {
            preferenceRow("While an AI agent works for you", detail: agentPolicyDetail) {
                Picker("While an AI agent works for you", selection: $model.agentQuietPolicy) {
                    ForEach(AgentQuietPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("While an AI agent works for you")
            }
            rowDivider
            toggleRow("Notice AI tools at work by themselves",
                      detail: "Needs no setup and works with most AI tools: Cursor, Antigravity, Claude, "
                        + "Codex, Gemini, Copilot and others. An AI agent at work keeps sending your work to "
                        + "its AI service, so Daybook watches how much data coding and AI apps send. It never "
                        + "looks at what they send. A long upload from one of them, such as a big git push, "
                        + "counts too while it lasts.",
                      isOn: $model.detectsAgentTraffic)
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
            return "When an AI agent is busy on your task and you are only watching, your session keeps "
                + "counting. Once the agent stops, the usual rules for stepping away apply."
        case .pauseQuietly:
            return "While you only watch an agent work, your session stops counting, but you are not "
                + "asked whether you took a break. Type or click to carry on."
        case .ignore:
            return "Agents make no difference. If you do not type or click for a while, it counts as "
                + "time away and you are asked about it."
        }
    }

    /// The limits, said plainly: the screen has to be on, and a run left
    /// going overnight is not a night's work.
    private var agentExplanation: String {
        var text = "Daybook notices an agent only while the screen is on and unlocked; locking the Mac "
            + "or letting the screen sleep is still time away."
        if !FocusConstants.isNever(model.longAwayCap) {
            text += " After \(Tokens.duration(model.longAwayCap)) without a key or click, Daybook takes "
                + "it that you have left, even if an agent is still busy."
        }
        return text
    }
}
