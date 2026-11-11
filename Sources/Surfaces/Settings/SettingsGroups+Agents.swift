import SwiftUI

/// Settings → Away → Apps working for you: what quiet means while
/// an agent, a render or a build works, and how Daybook can tell. Written for someone who has
/// never heard of a hook.
extension SettingsGroups {
    var agentsPanel: some View {
        SurfacePanel(title: "Apps working for you", layout: layout) {
            preferenceRow("While an app works for you", detail: agentPolicyDetail) {
                RowMenu("While an app works for you", selection: $model.agentQuietPolicy,
                        options: AgentQuietPolicy.allCases) { $0.title }
            }
            rowDivider
            toggleRow("Notice apps working for you by themselves",
                      detail: "Reads network and processor load of apps used this session, never content.",
                      isOn: $model.noticesAppsAtWork)
                .disabled(model.agentQuietPolicy == .ignore)
            rowDivider
            toggleRow("Count a coding app in front as you being here",
                      detail: "Leave off if you often walk away with it open.",
                      isOn: $model.countsAgentAppInFront)
                .disabled(model.agentQuietPolicy == .ignore)
            rowDivider
            toggleRow("Count a keep-awake app as you being here",
                      detail: "Amphetamine, Caffeine and similar. A lunch with one on counts too.",
                      isOn: $model.countsKeepAwake)
                .disabled(model.agentQuietPolicy == .ignore)
            rowDivider
            preferenceRow("Let your agent tell Daybook when it works",
                          detail: "Claude Code, Codex, Gemini CLI or Cursor. Paste the message into the agent.") {
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
            return "Your session keeps counting while an agent, render or build runs."
        case .pauseQuietly:
            return "The clock stops while you watch, without asking about a break."
        case .ignore:
            return "Quiet time counts as away, as usual."
        }
    }

    /// The limits, said plainly: the screen has to be on, and a run left
    /// going overnight is not a night's work.
    private var agentExplanation: String {
        var text = "Works only while the screen is on and unlocked."
        if !FocusConstants.isNever(model.longAwayCap) {
            text += " After \(Tokens.duration(model.longAwayCap)) without input, you count as gone."
        }
        return text
    }
}
