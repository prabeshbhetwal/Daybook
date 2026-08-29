import SwiftUI

/// Compatibility name for the menu-bar caller. Selection and the hard
/// three-row cap live in `FocusContinuationSource`, shared with desktop Focus.
struct ContinueTodaySection: View {
    @ObservedObject var store: SessionStore
    var limit: Int

    var body: some View {
        FocusContinuations(store: store, limit: limit, compact: true)
    }
}
