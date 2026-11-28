import Foundation

extension Tokens {
    /// `You 8h 21m · Agent 3h 28m`: a session's two lanes (`AgentLane`). Nil
    /// when the Agent lane is empty or under a minute, so a session from
    /// before the lane, or one no agent touched, never reads "Agent 0m".
    /// `together`, the part of `agent` the person also worked, stays in
    /// theirs and is named, since the lanes are never summed.
    static func laneSplit(worked: TimeInterval, agent: TimeInterval, together: TimeInterval = 0) -> String? {
        guard agent >= 60 else { return nil }
        let shared = min(max(0, together), agent)
        let line = "You \(duration(max(0, worked - agent + shared))) · Agent \(duration(agent))"
        return shared >= 60 ? line + " · \(duration(shared)) at once" : line
    }
}
