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
        case .tracking: tracking
        case .appearance: appearance
        case .data: data
        case .advanced: advanced
        }
    }

    private var general: some View {
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
                        + "\(FocusConstants.goalMedianWindowDays) working days.")
        }
    }

    private var away: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Stepping away", layout: layout) {
                preferenceRow("Ask me after",
                              detail: "Shorter absences are left out of the session without a question.") {
                    thresholdPicker("Ask me after", selection: $model.breakThreshold,
                                    options: FocusConstants.thresholdOptions)
                }
                rowDivider
                preferenceRow("End session after",
                              detail: "Longer than this, the session ends where you left rather than waiting.") {
                    thresholdPicker("End session after", selection: $model.longAwayCap,
                                    options: FocusConstants.longAwayCapOptions)
                }
                rowDivider
                preferenceRow("Full-screen prompt after",
                              detail: "How long the away question stays in the menu bar before it fills the screen.") {
                    Picker("Full-screen prompt after", selection: $model.fullPromptAfter) {
                        ForEach(FocusConstants.fullPromptAfterOptions, id: \.self) { seconds in
                            Text(Tokens.duration(seconds)).tag(seconds)
                        }
                        Text("Never").tag(0.0)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .accessibilityLabel("Full-screen prompt after")
                }
                explanation(awayExplanation)
            }

            SurfacePanel(title: "Breaks", layout: layout) {
                toggleRow("Remind me to take breaks",
                          detail: "A notice after a long stretch of continuous use, timed from your typing "
                            + "and clicking rather than from sessions.",
                          isOn: $model.remindersEnabled)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    ForEach(BreakTier.allCases, id: \.rawValue) { tier in
                        Text("\(Int(tier.workThreshold / 60)) minutes working → "
                             + "\(BreakPrompt.phrase(tier.breakLength)) off. \(tier.reason)")
                    }
                    Text("Timed from continuous use, not from sessions. A short break resets "
                         + "the short timer only; the longer ones keep running.")
                }
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var categories: some View {
        SurfacePanel(title: "Categories", layout: layout) {
            CategoriesView(model: model)
        }
    }

    private var automatic: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Automatic sessions", layout: layout) {
                toggleRow("Use my activity rules",
                          detail: "Start and switch sessions from the rules below, going by which apps "
                            + "you are in. Editing a rule never starts a session by itself.",
                          isOn: $model.activityRuleAutomationEnabled)
                rowDivider
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
                    thresholdPicker("Auto-session gap", selection: $model.breakLength,
                                    options: FocusConstants.breakLengthOptions)
                }
                rowDivider
                toggleRow("Celebrate milestones",
                          detail: "A short notice in the corner when you reach the daily goal, keep a "
                            + "streak going or beat your usual pace.",
                          isOn: $model.rewardsEnabled)
            }
            SurfacePanel(title: "Activities and applications", layout: layout) {
                ActivityRulesView(model: model)
            }
        }
    }

    private var tracking: some View {
        SurfacePanel(title: "Tracking and apps", layout: layout) {
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

    private func thresholdPicker(_ label: String, selection: Binding<TimeInterval>,
                                 options: [TimeInterval]) -> some View {
        Picker(label, selection: selection) {
            ForEach(options, id: \.self) { seconds in
                Text(Tokens.duration(seconds)).tag(seconds)
            }
        }
        .labelsHidden()
        .frame(width: 180)
        .accessibilityLabel(label)
    }

    private var rowDivider: some View { Divider() }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(Tokens.Typography.metadata)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var awayExplanation: String {
        "Under 5 seconds is ignored. Up to \(Tokens.duration(model.breakThreshold)) is left "
        + "out of the session without interrupting you. Up to "
        + "\(Tokens.duration(model.longAwayCap)) you are asked what it was; past that the "
        + "session ends where you left. "
        + (model.fullPromptAfter > 0
           ? "From \(Tokens.duration(model.fullPromptAfter)) the question fills the screen."
           : "Every absence is asked about from the menu bar.")
        + " Pressing Away is never asked about. Quiet in front of video, a call or a "
        + "presentation keeping the screen awake is Watching, not an absence."
    }
}
