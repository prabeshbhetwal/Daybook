import SwiftUI

/// The selected Settings group. Every interactive row binds directly to the
/// coordinator-owned model; read-only rows come from its live diagnostics.
/// A row's title and control say what it does; a detail line is added only
/// when they leave something unsaid.
struct SettingsGroups: View {
    @ObservedObject var model: SettingsModel
    @State var copiedAgentSetup = false
    /// The app chooser of the Daily goals panel.
    @State var choosingGoalApp = false
    let section: SettingsSection
    @Environment(\.focusInterfaceDensity) private var density
    /// What the last Try reached, shown under its button until the next one.
    @State var hapticTryResult: MouseLinkStatus?

    var layout: InterfaceDensity.Layout { density.layout }

    @ViewBuilder var body: some View {
        switch section {
        case .general: general
        case .focus: focus
        case .categories: categories
        case .away: away
        case .breaks: breaks
        case .automatic: automatic
        case .activities: activities
        case .tracking: tracking
        case .appearance: appearance
        case .data: data
        case .updates: updates
        case .advanced: advanced
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Menu bar, Dock and login", layout: layout) {
                toggleRow("Open at login", isOn: $model.opensAtLogin)
                if let message = loginItemMessage {
                    explanation(message)
                }
                if model.loginItemNeedsApproval {
                    systemSettingsRow(Self.loginApproval, button: "Open Login Items") {
                        model.openLoginItemsSettings()
                    }
                }
                rowDivider
                toggleRow("Show the icon in the menu bar", isOn: $model.showsMenuBarIcon)
                rowDivider
                toggleRow("Show the session time in the menu bar", isOn: $model.menuBarShowsTime)
                    .disabled(!model.showsMenuBarIcon)
                rowDivider
                preferenceRow("Dock icon", detail: dockIconDetail) {
                    RowMenu("Dock icon", selection: $model.dockIconMode,
                            options: [.whileWindowOpen, .always, .never]) { mode in
                        switch mode {
                        case .whileWindowOpen: return "While the window is open"
                        case .always: return "Always"
                        case .never: return "Never"
                        }
                    }
                    .disabled(!model.showsMenuBarIcon)
                }
            }
            // A switch that flips back by itself is otherwise silent.
            .announcesChanges(to: loginItemMessage)
            .announcesChanges(to: model.loginItemNeedsApproval ? Self.loginApproval : nil)
            askPanel
            keyboard
            hapticsPanel
            SurfacePanel(title: "Confirmations", layout: layout) {
                toggleRow("Ask before changing how a break counts", isOn: asks(.changeBreak))
                rowDivider
                toggleRow("Ask before removing a session", isOn: asks(.removeSession))
                explanation("Undo works either way. Anything Undo can't reverse always asks first.")
            }
            if model.canReplayWelcome {
                SurfacePanel(title: "Getting started", layout: layout) {
                    // A tour ended by a quit or a crash, not by Skip or its
                    // last card, can be picked up where it was left.
                    explanation(model.interruptedWelcomeChapter.map {
                        "Stopped at chapter \($0.number), \($0.title)."
                    } ?? "Seven short chapters, a few minutes.")
                    HStack(spacing: Tokens.Space.s) {
                        if let chapter = model.interruptedWelcomeChapter {
                            Button("Continue the Tour") { model.resumeWelcome() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityHint("Closes Settings and picks the introduction up at chapter "
                                                   + "\(chapter.number), \(chapter.title)")
                        }
                        Button(model.interruptedWelcomeChapter == nil ? "Show the Tour Again"
                                                                      : "Start From the Beginning") {
                            model.replayWelcome()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Closes Settings and runs the introduction over the story")
                    }
                }
            }
        }
        .onAppear(perform: model.refreshSystemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemStatus()
        }
    }

    private static let loginApproval = "Approve Daybook in System Settings › General › Login Items."

    private var loginItemMessage: String? {
        model.loginItemError.map { "The login item couldn't be changed. \($0.endingInFullStop) Try again, or use System Settings › General › Login Items." }
    }

    /// Said only where the menu leaves it unclear: the app's menus come and
    /// go with the Dock icon.
    private var dockIconDetail: String? {
        guard model.showsMenuBarIcon else { return "Always shown while the menu bar icon is hidden." }
        return model.dockIconMode == .never ? "No Dock icon or app menus." : nil
    }

    private var away: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Stepping away", layout: layout) {
                preferenceRow("Pause after no input for",
                              detail: "Leave room for reading and thinking.") {
                    ThresholdControl(label: "Pause after no input for", selection: $model.idlePauseThreshold,
                                     options: FocusConstants.idlePauseOptions, allowsNever: true)
                }
                rowDivider
                preferenceRow("Ask me after", detail: "Shorter absences are left out without asking.") {
                    ThresholdControl(label: "Ask me after", selection: $model.breakThreshold,
                                     options: FocusConstants.thresholdOptions, allowsNever: true)
                }
                rowDivider
                preferenceRow("Stop session after") {
                    ThresholdControl(label: "Stop session after", selection: $model.longAwayCap,
                                     options: FocusConstants.longAwayCapOptions, allowsNever: true)
                }
                rowDivider
                preferenceRow("Full-screen prompt after",
                              detail: "Until then the question waits in the menu bar.") {
                    ThresholdControl(label: "Full-screen prompt after", selection: $model.fullPromptAfter,
                                     options: FocusConstants.fullPromptAfterOptions, allowsNever: true,
                                     neverValue: 0)
                }
                explanation(awayExplanation)
            }

            agentsPanel
        }
        .onAppear(perform: model.refreshSystemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemStatus()
        }
    }

    /// What the rows above leave unsaid: a pause also ends at the cap, Away
    /// is never questioned, and watching is not an absence.
    private var awayExplanation: String {
        let cap = FocusConstants.isNever(model.longAwayCap)
            ? "" : "A pause past \(Tokens.duration(model.longAwayCap)) also ends the session. "
        return cap + "Pressing Away never asks. Video, calls and presentations count as watching."
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Categories", layout: layout) {
                CategoriesView(model: model)
            }
            SurfacePanel(title: "Automatic categories", layout: layout) { aiCategoryRows }
        }
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Activity rules", layout: layout) {
                toggleRow("Use my activity rules",
                          detail: "Rules start a session only when none is running.",
                          isOn: $model.activityRuleAutomationEnabled)
            }
            ActivityRulesView(model: model)
        }
    }

    /// On while the app still asks this question; off is "Don't ask again".
    private func asks(_ confirmation: Confirmation) -> Binding<Bool> {
        Binding(get: { !model.skippedConfirmations.contains(confirmation) },
                set: { on in
                    var skipped = model.skippedConfirmations
                    if on { skipped.remove(confirmation) } else { skipped.insert(confirmation) }
                    model.skippedConfirmations = skipped
                })
    }
}
