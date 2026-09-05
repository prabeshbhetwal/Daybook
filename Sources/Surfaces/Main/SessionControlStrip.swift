import SwiftUI

enum SessionControlsVisibility {
    static func isVisible(expanded: Bool, pinned: Bool) -> Bool {
        expanded || pinned
    }
}

/// The window's operational strip. It reuses the same FocusHero action
/// boundary as the menu bar and never owns or mutates a second timer.
///
/// It is a toolbar, not a panel: one row, with Pin and Close at the end of the
/// controls they govern rather than in a header of their own. The header used
/// to sit above the content and push its two controls to the window's far
/// edge — 468pt of nothing at the minimum width, 1,088pt at 1,600 — while the
/// strip itself stood 225pt tall in a 680pt window.
struct SessionControlStrip: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    @FocusState private var intentFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                FocusHero(store: store,
                          intentFocused: $intentFocused,
                          compact: true,
                          wide: true)
                stripChrome
            }
            if let choice = store.pendingActivityChoice {
                ActivityQuietChoiceView(store: store, choice: choice)
            }
            if let error = store.activityAutomationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.metadata).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.rail)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session controls")
    }

    private var stripChrome: some View {
        HStack(spacing: Tokens.Space.s) {
            // A checkbox draws a 16pt target and reads as a form field. In a
            // toolbar row a pin is a toggle button: the same state, a 28pt
            // target, and a pressed look that says "held open" without a word.
            Toggle(isOn: $settings.sessionControlsPinned) {
                Label("Pin", systemImage: settings.sessionControlsPinned ? "pin.fill" : "pin")
                    .labelStyle(.iconOnly)
                    .symbolSwap()
                    .symbolNod(on: settings.sessionControlsPinned)
                    .font(Tokens.Typography.metadata.weight(.semibold))
            }
            .toggleStyle(.button)
            .controlSize(.large)
            .tint(Color.primary.opacity(0.06))
            .foregroundStyle(settings.sessionControlsPinned ? AnyShapeStyle(StoryStyle.action)
                                                            : AnyShapeStyle(.secondary))
            .help("Keep session controls visible in this window")
            .accessibilityLabel("Pin session controls")
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .frame(height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.primary.opacity(0.06))
            .foregroundStyle(.secondary)
            .help("Close session controls")
            .accessibilityLabel("Close session controls")
        }
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .fixedSize()
    }

    /// Closing releases the pin. The button used to be disabled while pinned,
    /// which left the one control that says "close" visibly present and dead,
    /// and turned one intention into two acts in a fixed order.
    private func close() {
        settings.sessionControlsPinned = false
        navigation.dismissSessionControls()
    }
}

struct ActivityQuietChoiceView: View {
    @ObservedObject var store: SessionStore
    let choice: ActivityQuietChoice

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(choice.candidates.map(\.name).joined(separator: " or ") + "?")
                .font(Tokens.Typography.rowTitle)
            Text("Choose one activity for the recorded external app interval. Time in FocusContinuity is excluded.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach(choice.candidates, id: \.ruleID) { candidate in
                    Button(candidate.name) { store.chooseActivity(ruleID: candidate.ruleID) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(Tokens.Space.m)
        .background(StoryStyle.well, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose activity for recorded app use")
        .storyRenderEvidence(.activityQuietChoice)
    }
}
