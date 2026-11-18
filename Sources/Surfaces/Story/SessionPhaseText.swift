import Foundation

/// The phase strip in words: each run's tooltip, the depth word on the row's title line, and what
/// VoiceOver hears. The words never claim more than the shape knows: no depth word without a depth,
/// and a shape read from app use alone says so.
enum SessionPhaseText {
    static func depthWord(_ depth: SessionDepth?) -> String? {
        switch depth {
        case .deep: return "Deep"
        case .light: return "Light"
        case .passive: return "Passive"
        case nil: return nil
        }
    }

    static func activityName(_ activity: PhaseActivity) -> String {
        switch activity {
        case .purpose(let purpose): return purpose.displayName
        case .browsing: return "Browsing"
        case .away: return "Away"
        }
    }

    /// "Coding 40 minutes", "Away 1 hour". A watched stretch the session paused for is named with its
    /// purpose, so it says it was not counted; away is never counted unless answered as work.
    static func phaseLine(_ phase: SessionPhase) -> String {
        let line = "\(activityName(phase.activity)) \(Tokens.spent(phase.end.timeIntervalSince(phase.start)))"
        return phase.counted || phase.activity == .away ? line : line + ", not counted"
    }

    /// The strip's VoiceOver value: every phase in order, then the depth and where the phases came from.
    static func summary(_ shape: SessionActivityShape) -> String {
        var text = shape.phases.map(phaseLine).joined(separator: ", ") + "."
        if let word = depthWord(shape.depth) { text += " \(word)." }
        if let note = fidelityNote(shape) { text += " \(note)." }
        return text
    }

    static func fidelityNote(_ shape: SessionActivityShape) -> String? {
        shape.fidelity == .appsOnly ? "From app use only" : nil
    }
}
