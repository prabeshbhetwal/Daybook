import SwiftUI

extension SessionStore {

    /// Ribbon selection is the reverse of session selection: clear the session
    /// first, then preserve the established timeline toggle/hour-detail logic.
    func selectTodayTimeline(at fraction: Double) {
        clearSession()
        selectTimeline(at: fraction)
    }

}

