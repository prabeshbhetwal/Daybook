import SwiftUI

/// Settings → Away → Apps working for you: what quiet means while
/// an agent, a render or a build works, and how Daybook can tell. Written for someone who has
/// never heard of a hook.
extension SettingsGroups {
    var agentsPanel: some View {
        SurfacePanel(title: "Apps working for you", layout: layout) {
            preferenceRow("Agent at work", detail: agentPolicyDetail) {
                RowMenu("Agent at work", selection: $model.agentQuietPolicy,
                        options: AgentQuietPolicy.allCases) { $0.title }
            }
            rowDivider
            // Beside the choice it qualifies: it only matters when agent time counts.
            preferenceRow("Unattended agent time counts for",
                          detail: "After this long with no input, agent time is still recorded but stops counting toward your goals.") {
                ThresholdControl(label: "Unattended agent time counts for", selection: $model.agentUnattendedLimit,
                                 options: FocusConstants.agentUnattendedLimitOptions, allowsNever: true,
                                 neverTitle: "No limit")
            }
            .disabled(model.agentQuietPolicy != .countAsWork)
            rowDivider
            toggleRow("Notice apps working for you by themselves",
                      detail: "Reads network and processor load of apps used this session, never content.",
                      isOn: $model.noticesAppsAtWork)
                .disabled(model.agentQuietPolicy == .ignore)
            rowDivider
            preferenceRow("Let your agent tell Daybook when it works",
                          detail: "Claude Code, Codex, Gemini CLI or Cursor. Paste the message into the agent.") {
                IconButton(systemImage: copiedAgentSetup ? "checkmark" : "doc.on.doc",
                           help: "Copy Setup Message",
                           label: copiedAgentSetup ? "Copied" : "Copy Setup Message") {
                    model.copyAgentSetupMessage()
                    copiedAgentSetup = true
                }
                // Back to the copy glyph after two seconds. A task of the
                // view, so leaving the page cancels the wait.
                .task(id: copiedAgentSetup) {
                    guard copiedAgentSetup else { return }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled { copiedAgentSetup = false }
                }
            }
            explanation(agentExplanation)
        }
    }

    private var agentPolicyDetail: String {
        switch model.agentQuietPolicy {
        case .trackSeparately:
            return "Your session keeps running. Agent time is shown on its own and leaves your goals to you."
        case .countAsWork:
            return "Your session keeps running, and agent time counts toward your goals alongside yours."
        case .pauseQuietly:
            return "The clock stops while an agent works, without asking about a break."
        case .ignore:
            return "Quiet time is time away, and you are asked about it when you come back."
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
