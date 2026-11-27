import Foundation

extension Tokens {
    /// `You 8h 21m · Agent 3h 28m`: a session's two lanes (`AgentLane`). Nil
    /// when the Agent lane is empty or under a minute, so a session from
    /// before the lane, or one no agent touched, never reads "Agent 0m".
    static func laneSplit(worked: TimeInterval, agent: TimeInterval) -> String? {
        guard agent >= 60 else { return nil }
        return "You \(duration(max(0, worked - agent))) · Agent \(duration(agent))"
    }
}
