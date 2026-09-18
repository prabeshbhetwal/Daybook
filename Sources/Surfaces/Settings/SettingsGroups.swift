import SwiftUI

/// Scalar diagnostics align a short value with their title; a narrative status
/// needs the row's full reading width instead of a compressed trailing column.
enum SettingsReadOnlyRowLayout: Equatable {
    case trailingValue
    case statusBlock

    var usesTrailingValue: Bool { self == .trailingValue }
    var usesFullWidthValue: Bool { self == .statusBlock }
}

/// The selected Settings group. Every interactive row binds directly to the
/// coordinator-owned model; read-only rows come from its live diagnostics.
struct SettingsGroups: View {
    @ObservedObject var model: SettingsModel
    let section: SettingsSection
    @Environment(\.focusInterfaceDensity) private var density

    private var layout: InterfaceDensity.Layout { density.layout }

    @ViewBuilder var body: some View {
        switch section {
        case .general: general
        case .focus: focus
        case .categories: categories
        case .away: away
        case .automatic: automatic
        case .activities: activities
        case .tracking: tracking
        case .appearance: appearance
        case .data: data
        case .advanced: advanced
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Main window", layout: layout) {
                preferenceRow("Opens on",
                              detail: "Which story the window tells when it opens.") {
                    Picker("Opens on", selection: $model.defaultStoryScope) {
                        ForEach(StoryScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .accessibilityLabel("Opens on")
                }
            }
            SurfacePanel(title: "Menu bar and login", layout: layout) {
                toggleRow("Open at login",
                          detail: "Starts FocusContinuity in the menu bar when you sign in, so the "
                            + "record never has a gap at the start of the day.",
                          isOn: $model.opensAtLogin)
                if let error = model.loginItemError {
                    explanation("Could not change the login item: \(error)")
                }
                rowDivider
                toggleRow("Show the session time in the menu bar",
                          detail: "Off, the menu bar keeps only the goal ring while a session runs.",
                          isOn: $model.menuBarShowsTime)
            }
            if model.canReplayWelcome {
                SurfacePanel(title: "Getting started", layout: layout) {
                    explanation("The welcome walks you through starting a session, naming it "
                                + "and seeing what your Mac recorded on its own. It takes about "
                                + "a minute.")
                    Button("Show the welcome again") { model.replayWelcome() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityHint("Closes Settings and runs the introduction over the story")
                }
            }
        }
    }

    private var focus: some View {
        SurfacePanel(title: "Goal", layout: layout) {
            preferenceRow("Daily goal",
                          detail: "Counts only declared focus while you were actually using the Mac.") {
                Picker("Daily goal", selection: $model.dailyGoal) {
                    ForEach(FocusConstants.dailyGoalOptions, id: \.self) { seconds in
                        Text(Tokens.duration(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Daily goal")
            }
            explanation("Your usual pace compares today with the same hour on your last "
                        + "\(model.paceWindowDays) working days.")
            rowDivider
            preferenceRow("Usual pace compares with",
                          detail: "How many of your working days the pace line is measured against.") {
                Picker("Usual pace compares with", selection: $model.paceWindowDays) {
                    ForEach(FocusConstants.paceWindowOptions, id: \.self) { days in
                        Text("last \(days) days").tag(days)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("Usual pace compares with")
            }
            rowDivider
            preferenceRow("Suggest activities from",
                          detail: "How far back the activity menu looks for names you have used.") {
                Picker("Suggest activities from", selection: $model.suggestionWindowDays) {
                    ForEach(FocusConstants.suggestionWindowOptions, id: \.self) { days in
                        Text("last \(days) days").tag(days)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("Suggest activities from")
            }
            rowDivider
            preferenceRow("Streak counts a day after",
                          detail: "A day joins your streak once its focus reaches this.") {
                ThresholdControl(label: "Streak counts a day after", selection: $model.streakMinimum,
                                 options: FocusConstants.streakMinimumOptions)
            }
            rowDivider
            preferenceRow("New sessions start as",
                          detail: "The category a session is filed under until you choose another.") {
                Picker("New sessions start as", selection: $model.defaultWorkType) {
                    ForEach(WorkType.startable) { type in
                        Label(type.displayName, systemImage: type.symbolName)
                            .labelStyle(.titleAndIcon).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("New sessions start as")
            }
            rowDivider
            preferenceRow("Keep sessions longer than",
                          detail: "A stretch shorter than this is a misclick, not history, and is never written.") {
                Picker("Keep sessions longer than", selection: $model.minimumRecordedSession) {
                    ForEach(FocusConstants.minimumRecordedSessionOptions, id: \.self) { seconds in
                        Text(Tokens.preciseDuration(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .accessibilityLabel("Keep sessions longer than")
            }
            rowDivider
            preferenceRow("Offer to continue for",
                          detail: "How long after a session ends it is still offered as something to pick up.") {
                ThresholdControl(label: "Offer to continue for", selection: $model.continueWindow,
                                 options: FocusConstants.continueWindowOptions)
            }
        }
    }

    private var away: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Stepping away", layout: layout) {
                preferenceRow("Pause after no input for",
                              detail: "Quiet at the keyboard for this long pauses the session, timed from "
                                + "your last key or click. Reading and thinking are work; pick a wait that "
                                + "does not punish them.") {
                    ThresholdControl(label: "Pause after no input for", selection: $model.idlePauseThreshold,
                                     options: FocusConstants.idlePauseOptions, allowsNever: true)
                }
                rowDivider
                preferenceRow("Ask me after",
                              detail: "Shorter absences are left out of the session without a question.") {
                    ThresholdControl(label: "Ask me after", selection: $model.breakThreshold,
                                     options: FocusConstants.thresholdOptions, allowsNever: true)
                }
                rowDivider
                preferenceRow("End session after",
                              detail: "Longer than this, the session ends where you left rather than waiting.") {
                    ThresholdControl(label: "End session after", selection: $model.longAwayCap,
                                     options: FocusConstants.longAwayCapOptions, allowsNever: true)
                }
                rowDivider
                preferenceRow("Full-screen prompt after",
                              detail: "How long the away question stays in the menu bar before it fills the screen.") {
                    ThresholdControl(label: "Full-screen prompt after", selection: $model.fullPromptAfter,
                                     options: FocusConstants.fullPromptAfterOptions, allowsNever: true,
                                     neverValue: 0)
                }
                explanation(awayExplanation)
            }

            SurfacePanel(title: "Breaks", layout: layout) {
                toggleRow("Remind me to take breaks",
                          detail: "A notice after a long stretch of continuous use, timed from your typing "
                            + "and clicking rather than from sessions.",
                          isOn: $model.remindersEnabled)
                // Each tier is its own switch: someone who finds the
                // twenty-minute nudge too frequent keeps the longer two.
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    ForEach(BreakTier.allCases, id: \.rawValue) { tier in
                        Toggle(isOn: Binding(
                            get: { model.enabledBreakTiers.contains(tier) },
                            set: { on in
                                var tiers = model.enabledBreakTiers
                                if on { tiers.insert(tier) } else { tiers.remove(tier) }
                                model.enabledBreakTiers = tiers
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("After \(Int(tier.workThreshold / 60)) minutes, "
                                     + "\(BreakPrompt.phrase(tier.breakLength)) off")
                                    .font(Tokens.Typography.control)
                                Text(tier.reason)
                                    .font(Tokens.Typography.metadata)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!model.remindersEnabled)
                    }
                    Text("Timed from continuous use, not from sessions. A short break resets "
                         + "the short timer only; the longer ones keep running.")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 26)
            }
        }
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
                          detail: "Start and switch sessions from the rules below, going by which apps "
                            + "you are in. Editing a rule never starts a session by itself.",
                          isOn: $model.activityRuleAutomationEnabled)
            }
            ActivityRulesView(model: model)
        }
    }

    private var automatic: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Automatic sessions", layout: layout) {
                toggleRow("Use legacy automatic sessions",
                          detail: "Without rules, guess from the app in front: a work app starts a "
                            + "session, a break app pauses it. Turned off while rules are on. "
                            + "The category is the one you chose the last few times you started "
                            + "from that app.",
                          isOn: $model.autoSessionsEnabled)
                    .disabled(model.activityRuleAutomationEnabled)
                rowDivider
                preferenceRow("Auto-session gap",
                              detail: "How long an automatic session can sit paused before it ends "
                                + "instead of picking up where it left off.") {
                    ThresholdControl(label: "Auto-session gap", selection: $model.breakLength,
                                     options: FocusConstants.breakLengthOptions, allowsNever: true)
                }
                rowDivider
                toggleRow("Celebrate milestones",
                          detail: "A short notice in the corner when you reach the daily goal, keep a "
                            + "streak going or beat your usual pace.",
                          isOn: $model.rewardsEnabled)
            }
        }
    }

    private var tracking: some View {
        SurfacePanel(title: "Tracking and apps", layout: layout) {
            preferenceRow("Apps shown in a card",
                          detail: "How many apps the rail and the History previews list before "
                            + "\u{201c}See all\u{201d}.") {
                Picker("Apps shown in a card", selection: $model.railAppCount) {
                    ForEach(FocusConstants.railAppOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("Apps shown in a card")
            }
            rowDivider
            preferenceRow("Recent app visits",
                          detail: "Limits the newest recorded app visits shown after you open "
                            + "an app in Story.") {
                Picker("Recent app visits", selection: $model.menuSessionCount) {
                    ForEach([3, 5, 7, 10], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("Recent app visits")
            }
            rowDivider
            toggleRow("Record app usage",
                      detail: "Which app was in front and for how long. Off, the story shows your "
                        + "sessions alone.",
                      isOn: $model.isTrackingEnabled)
            explanation(SettingsPrivacyDisclosure.current.storageDetail)
        }
    }

    private var appearance: some View {
        SurfacePanel(title: "Interface", layout: layout) {
            preferenceRow("Appearance",
                          detail: "System follows macOS, including its schedule.") {
                Picker("Appearance", selection: $model.appearancePreference) {
                    Text("System").tag(AppearancePreference.system)
                    Text("Light").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Appearance")
            }
            rowDivider
            preferenceRow("Interface density",
                          detail: "Compact fits more rows into the same space.") {
                Picker("Interface density", selection: $model.interfaceDensity) {
                    Text("Comfortable").tag(InterfaceDensity.comfortable)
                    Text("Compact").tag(InterfaceDensity.compact)
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Interface density")
            }
            rowDivider
            toggleRow("Show Story timestamps",
                      detail: "Times down the left edge of the day's timeline.",
                      isOn: $model.showsTimelineLabels)
            rowDivider
            toggleRow("Expand entry details by default",
                      detail: "Open each session's apps and notes without a click.",
                      isOn: $model.expandsEntryDetails)
            explanation("Reduce Motion always follows macOS and is never overridden here.")
            rowDivider
            preferenceRow("Fold quiet stretches after",
                          detail: "Runs of gaps and loose app use fold into one line once they reach this many rows.") {
                Picker("Fold quiet stretches after", selection: $model.quietFold) {
                    ForEach(FocusConstants.quietFoldOptions, id: \.self) { count in
                        Text(count == 0 ? "Never" : "\(count) rows").tag(count)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .accessibilityLabel("Fold quiet stretches after")
            }
        }
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Privacy", layout: layout) {
                readOnlyRow("Storage", value: "Local only",
                            detail: SettingsPrivacyDisclosure.current.storageDetail)
                rowDivider
                readOnlyRow("Accurate app usage from",
                            value: model.diagnostics.usageAccuracyEpoch.map(
                                SettingsDiagnostics.accuracyEpochLabel)
                                ?? "Not established",
                            detail: "App-use patterns before this epoch remain visibly qualified.")
                rowDivider
                readOnlyRow("Legacy backup location",
                            value: model.diagnostics.legacyBackupURL?.path ?? "No legacy backup created",
                            detail: "A backup appears only when older app-usage bytes are migrated.",
                            valueLayout: .statusBlock)
            }

            SurfacePanel(title: "Data folder", layout: layout) {
                readOnlyRow("Location", value: model.dataDirectoryURL.path,
                            valueLayout: .statusBlock)
                Button("Reveal data folder") { model.revealDataFolder() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint("Opens the local FocusContinuity data folder in Finder")
            }
        }
    }

    private var advanced: some View {
        SurfacePanel(title: "Diagnostics", layout: layout) {
            readOnlyRow("Version", value: model.diagnostics.version)
            rowDivider
            readOnlyRow("Build", value: model.diagnostics.build)
            rowDivider
            readOnlyRow("Recovery", value: model.diagnostics.recoverySummary,
                        detail: "Recovery preserves source evidence before the app resumes writing.",
                        valueLayout: .statusBlock)
        }
    }

    private func preferenceRow<Accessory: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Tokens.Typography.rowTitle)
                if let detail {
                    Text(detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Tokens.Space.m)
            accessory()
        }
        .frame(minHeight: layout.rowHeight)
    }

    @ViewBuilder
    private func readOnlyRow(_ title: String, value: String, detail: String? = nil,
                             valueLayout: SettingsReadOnlyRowLayout = .trailingValue) -> some View {
        switch valueLayout {
        case .trailingValue:
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                    Text(title)
                        .font(Tokens.Typography.rowTitle)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Tokens.Space.m)
                    Text(value)
                        .font(Tokens.Typography.metadata)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                if let detail {
                    Text(detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: layout.rowHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))

        case .statusBlock:
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title)
                    .font(Tokens.Typography.rowTitle)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(Tokens.Typography.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if let detail {
                    Text(detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: layout.rowHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))
        }
    }

    /// A switch whose label says what it does, not only what it is called.
    /// The description sits under the switch and is not part of its target:
    /// reading it must not flip it, and the whole row used to.
    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: isOn) {
                Text(title).font(Tokens.Typography.rowTitle)
            }
            .accessibilityHint(detail)
            Text(detail)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 22)
                .accessibilityHidden(true)
        }
        .frame(minHeight: layout.rowHeight, alignment: .leading)
    }

    private var rowDivider: some View { Divider() }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(Tokens.Typography.metadata)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var awayExplanation: String {
        let asks = !FocusConstants.isNever(model.breakThreshold)
        let ends = !FocusConstants.isNever(model.longAwayCap)
        var text = "Under 5 seconds is ignored. "
        if asks {
            text += "Up to \(Tokens.duration(model.breakThreshold)) is left out of the session "
                + "without interrupting you. "
            text += ends
                ? "Up to \(Tokens.duration(model.longAwayCap)) you are asked what it was; past that the "
                    + "session ends where you left. "
                : "Longer than that you are asked what it was, however long you were gone. "
        } else {
            text += "Absences are never asked about; they are left out of the session. "
            text += ends
                ? "Past \(Tokens.duration(model.longAwayCap)) the session ends where you left. "
                : "The session waits for you however long you were gone. "
        }
        text += (asks && model.fullPromptAfter > 0
                 ? "From \(Tokens.duration(model.fullPromptAfter)) the question fills the screen."
                 : asks ? "Every absence is asked about from the menu bar." : "")
        return text + " Pressing Away is never asked about. Quiet in front of video, a call or a "
            + "presentation keeping the screen awake is Watching, not an absence."
    }
}
