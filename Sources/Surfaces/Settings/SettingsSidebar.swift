import SwiftUI

extension SettingsSection {
    var title: String {
        switch self {
        case .general: return "General"
        case .focus: return "Focus sessions"
        case .away: return "Away and breaks"
        case .automatic: return "Automatic and rewards"
        case .tracking: return "Tracking and apps"
        case .appearance: return "Appearance"
        case .data: return "Data and privacy"
        case .advanced: return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .focus: return "target"
        case .away: return "moon.zzz"
        case .automatic: return "wand.and.stars"
        case .tracking: return "rectangle.stack.badge.play"
        case .appearance: return "circle.lefthalf.filled"
        case .data: return "lock.shield"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    /// Literal labels used by the visible rows and controls. Search never
    /// indexes promises hidden in explanatory copy.
    var controlLabels: [String] {
        switch self {
        case .general:
            return ["Default tab"]
        case .focus:
            return ["Daily goal"]
        case .away:
            return ["Ask me after", "End session after", "Full-screen prompt after",
                    "Remind me to take breaks"]
        case .automatic:
            return ["Start sessions for me", "Auto-session gap", "Celebrate milestones"]
        case .tracking:
            return ["Sessions per app", "Record app usage"]
        case .appearance:
            return ["Appearance", "Interface density", "Show timeline labels"]
        case .data:
            return ["Privacy", "Accurate app usage from", "Legacy backup location",
                    "Reveal data folder"]
        case .advanced:
            return ["Version", "Build", "Recovery"]
        }
    }

    var mutableControlKeys: [SettingsControlKey] {
        switch self {
        case .general: return [.defaultTab]
        case .focus: return [.dailyGoal]
        case .away:
            return [.breakThreshold, .longAwayCap, .fullPromptAfter, .reminders]
        case .automatic:
            return [.automaticSessions, .automaticGap, .rewards]
        case .tracking:
            return [.sessionsPerApp, .usageRecording]
        case .appearance:
            return [.appearance, .density, .timelineLabels]
        case .data, .advanced:
            return []
        }
    }

    static func matching(_ query: String) -> [SettingsSection] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return allCases }
        return allCases.filter { section in
            ([section.title] + section.controlLabels).contains {
                $0.localizedCaseInsensitiveContains(needle)
            }
        }
    }
}

/// Comfortable widths retain the desktop list. The selected group is the only
/// dominant element in the right pane; this is navigation, not a second form.
struct SettingsSidebar: View {
    let sections: [SettingsSection]
    @Binding var selected: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            ForEach(sections) { section in
                Button { selected = section } label: {
                    HStack(spacing: Tokens.Space.s) {
                        Image(systemName: section.symbol)
                            .frame(width: 18)
                            .symbolRenderingMode(.hierarchical)
                        Text(section.title)
                            .lineLimit(1)
                        Spacer(minLength: Tokens.Space.s)
                    }
                    .font(Tokens.Typography.rowTitle)
                    .padding(.horizontal, Tokens.Space.m)
                    .frame(minHeight: 36)
                    .background(selected == section
                                ? Tokens.Colour.elevated : Color.clear,
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                                     style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.title), \(selected == section ? "selected" : "not selected")")
                .accessibilityAddTraits(selected == section ? .isSelected : [])
            }
        }
        .frame(width: 240, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings groups")
    }
}

struct SettingsGroupMenu: View {
    let sections: [SettingsSection]
    @Binding var selected: SettingsSection

    var body: some View {
        Menu {
            ForEach(sections) { section in
                Button {
                    selected = section
                } label: {
                    Label(section.title, systemImage: section.symbol)
                }
            }
        } label: {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: selected.symbol)
                Text(selected.title)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(Tokens.Typography.rowTitle)
            .padding(.horizontal, Tokens.Space.m)
            .frame(minHeight: 36)
            .background(Tokens.Colour.elevated, in: Capsule())
            .overlay(Capsule().stroke(Tokens.Colour.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Settings group, \(selected.title), selected")
        .accessibilityAddTraits(.isSelected)
    }
}

/// ImageRenderer cannot host AppKit's menu view service. The snapshot path uses
/// this inert rendering of the same selected-group chrome; production always
/// uses SettingsGroupMenu above.
struct SettingsGroupLabel: View {
    let selected: SettingsSection

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: selected.symbol)
            Text(selected.title)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(Tokens.Typography.rowTitle)
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: 36)
        .background(Tokens.Colour.elevated, in: Capsule())
        .overlay(Capsule().stroke(Tokens.Colour.line, lineWidth: 1))
        .accessibilityLabel("Settings group, \(selected.title), selected")
        .accessibilityAddTraits(.isSelected)
    }
}
