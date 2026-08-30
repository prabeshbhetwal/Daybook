import SwiftUI

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
            preferenceRow("Default tab",
                          detail: "Used once when FocusContinuity launches its main window.") {
                Picker("Default tab", selection: $model.defaultAppTab) {
                    ForEach(AppTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Default tab")
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
                preferenceRow("Ask me after") {
                    thresholdPicker("Ask me after", selection: $model.breakThreshold,
                                    options: FocusConstants.thresholdOptions)
                }
                rowDivider
                preferenceRow("End session after") {
                    thresholdPicker("End session after", selection: $model.longAwayCap,
                                    options: FocusConstants.longAwayCapOptions)
                }
                rowDivider
                preferenceRow("Full-screen prompt after") {
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
                Toggle("Remind me to take breaks", isOn: $model.remindersEnabled)
                    .frame(minHeight: layout.rowHeight)
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

    private var automatic: some View {
        SurfacePanel(title: "Automatic sessions", layout: layout) {
            Toggle("Start sessions for me", isOn: $model.autoSessionsEnabled)
                .frame(minHeight: layout.rowHeight)
            rowDivider
            preferenceRow("Auto-session gap") {
                thresholdPicker("Auto-session gap", selection: $model.breakLength,
                                options: FocusConstants.breakLengthOptions)
            }
            rowDivider
            Toggle("Celebrate milestones", isOn: $model.rewardsEnabled)
                .frame(minHeight: layout.rowHeight)
            explanation("Sessions the app starts can be undone from the notice, and one it "
                        + "ends on its own ends where the work stopped. The gap is how long a "
                        + "pause must be before such a session is treated as over.")
            explanation("Started sessions are named by what you are doing — Browsing in a "
                        + "browser, Coding, Writing & AI, Design elsewhere. Apps the app does "
                        + "not know are read from the category they declare about themselves, "
                        + "when they declare one.")
        }
    }

    private var tracking: some View {
        SurfacePanel(title: "Tracking and apps", layout: layout) {
            preferenceRow("Sessions per app",
                          detail: "Controls how many recent sessions each app shows in the menu bar.") {
                Picker("Sessions per app", selection: $model.menuSessionCount) {
                    ForEach([3, 5, 7, 10], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("Sessions per app")
            }
            rowDivider
            Toggle("Record app usage", isOn: $model.isTrackingEnabled)
                .frame(minHeight: layout.rowHeight)
            explanation(SettingsPrivacyDisclosure.current.storageDetail)
        }
    }

    private var appearance: some View {
        SurfacePanel(title: "Interface", layout: layout) {
            preferenceRow("Appearance") {
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
            preferenceRow("Interface density") {
                Picker("Interface density", selection: $model.interfaceDensity) {
                    Text("Comfortable").tag(InterfaceDensity.comfortable)
                    Text("Compact").tag(InterfaceDensity.compact)
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Interface density")
            }
            rowDivider
            Toggle("Show timeline labels", isOn: $model.showsTimelineLabels)
                .frame(minHeight: layout.rowHeight)
            explanation("System follows the current macOS appearance. Reduce Motion always "
                        + "follows macOS and is never overridden here.")
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
                            detail: "A backup appears only when older app-usage bytes are migrated.")
            }

            SurfacePanel(title: "Data folder", layout: layout) {
                readOnlyRow("Location", value: model.dataDirectoryURL.path)
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
                        detail: "Recovery preserves source evidence before the app resumes writing.")
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

    private func readOnlyRow(_ title: String, value: String, detail: String? = nil) -> some View {
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
