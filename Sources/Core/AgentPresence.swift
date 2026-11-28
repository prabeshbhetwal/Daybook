import Foundation

/// What quiet at the keyboard means while an AI agent works for the user.
enum AgentQuietPolicy: String, CaseIterable {
    /// The session keeps running and the agent's time goes in its own lane,
    /// which goals leave out (`AgentLane`).
    case trackSeparately
    /// The session keeps running and goals count the agent's lane with the
    /// person's, up to the unattended limit.
    case countAsWork
    /// The clock stops without a question, as it does behind a film.
    case pauseQuietly
    /// Agents change nothing: quiet is an absence, asked about on return.
    case ignore

    var title: String {
        switch self {
        case .trackSeparately: return "Track separately"
        case .countAsWork: return "Count with my time"
        case .pauseQuietly: return "Pause the session"
        case .ignore: return "Treat it as time away"
        }
    }

    /// The session runs on while an agent works, and the Agent lane records it.
    var keepsSessionRunning: Bool { self == .trackSeparately || self == .countAsWork }
}

/// Whether an AI agent is working for the person at the session. Evidence,
/// surest first: the agent's own hooks posting `pingName`; a coding or AI app
/// busy using the network or processor (`WorkTraffic`). An agent's window in
/// front, or a keep-awake app holding the screen on, is not evidence: both
/// stay exactly so when the person walks away.
enum AgentPresence {
    /// The Darwin notification an agent hook posts: `notifyutil -p <name>`.
    static let pingName = "com.prabesh.daybook.agent-activity"

    /// Activity closer together than this is one stretch of work: an agent
    /// goes quiet between steps while it thinks or a command runs.
    static let window: TimeInterval = 5 * 60

    /// Agent clients, and the terminals command-line agents run in. Any other
    /// app Daybook counts as coding (`PurposeMap`) is a work app too.
    static let appBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop", "com.openai.codex", "com.openai.chat", "com.google.GeminiMacOS",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "com.github.wez.wezterm", "net.kovidgoyal.kitty"
    ]

    /// An app whose busy network is an agent at work, not a film or a sync.
    /// An agent in `agentApp` works alongside the person when they are in a different app. With
    /// the agent's own app in front the time is the person's.
    static func worksAlongside(front: String?, agentApp: String?) -> Bool {
        guard let agentApp, isWorkApp(agentApp) else { return false }
        return front != agentApp
    }

    static func isWorkApp(_ bundleID: String) -> Bool {
        appBundleIDs.contains(bundleID) || PurposeMap.purpose(for: bundleID, activity: .active) == .coding
    }

    /// Pasted into any agent that supports hooks, it sets the agent up to
    /// ping Daybook.
    static let setupMessage = """
        Please set up hooks so the Daybook app knows when you are working. In your own \
        user-level hook settings, add a command hook that runs:

        notifyutil -p \(pingName)

        when a prompt is submitted, before and after each tool, and when you stop, or on your \
        nearest equivalents. For example: Claude Code ~/.claude/settings.json and Codex \
        ~/.codex/hooks.json (UserPromptSubmit, PreToolUse, PostToolUse, Stop); Gemini CLI \
        ~/.gemini/settings.json (BeforeAgent, BeforeTool, AfterTool, AfterAgent); Cursor \
        ~/.cursor/hooks.json (beforeSubmitPrompt, beforeShellExecution, afterShellExecution, \
        afterFileEdit, stop). Keep every hook that is already there.
        """

    /// When an agent was last seen working, if that counts now; nil otherwise.
    /// Idle time after an agent stops is measured from this moment.
    ///
    /// - Parameters:
    ///   - quiet: seconds since the last key or click. Past `cap` nobody is at
    ///     the machine, whatever an agent is still doing, so a run left going
    ///     overnight is not a night's work.
    ///   - lastActivity: the latest hook ping or busy network reading. One from
    ///     before the last key or click says nothing about the quiet since; kept,
    ///     it held an idle pause off for up to `window` with no agent at work.
    static func lastSeen(now: Date, quiet: TimeInterval, lastActivity: Date?,
                         policy: AgentQuietPolicy, cap: TimeInterval) -> Date? {
        guard policy != .ignore, quiet < cap else { return nil }
        guard let lastActivity, lastActivity <= now,
              now.timeIntervalSince(lastActivity) < min(window, quiet) else { return nil }
        return lastActivity
    }
}
