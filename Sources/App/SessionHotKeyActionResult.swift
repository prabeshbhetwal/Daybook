import Foundation

enum SessionHotKeyActionResult: Equatable {
    case started
    case stopped
    case stoppedPendingFinalisation
    case showAwayDecision
    case saveFailed

    /// The HUD's title for a press that did not fully save, nil for one that
    /// did. The shortcut says it itself: the window may well be closed.
    var failureTitle: String? {
        switch self {
        case .saveFailed: return "Couldn't save the session"
        case .stoppedPendingFinalisation: return "Session stopped, not fully saved"
        case .started, .stopped, .showAwayDecision: return nil
        }
    }
}
