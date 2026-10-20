import Foundation

/// The three reminders. Each stands for a kind of fatigue continuous computer
/// work produces, with its own onset and its own recovery cost: a thirty-second
/// look-away genuinely fixes eye strain and genuinely does nothing for a brain
/// ninety minutes into a task.
///
/// The cases are slots in a `BreakPlan`: `.micro` is Eyes, `.cognitive` the
/// main rhythm and `.ultradian` the long-stretch guard. The numbers on the
/// tier itself are Steady's defaults, and the fallbacks a prompt uses when it
/// carries none of its own; the reminder engine reads a plan's numbers
/// instead.
///
/// Ordered by depth, and evaluated deepest-first, so a due guard is never
/// reported as a stretch break. The raw values are stored with the reminder
/// clock and the last notice.
enum BreakTier: Int, CaseIterable, Comparable, Codable {

    /// Eyes: visual and musculoskeletal strain, the 20-20-20 rule.
    case micro = 0
    /// The main rhythm: cognitive load; attention degrades and needs a reset.
    case cognitive = 1
    /// The guard: a long stretch with no real break, where the body starts
    /// drawing on reserves and analytical efficiency falls away.
    case ultradian = 2

    static func < (lhs: BreakTier, rhs: BreakTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Continuous work that brings this tier due under Steady and the standard
    /// guard.
    var workThreshold: TimeInterval {
        switch self {
        case .micro: return 20 * 60
        case .cognitive: return 50 * 60
        case .ultradian: return 90 * 60
        }
    }

    /// Rest this tier prescribes under Steady and the standard guard.
    var breakLength: TimeInterval {
        switch self {
        case .micro: return 30
        case .cognitive: return 5 * 60
        case .ultradian: return 15 * 60
        }
    }

    var title: String {
        switch self {
        case .micro: return "Look away for 30 seconds"
        case .cognitive: return "Take 5 minutes"
        case .ultradian: return "Step away for 15 minutes"
        }
    }

    var symbolName: String {
        switch self {
        case .micro: return "eye"
        case .cognitive: return "cup.and.saucer.fill"
        case .ultradian: return "figure.walk"
        }
    }

    /// Why this break exists, in the plainest words that are still true. Shown
    /// to the user, so no jargon survives here that a non-specialist would have
    /// to look up.
    var reason: String {
        switch self {
        case .micro:
            return "Focus on something far away and let your shoulders drop. "
                + "This is for your eyes and your posture, not your "
                + "concentration — it is over before you lose your thread."
        case .cognitive:
            return "Attention wears down after about this long and a short rest "
                + "restores it. Stand up if you can. Scrolling your phone uses "
                + "the same part of the brain you are trying to rest."
        case .ultradian:
            return "You are past the point where pushing on costs more than it "
                + "returns. A real break away from the screen is what resets "
                + "this — email and messages do not count as one."
        }
    }

    /// Short label for the menu bar countdown.
    var shortLabel: String {
        switch self {
        case .micro: return "Look away"
        case .cognitive: return "Break"
        case .ultradian: return "Long break"
        }
    }
}
