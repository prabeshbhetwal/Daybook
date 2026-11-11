import SwiftUI

/// Settings → Privacy and About: where the data lives, its backups, updates
/// and diagnostics.
extension SettingsGroups {
    var data: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            SurfacePanel(title: "Privacy", layout: layout) {
                readOnlyRow("Storage",
                            value: model.backupSchedule != .off && model.backupDestination == .iCloudDrive
                                && model.iCloudDriveIsOn ? "On this Mac, backed up to iCloud" : "Local only")
                // The full disclosure, once, folded: the row above answers
                // the usual question; this is for whoever wants the detail.
                DisclosureGroup("What is stored, and what leaves this Mac") {
                    explanation(SettingsPrivacyDisclosure.current.storageDetail)
                        .padding(.top, Tokens.Space.xs)
                }
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                rowDivider
                readOnlyRow("App use measured precisely since",
                            value: model.diagnostics.usageAccuracyEpoch.map(
                                SettingsDiagnostics.accuracyEpochLabel)
                                ?? "Not established",
                            detail: "Earlier records may include time away.")
                // Without a usable on-device model there is nothing to switch.
                if ModelGate.modelAvailable {
                    rowDivider
                    toggleRow("Use on-device AI", detail: "For notes and suggestions. Nothing leaves this Mac.",
                              isOn: $model.useAppleIntelligence)
                }
                // Only an upgrade from the oldest format leaves this copy;
                // without one the row said nothing worth reading.
                if let backup = model.diagnostics.legacyBackupURL {
                    rowDivider
                    readOnlyRow("Backup of older app use", value: backup.path, valueLayout: .statusBlock)
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
            preferenceRow("Back up automatically", detail: "Data and preferences, to a dated folder.") {
                RowMenu("Back up automatically", selection: $model.backupSchedule,
                        options: BackupSchedule.allCases) { $0.title }
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
            preferenceRow("Keep automatic backups", detail: "Back Up Now copies are always kept.") {
                RowMenu("Keep automatic backups", selection: $model.backupRetention,
                        options: BackupRetention.allCases) { $0.title }
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
                ? "iCloud Drive › \(DataBackup.folderName)"
                : "iCloud Drive is off on this Mac, so nothing is backed up. Turn it on or choose a folder."
        case .folder(let url):
            return "\(url.path) › \(DataBackup.folderName)"
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
    var updates: some View {
        SurfacePanel(title: "Updates", layout: layout) {
            if model.updater == nil {
                explanation("Only the installed app checks for updates.")
            } else {
                toggleRow("Check for updates automatically", detail: "Sends only the version number.",
                          isOn: $model.checksForUpdatesAutomatically)
                rowDivider
                preferenceRow("How often") {
                    RowMenu("How often to check for updates", selection: $model.updateFrequency,
                            options: UpdateFrequency.allCases) { $0.title }
                        .disabled(!model.checksForUpdatesAutomatically)
                }
                rowDivider
                preferenceRow("When an update is found", detail: model.updateInstallMode.detail) {
                    RowMenu("When an update is found", selection: $model.updateInstallMode,
                            options: UpdateInstallMode.allCases) { $0.title }
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

    var advanced: some View {
        SurfacePanel(title: "Diagnostics", layout: layout) {
            readOnlyRow("Version", value: model.diagnostics.version)
            rowDivider
            readOnlyRow("Build", value: model.diagnostics.build)
            rowDivider
            readOnlyRow("Recovery", value: model.diagnostics.recoverySummary,
                        detail: "Unreadable files are set aside, never overwritten.",
                        valueLayout: .statusBlock)
        }
    }
}
