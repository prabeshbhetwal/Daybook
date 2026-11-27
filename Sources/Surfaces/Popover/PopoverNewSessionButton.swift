import SwiftUI

/// The plus in the Switch to header. It opens the same chooser the idle hero
/// shows (activity, category, Start Focus) and starts through the store's own
/// `start()`, so a new session from here behaves exactly like one from the hero.
struct PopoverNewSessionButton: View {
    @ObservedObject var store: SessionStore
    @State private var isPresented = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "plus")
                .font(Tokens.Typography.label)
                .frame(minWidth: AccessibilityMetrics.minimumTargetSize,
                       minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true))
        .foregroundStyle(StoryStyle.supportingInk)
        .help("Starts a new session")
        .accessibilityLabel("New session")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("New session")
                    .font(Tokens.Typography.rowTitle)
                    .accessibilityAddTraits(.isHeader)
                ActivityChooser(store: store, intentFocused: $nameFocused, compact: true) { start() }
                HStack(spacing: Tokens.Space.s) {
                    WorkTypePicker(selection: $store.workType)
                    StartButton(title: "Start Focus", fills: true,
                                height: Tokens.Control.compactHeight) { start() }
                }
            }
            .padding(Tokens.Space.l)
            .frame(width: 300.zoomed)
            .onAppear { nameFocused = true }
        }
    }

    private func start() {
        store.start()
        isPresented = false
    }
}
