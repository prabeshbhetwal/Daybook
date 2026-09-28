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

    /// Whether the strip shows today's goal. Day view of today has the goal
    /// card in the rail, unless a sheet covers it or History, which has no
    /// goal card, is in its place.
    static func showsGoal(scope: StoryScope, isToday: Bool,
                          workspace: MainReadingWorkspace, sheet: StorySheetKind?) -> Bool {
        !(scope == .day && isToday && workspace == .story && sheet == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                FocusHero(store: store,
                          intentFocused: $intentFocused,
                          compact: true,
                          wide: true,
                          showsGoal: Self.showsGoal(scope: navigation.storyScope,
                                                    isToday: store.isToday,
                                                    workspace: navigation.workspace,
                                                    sheet: navigation.sheet))
                    .coachAnchor(.activityField)
                stripChrome
            }
            if let choice = store.pendingActivityChoice {
                ActivityQuietChoiceView(store: store, choice: choice)
            }
            if let error = store.activityAutomationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.metadata).foregroundStyle(Tokens.Colour.danger)
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
            // The same round button the chrome uses for its icon actions, one
            // row up. A pin is a toggle: on, the circle takes the accent. These
            // were bordered controls with a 6%-alpha tint, which an inactive
            // window dimmed to nothing.
            IconButton(systemImage: settings.sessionControlsPinned ? "pin.fill" : "pin",
                       help: "Keep session controls visible in this window",
                       prominent: settings.sessionControlsPinned,
                       label: "Pin session controls",
                       isOn: settings.sessionControlsPinned) {
                settings.sessionControlsPinned.toggle()
            }
            IconButton(systemImage: "xmark", help: "Close session controls", action: close)
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
                        .buttonStyle(StoryActionStyle())
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
