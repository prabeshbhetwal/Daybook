import SwiftUI

/// Settings → General, below the menu bar: how Daybook looks and what it
/// shows, then how it feels. Every row here changes the app's own
/// presentation, never what is recorded or kept.
extension SettingsGroups {
    var appearance: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            interfacePanel
            storyPanel
        }
    }

    private var interfacePanel: some View {
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
        }
    }

    /// What the Story and its Top apps card show. The recording they draw
    /// from is a switch in Privacy & Data.
    private var storyPanel: some View {
        SurfacePanel(title: "Story", layout: layout) {
            toggleRow("Show Story timestamps", isOn: $model.showsTimelineLabels)
            rowDivider
            toggleRow("Expand entry details by default", isOn: $model.expandsEntryDetails)
            rowDivider
            preferenceRow("Fold quiet stretches after",
                          detail: "Gaps and loose app use fold into one line.") {
                RowMenu("Fold quiet stretches after", selection: $model.quietFold,
                        options: FocusConstants.quietFoldOptions) { $0 == 0 ? "Never" : "\($0) rows" }
            }
            rowDivider
            preferenceRow("Apps shown in a card") {
                RowMenu("Apps shown in a card", selection: $model.railAppCount,
                        options: FocusConstants.railAppOptions) { "\($0)" }
            }
            rowDivider
            preferenceRow("Recent app visits") {
                RowMenu("Recent app visits", selection: $model.menuSessionCount,
                        options: [3, 5, 7, 10]) { "\($0)" }
            }
        }
    }

    var hapticsPanel: some View {
        SurfacePanel(title: "Haptics", layout: layout) {
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
