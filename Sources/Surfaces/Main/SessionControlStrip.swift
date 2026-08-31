import SwiftUI

enum SessionControlsVisibility {
    static func isVisible(expanded: Bool, pinned: Bool) -> Bool {
        expanded || pinned
    }
}

/// The existing main window's operational strip. It reuses the same FocusHero
/// action boundary as the menu bar and never owns or mutates a second timer.
struct SessionControlStrip: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    @FocusState private var intentFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.s) {
                Label("Session controls", systemImage: "timer")
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Tokens.Space.m)
                Toggle("Pin controls", isOn: $settings.sessionControlsPinned)
                    .toggleStyle(.checkbox)
                    .font(Tokens.Typography.metadata)
                    .help("Keep session controls visible in this window")
                Button(action: navigation.dismissSessionControls) {
                    Image(systemName: "xmark")
                        .frame(width: AccessibilityMetrics.minimumTargetSize,
                               height: AccessibilityMetrics.minimumTargetSize)
                }
                .buttonStyle(.plain)
                .disabled(settings.sessionControlsPinned)
                .help(settings.sessionControlsPinned ? "Unpin controls before closing" : "Close session controls")
                .accessibilityLabel("Close session controls")
            }
            FocusHero(store: store,
                      intentFocused: $intentFocused,
                      compact: true,
                      wide: false)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.rail)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session controls")
    }
}
