import SwiftUI

/// The selected Settings group. Every interactive row binds directly to the
/// coordinator-owned model; read-only rows come from its live diagnostics.
/// A row's title and control say what it does; a detail line is added only
/// when they leave something unsaid.
struct SettingsGroups: View {
    @ObservedObject var model: SettingsModel
    @State var copiedAgentSetup = false
    let section: SettingsSection
    @Environment(\.focusInterfaceDensity) private var density
    /// What the last Try reached, shown under its button until the next one.
    @State private var hapticTryResult: MouseLinkStatus?

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
            SurfacePanel(title: "Confirmations", layout: layout) {
                toggleRow("Ask before changing how a break counts", isOn: asks(.changeBreak))
                rowDivider
                toggleRow("Ask before removing a session", isOn: asks(.removeSession))
                explanation("Undo works either way. Deletes Undo can't reverse always ask.")
            }
            if model.canReplayWelcome {
                SurfacePanel(title: "Getting started", layout: layout) {
                    // A tour ended by a quit or a crash, not by Skip or its
                    // last card, can be picked up where it was left.
                    explanation(model.interruptedWelcomeChapter.map {
                        "Stopped at chapter \($0.number), \($0.title)."
                    } ?? "Twelve short chapters, about seven minutes.")
                    HStack(spacing: Tokens.Space.s) {
                        if let chapter = model.interruptedWelcomeChapter {
                            Button("Continue the tour") { model.resumeWelcome() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(Tokens.Zoom.controlSize(.large))
                                .accessibilityHint("Closes Settings and picks the introduction up at chapter "
                                                   + "\(chapter.number), \(chapter.title)")
                        }
                        Button(model.interruptedWelcomeChapter == nil ? "Show the tour again"
                                                                      : "Start from the beginning") {
                            model.replayWelcome()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(Tokens.Zoom.controlSize(.large))
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
        model.loginItemError.map { "Could not change the login item: \($0)" }
    }

    /// Said only where the menu leaves it unclear: the app's menus come and
    /// go with the Dock icon.
    private var dockIconDetail: String? {
        guard model.showsMenuBarIcon else { return "Always shown while the menu bar icon is hidden." }
        return model.dockIconMode == .never ? "No Dock icon or app menus." : nil
    }

    private var focus: some View {
        SurfacePanel(title: "Goal", layout: layout) {
            preferenceRow("Daily goal", detail: "Counts focus only while you're at the Mac.") {
                RowMenu("Daily goal", selection: $model.dailyGoal,
                        options: FocusConstants.dailyGoalOptions) { Tokens.duration($0) }
            }
            rowDivider
            preferenceRow("Usual pace compares with") {
                RowMenu("Usual pace compares with", selection: $model.paceWindowDays,
                        options: FocusConstants.paceWindowOptions) { "last \($0) days" }
            }
            rowDivider
            preferenceRow("Suggest activities from") {
                RowMenu("Suggest activities from", selection: $model.suggestionWindowDays,
                        options: FocusConstants.suggestionWindowOptions) { "last \($0) days" }
            }
            rowDivider
            preferenceRow("Streak counts a day after") {
                ThresholdControl(label: "Streak counts a day after", selection: $model.streakMinimum,
                                 options: FocusConstants.streakMinimumOptions)
            }
            rowDivider
            preferenceRow("New sessions start as") {
                RowMenu("New sessions start as", selection: $model.defaultWorkType,
                        items: WorkType.startable.map { .option($0, $0.displayName, systemImage: $0.symbolName) })
            }
            rowDivider
            preferenceRow("Keep sessions longer than", detail: "Shorter ones are never saved.") {
                RowMenu("Keep sessions longer than", selection: $model.minimumRecordedSession,
                        options: FocusConstants.minimumRecordedSessionOptions) { Tokens.preciseDuration($0) }
            }
            rowDivider
            preferenceRow("Offer to continue for", detail: "Counted from when a session ends.") {
                ThresholdControl(label: "Offer to continue for", selection: $model.continueWindow,
                                 options: FocusConstants.continueWindowOptions)
            }
        }
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
                preferenceRow("End session after") {
                    ThresholdControl(label: "End session after", selection: $model.longAwayCap,
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
        SurfacePanel(title: "Categories", layout: layout) {
            CategoriesView(model: model)
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

    private var automatic: some View {
        let rulesOn = model.activityRuleAutomationEnabled
        return VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Automatic sessions", layout: layout) {
                // While rules are on the guess is not in effect, so the switch
                // reads off. Only its reading changes: the stored choice is
                // kept for when rules are turned off again.
                toggleRow("Guess sessions from the app in front",
                          detail: rulesOn ? "Off while activity rules are on."
                                          : "Work apps start a session; break apps pause it.",
                          isOn: Binding(get: { model.autoSessionsEnabled && !rulesOn },
                                        set: { model.autoSessionsEnabled = $0 }))
                    .disabled(rulesOn)
                rowDivider
                preferenceRow("End a paused automatic session after") {
                    ThresholdControl(label: "End a paused automatic session after",
                                     selection: $model.autoSessionPauseLimit,
                                     options: FocusConstants.autoSessionPauseLimitOptions, allowsNever: true)
                }
                rowDivider
                toggleRow("Celebrate milestones", detail: "Goal, streak and pace.", isOn: $model.rewardsEnabled)
                rowDivider
                toggleRow("Haptic feedback", detail: "Trackpad or MX Master 4.", isOn: $model.hapticsEnabled)
                rowDivider
                preferenceRow("Try haptic feedback", detail: hapticTryResult?.tryMessage) {
                    Button("Try") {
                        Task { @MainActor in hapticTryResult = await model.tryHaptics() }
                    }
                    .disabled(!model.hapticsEnabled)
                }
            }
        }
    }

    private var tracking: some View {
        SurfacePanel(title: "Tracking and apps", layout: layout) {
            preferenceRow("Apps shown in a card") {
                RowMenu("Apps shown in a card", selection: $model.railAppCount,
                        options: FocusConstants.railAppOptions) { "\($0)" }
            }
            rowDivider
            preferenceRow("Recent app visits") {
                RowMenu("Recent app visits", selection: $model.menuSessionCount,
                        options: [3, 5, 7, 10]) { "\($0)" }
            }
            rowDivider
            toggleRow("Record app usage", detail: "Off, Story shows sessions only.", isOn: $model.isTrackingEnabled)
        }
    }

    private var appearance: some View {
        SurfacePanel(title: "Interface", layout: layout) {
            preferenceRow("Appearance") {
                RowMenu("Appearance", selection: $model.appearancePreference,
                        options: [.system, .light, .dark]) { preference in
                    switch preference {
                    case .system: return "System"
                    case .light: return "Light"
                    case .dark: return "Dark"
                    }
                }
            }
            rowDivider
            preferenceRow("Interface density") {
                RowMenu("Interface density", selection: $model.interfaceDensity,
                        options: [.comfortable, .compact]) { $0 == .compact ? "Compact" : "Comfortable" }
            }
            rowDivider
            preferenceRow("Zoom") { ZoomControl(model: model) }
            rowDivider
            toggleRow("Show Story timestamps", isOn: $model.showsTimelineLabels)
            rowDivider
            toggleRow("Expand entry details by default", isOn: $model.expandsEntryDetails)
            rowDivider
            preferenceRow("Fold quiet stretches after",
                          detail: "Gaps and loose app use fold into one line.") {
                RowMenu("Fold quiet stretches after", selection: $model.quietFold,
                        options: FocusConstants.quietFoldOptions) { $0 == 0 ? "Never" : "\($0) rows" }
            }
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
