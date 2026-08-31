import SwiftUI

/// The compact menu-bar wrapper around the same Focus hero used by the desktop
/// canvas. Only spacing and available measure differ.
struct HeroCard: View {
    @ObservedObject var store: SessionStore
    var intentFocused: FocusState<Bool>.Binding
    var dense = false

    var body: some View {
        FocusHero(store: store,
                  intentFocused: intentFocused,
                  compact: true,
                  wide: false)
            .card(padding: dense ? Tokens.Space.m : Tokens.Space.l)
    }
}
