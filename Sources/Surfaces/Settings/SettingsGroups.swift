import SwiftUI

/// Scalar diagnostics align a short value with their title; a narrative status
/// needs the row's full reading width instead of a compressed trailing column.
enum SettingsReadOnlyRowLayout: Equatable {
    case trailingValue
    case statusBlock

    var usesTrailingValue: Bool { self == .trailingValue }
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
        case .updates: updates
        case .advanced: advanced
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Menu bar, Dock and login", layout: layout) {
                toggleRow("Open at login",
                          detail: "Starts Daybook in the menu bar when you sign in, so the "
                            + "record never has a gap at the start of the day.",
                          isOn: $model.opensAtLogin)
                if let message = loginItemMessage {
                    explanation(message)
                }
                if model.loginItemNeedsApproval {
                    systemSettingsRow(Self.loginApproval, button: "Open Login Items") {
                        model.openLoginItemsSettings()
                    }
                }
                rowDivider
                toggleRow("Show the icon in the menu bar",
                          detail: "Off, the Dock icon stays so Daybook can always be reached.",
                          isOn: $model.showsMenuBarIcon)
                rowDivider
                toggleRow("Show the session time in the menu bar",
                          detail: "Off, the menu bar keeps only the goal ring while a session runs.",
                          isOn: $model.menuBarShowsTime)
                    .disabled(!model.showsMenuBarIcon)
                rowDivider
                preferenceRow("Dock icon", detail: dockIconDetail) {
                    Picker("Dock icon", selection: $model.dockIconMode) {
                        Text("While the window is open").tag(DockIconMode.whileWindowOpen)
                        Text("Always").tag(DockIconMode.always)
                        Text("Never").tag(DockIconMode.never)
                    }
                    .labelsHidden()
                    .disabled(!model.showsMenuBarIcon)
                    .accessibilityLabel("Dock icon")
                }
            }
            // A switch that flips back by itself is otherwise silent.
            .announcesChanges(to: loginItemMessage)
            .announcesChanges(to: model.loginItemNeedsApproval ? Self.loginApproval : nil)
            keyboard
            SurfacePanel(title: "Confirmations", layout: layout) {
                toggleRow("Ask before changing how a break counts",
                          detail: "Count as focus and Leave uncounted ask first. Undo restores the break either way.",
                          isOn: asks(.changeBreak))
                rowDivider
                toggleRow("Ask before removing a session",
                          detail: "Remove asks first. Undo puts the session back either way.",
                          isOn: asks(.removeSession))
                explanation("“Don't ask again” in a question turns its switch off here. "
                            + "Deleting a rule, resetting a category and discarding a note always ask, "
                            + "because Undo cannot reverse them.")
            }
            if model.canReplayWelcome {
                SurfacePanel(title: "Getting started", layout: layout) {
                    explanation("The tour walks through every part of the app in twelve short "
                                + "chapters — starting a session, what your Mac records on its "
                                + "own, the away card, rules, History, the menu bar. About seven "
                                + "minutes; any chapter can be skipped.")
                    // A tour ended by a quit or a crash, not by Skip or its
                    // last card, can be picked up where it was left.
                    if let chapter = model.interruptedWelcomeChapter {
                        explanation("You left the tour at chapter \(chapter.number), \(chapter.title).")
                    }
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

    /// The keys, in one place that stays. The app has no menu bar to list
    /// them in, and the welcome names them once and moves on.
    private var keyboard: some View {
        SurfacePanel(title: "Keyboard", layout: layout) {
            globalShortcutRow
            rowDivider
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                ForEach(Self.windowKeys, id: \.keys) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                        Text(entry.keys)
                            .font(Tokens.Typography.label.monospacedDigit())
                            .frame(width: 52.zoomed, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(entry.action)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.action), \(entry.spoken)")
                }
                Text(Self.pauseOrAwayNote)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tokens.Space.xs)
            }
            .padding(.vertical, Tokens.Space.s)
        }
    }

    /// The chord, a button that records a new one, and the way back to the
    /// standard chord or to none. The line under it says whether it is held.
    private var globalShortcutRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                Text("Start or end a session from any app")
                    .font(Tokens.Typography.rowTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Tokens.Space.m)
                ShortcutRecorder(shortcut: model.globalShortcut) { model.setGlobalShortcut($0) }
                if model.globalShortcut != .standard {
                    Button("Reset") { model.setGlobalShortcut(.standard) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset the shortcut to Control-Option-Space")
                }
                if model.globalShortcut != nil {
                    Button("Turn off") { model.setGlobalShortcut(nil) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Turn the global shortcut off")
                }
            }
            explanation(Self.globalShortcutDetail(model.globalShortcutStatus, shortcut: model.globalShortcut))
            if let message = model.globalShortcutMessage {
                Text(message)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Colour.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: layout.rowHeight)
        .announcesChanges(to: model.globalShortcutMessage)
    }

    static func globalShortcutDetail(_ status: HotKeyMonitor.Status,
                                     shortcut: GlobalShortcut? = .standard) -> String {
        let chord = shortcut?.spoken ?? "The shortcut"
        switch status {
        case .registered:
            return "\(chord) works in any app. It also brings up an away card that is waiting for you."
        case .yieldedToVoiceOver:
            return "Off while VoiceOver is on, because VoiceOver uses Control-Option chords. "
                + "It comes back when VoiceOver turns off, or record a chord without both."
        case .unavailable:
            return "Another app is using \(chord), so this shortcut is off. Record a different "
                + "one, or free the keys in that app, then quit and reopen Daybook."
        case .off:
            return "Off. Record a shortcut to turn it on."
        }
    }

    /// Pause and Away sit side by side on the bar and read as one thing
    /// until pressed; the keyboard list is where the difference is written down.
    static let pauseOrAwayNote = "Pause is for staying at the Mac: the clock stops, app use is still "
        + "recorded. Away is for leaving it: nothing is recorded until you're back, and a long "
        + "gap is asked about."

    /// The window's own keys. The session keys come from `SessionShortcut`,
    /// so this list cannot drift from what the Session commands answer to.
    static let windowKeys: [KeyEntry] = [
        KeyEntry(keys: SessionShortcut.start.glyphs, spoken: "Option-Command-N", action: "Start focus"),
        KeyEntry(keys: SessionShortcut.pauseOrResume.glyphs, spoken: "Option-Command-P",
                 action: "Pause or resume"),
        KeyEntry(keys: SessionShortcut.stepAway.glyphs, spoken: "Option-Command-A", action: "Away"),
        KeyEntry(keys: SessionShortcut.stop.glyphs, spoken: "Option-Command-S", action: "Stop the session"),
        KeyEntry(keys: "⌘1", spoken: "Command-1", action: "The day's story"),
        KeyEntry(keys: "⌘2", spoken: "Command-2", action: "History"),
        KeyEntry(keys: "⌘F", spoken: "Command-F", action: "Find in History"),
        KeyEntry(keys: "⌘K", spoken: "Command-K", action: "Ask Daybook"),
        KeyEntry(keys: "⌘6", spoken: "Command-6", action: "Awards"),
        KeyEntry(keys: "⌘7", spoken: "Command-7", action: "Session controls"),
        KeyEntry(keys: "⌘,", spoken: "Command-comma", action: "Settings"),
        KeyEntry(keys: "⌘+", spoken: "Command-plus", action: "Zoom in"),
        KeyEntry(keys: "⌘−", spoken: "Command-minus", action: "Zoom out"),
        KeyEntry(keys: "⌘0", spoken: "Command-0", action: "Actual size")
    ]

    struct KeyEntry: Hashable {
        let keys: String
        /// How VoiceOver should say the keys; it reads the glyphs poorly.
        let spoken: String
        let action: String
    }

    private var loginItemMessage: String? {
        model.loginItemError.map { "Could not change the login item: \($0)" }
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
                .accessibilityLabel("Daily goal")
            }
            rowDivider
            preferenceRow("Usual pace compares with",
                          detail: "Today is compared with the same hour on these working days.") {
                Picker("Usual pace compares with", selection: $model.paceWindowDays) {
                    ForEach(FocusConstants.paceWindowOptions, id: \.self) { days in
                        Text("last \(days) days").tag(days)
                    }
                }
                .labelsHidden()
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
                          detail: "Used until you choose another.") {
                Picker("New sessions start as", selection: $model.defaultWorkType) {
                    ForEach(WorkType.startable) { type in
                        Label(type.displayName, systemImage: type.symbolName)
                            .labelStyle(.titleAndIcon).tag(type)
                    }
                }
                .labelsHidden()
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
                // Declined notifications drop the Notification Centre copy
                // without a word; nothing is added while they are allowed.
                if model.remindersEnabled && model.notificationsDenied {
                    systemSettingsRow("Notifications are off, so a reminder shows on screen but not in "
                                      + "Notification Centre.",
                                      button: "Open Notification Settings") {
                        model.openNotificationSettings()
                    }
                }
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
                            VStack(alignment: .leading, spacing: 2.zoomed) {
                                Text("After \(Int(tier.workThreshold / 60)) minutes, "
                                     + "\(BreakPrompt.phrase(tier.breakLength)) off")
                                    .font(Tokens.Typography.control)
                                Text(tier.reason)
                                    .font(Tokens.Typography.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!model.remindersEnabled)
                    }
                    // "Timed from use, not sessions" is the switch's own detail.
                    Text("A short break resets the short timer only; the longer ones keep running.")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 26.zoomed)
            }
        }
        .onAppear(perform: model.refreshSystemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemStatus()
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
                          // What a rule does is the panel's opening line below.
                          detail: "Rules start a session only when none is running; they never switch one. "
                            + "When off, your rules are kept but start nothing. "
                            + "Editing a rule never starts a session by itself.",
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
                          detail: "A work app starts a session and a break app pauses it. The category "
                            + "is the one you chose the last few times you started from that app."
                            + (rulesOn ? "" : " Activity rules replace this while they are on."),
                          isOn: Binding(get: { model.autoSessionsEnabled && !rulesOn },
                                        set: { model.autoSessionsEnabled = $0 }))
                    .disabled(rulesOn)
                if rulesOn {
                    explanation("Off while activity rules are on.")
                }
                rowDivider
                preferenceRow("End a paused automatic session after",
                              detail: "Come back sooner and it picks up where it left off.") {
                    ThresholdControl(label: "End a paused automatic session after",
                                     selection: $model.breakLength,
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
                          detail: "How many apps the side panel and the History previews list before "
                            + "\u{201c}See all\u{201d}.") {
                Picker("Apps shown in a card", selection: $model.railAppCount) {
                    ForEach(FocusConstants.railAppOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
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
                .accessibilityLabel("Interface density")
            }
            rowDivider
            preferenceRow("Zoom",
                          detail: "Makes text, spacing and controls larger or smaller in every Daybook window.") {
                ZoomControl(model: model)
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
                .accessibilityLabel("Fold quiet stretches after")
            }
        }
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Privacy", layout: layout) {
                readOnlyRow("Storage",
                            value: model.backupSchedule != .off && model.backupDestination == .iCloudDrive
                                && model.iCloudDriveIsOn ? "On this Mac, backed up to iCloud" : "Local only",
                            detail: SettingsPrivacyDisclosure.current.storageDetail)
                rowDivider
                readOnlyRow("App use measured precisely since",
                            value: model.diagnostics.usageAccuracyEpoch.map(
                                SettingsDiagnostics.accuracyEpochLabel)
                                ?? "Not established",
                            detail: "Earlier app use may include time you were not at the Mac.")
                // Only an upgrade from the oldest format leaves this copy;
                // without one the row said nothing worth reading.
                if let backup = model.diagnostics.legacyBackupURL {
                    rowDivider
                    readOnlyRow("Backup of older app use", value: backup.path,
                                detail: "Made when older data was upgraded.",
                                valueLayout: .statusBlock)
                }
            }

            backups

            SurfacePanel(title: "Data folder", layout: layout) {
                readOnlyRow("Location", value: model.dataDirectoryURL.path,
                            valueLayout: .statusBlock)
                Button("Reveal data folder") { model.revealDataFolder() }
                    .buttonStyle(.bordered)
                    .controlSize(Tokens.Zoom.controlSize(.large))
                    .accessibilityHint("Opens the local Daybook data folder in Finder")
            }
        }
        .onAppear { model.refreshBackupState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshBackupState()
        }
    }

    /// The schedule, where backups go, how long automatic ones stay, and
    /// what the last one did, including whether it has reached iCloud.
    private var backups: some View {
        SurfacePanel(title: "Backups", layout: layout) {
            preferenceRow("Back up automatically",
                          detail: "Copies the data folder and your preferences to a new dated folder. "
                            + "A Mac asleep at the time backs up soon after it wakes.") {
                Picker("Back up automatically", selection: $model.backupSchedule) {
                    ForEach(BackupSchedule.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .accessibilityLabel("Back up automatically")
            }
            rowDivider
            preferenceRow("Back up to", detail: backupDestinationDetail) {
                HStack(spacing: Tokens.Space.s) {
                    if model.backupDestination != .iCloudDrive {
                        Button("Use iCloud Drive") { model.backupDestination = .iCloudDrive }
                    }
                    Button("Choose Folder…") { model.chooseBackupFolder() }
                        .accessibilityHint("Picks another disk or folder for backups")
                }
            }
            rowDivider
            preferenceRow("Keep automatic backups",
                          detail: "Older ones go to the Trash at the next backup; the newest always stays. "
                            + "Backups made with Back Up Now are always kept.") {
                Picker("Keep automatic backups", selection: $model.backupRetention) {
                    ForEach(BackupRetention.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .accessibilityLabel("Keep automatic backups")
            }
            rowDivider
            readOnlyRow("Last backup", value: lastBackupValue, detail: lastBackupDetail)
            rowDivider
            readOnlyRow("Next backup", value: nextBackupValue)
            HStack(spacing: Tokens.Space.s) {
                Button("Back Up Now") { model.backUp() }
                    .buttonStyle(.bordered)
                    .controlSize(Tokens.Zoom.controlSize(.large))
                    .accessibilityHint("Copies your Daybook data and preferences to \(model.backupDestination.name)")
                Button("Show Backups") { model.revealBackups() }
                    .buttonStyle(.bordered)
                    .controlSize(Tokens.Zoom.controlSize(.large))
                    .accessibilityHint("Opens the backups folder in Finder")
            }
            if let status = model.backupStatus {
                explanation(status)
            }
        }
        // Whether Back Up Now worked appears under its button; say it too.
        .announcesChanges(to: model.backupStatus)
    }

    private var backupDestinationDetail: String {
        switch model.backupDestination {
        case .iCloudDrive:
            return model.iCloudDriveIsOn
                ? "iCloud Drive › \(DataBackup.folderName), which iCloud keeps in step across your devices."
                : "iCloud Drive is off on this Mac, so nothing is backed up. Turn it on in System Settings › "
                    + "your name › iCloud › iCloud Drive, or choose a folder."
        case .folder(let url):
            return "\(url.path) › \(DataBackup.folderName). If it is on another disk, backups wait until it "
                + "is connected."
        }
    }

    private var lastBackupValue: String {
        model.backupLog.lastSuccess?.formatted(date: .abbreviated, time: .shortened) ?? "None yet"
    }

    private var lastBackupDetail: String? {
        let log = model.backupLog
        var parts: [String] = []
        switch model.backupUploadState {
        case .uploaded?: parts.append("Uploaded to iCloud.")
        case .uploading?: parts.append("Uploading to iCloud.")
        case .waiting?: parts.append("Waiting to upload to iCloud.")
        case .failed(let reason)?: parts.append("Not uploaded to iCloud: \(reason)")
        case .missing?: parts.append("That backup is no longer where it was made.")
        case .notInICloud?, nil: break
        }
        if let failure = log.failure, let failedAt = log.failedAt, failedAt > (log.lastSuccess ?? .distantPast) {
            parts.append("The latest attempt, \(failedAt.formatted(date: .omitted, time: .shortened)), failed: \(failure)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var nextBackupValue: String {
        switch model.nextBackup() {
        case .off: return "Off"
        case .due: return "Within half an hour"
        case .at(let next): return next.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// Sparkle reads the release feed on GitHub; only the version is sent.
    private var updates: some View {
        SurfacePanel(title: "Updates", layout: layout) {
            if model.updater == nil {
                explanation("Updates are checked by the installed app. This copy is a preview or a test.")
            } else {
                toggleRow("Check for updates automatically",
                          detail: "Looks for a new version on GitHub. Only the version number is sent.",
                          isOn: $model.checksForUpdatesAutomatically)
                rowDivider
                preferenceRow("How often") {
                    Picker("How often", selection: $model.updateFrequency) {
                        ForEach(UpdateFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(!model.checksForUpdatesAutomatically)
                    .accessibilityLabel("How often to check for updates")
                }
                rowDivider
                preferenceRow("When an update is found", detail: model.updateInstallMode.detail) {
                    Picker("When an update is found", selection: $model.updateInstallMode) {
                        ForEach(UpdateInstallMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityLabel("When an update is found")
                }
                rowDivider
                preferenceRow("Check for Updates", detail: lastUpdateCheck) {
                    Button("Check Now") { model.updater?.checkForUpdates() }
                        .disabled(model.updater?.canCheckForUpdates != true)
                }
            }
        }
    }

    private var lastUpdateCheck: String {
        guard let date = model.updater?.lastCheck else { return "Not checked yet." }
        let day = Tokens.dayLabel(date)
        let when = ["Today", "Yesterday"].contains(day) ? day.lowercased() : "on \(day)"
        return "Last checked \(when) at \(Tokens.timeOfDayOnly(date))."
    }

    private var advanced: some View {
        SurfacePanel(title: "Diagnostics", layout: layout) {
            readOnlyRow("Version", value: model.diagnostics.version)
            rowDivider
            readOnlyRow("Build", value: model.diagnostics.build)
            rowDivider
            readOnlyRow("Recovery", value: model.diagnostics.recoverySummary,
                        detail: "A file the app cannot read is set aside or left untouched, never written over.",
                        valueLayout: .statusBlock)
        }
    }

    private func preferenceRow<Accessory: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 3.zoomed) {
                Text(title).font(Tokens.Typography.rowTitle)
                if let detail {
                    Text(detail)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Tokens.Space.m)
            // Every control at its own width against the trailing edge, the
            // way System Settings lines them up. A pop-up draws at its widest
            // item whatever frame it is given, so a wider frame centred it and
            // each row's control stood at a different place.
            accessory()
                .fixedSize()
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
                        .font(Tokens.Typography.body)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                if let detail {
                    Text(detail)
                        .font(Tokens.Typography.body)
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
                        .font(Tokens.Typography.body)
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
        VStack(alignment: .leading, spacing: 3.zoomed) {
            Toggle(isOn: isOn) {
                Text(title).font(Tokens.Typography.rowTitle)
            }
            .accessibilityHint(detail)
            Text(detail)
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 22.zoomed)
                .accessibilityHidden(true)
        }
        .frame(minHeight: layout.rowHeight, alignment: .leading)
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

    /// A system state this app cannot change for you, with the button that
    /// opens the place where you can.
    private func systemSettingsRow(_ text: String, button: String,
                                   action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
            explanation(text)
            Spacer(minLength: Tokens.Space.s)
            Button(button, action: action)
                .fixedSize()
        }
    }

    private var rowDivider: some View { Divider() }

    /// The app's menus come and go with the Dock icon, so the detail names both.
    private var dockIconDetail: String {
        guard model.showsMenuBarIcon else {
            return "Always, while the menu bar icon is hidden: the Dock is then the only way in."
        }
        switch model.dockIconMode {
        case .whileWindowOpen: return "The Dock icon and the app's menus show while the window is open."
        case .always: return "The Dock icon and the app's menus show all the time."
        case .never: return "Daybook stays in the menu bar, with no Dock icon or app menus."
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(Tokens.Typography.body)
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
        if ends {
            text += "A pause longer than \(Tokens.duration(model.longAwayCap)) ends the session too. "
        }
        text += (asks && model.fullPromptAfter > 0
                 ? "From \(Tokens.duration(model.fullPromptAfter)) the question fills the screen."
                 : asks ? "Every absence is asked about from the menu bar." : "")
        return text + " Pressing Away is never asked about. Quiet in front of video, a call or a "
            + "presentation keeping the screen awake is Watching, not an absence."
    }
}
