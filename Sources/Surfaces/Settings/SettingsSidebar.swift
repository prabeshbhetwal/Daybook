import SwiftUI

/// The eight logical sections keep control ownership precise; five pages make
/// the native sheet small enough to read without a second, unreachable pane.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case sessions
    case awayAndBreaks
    case recording
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .sessions: return "Sessions"
        case .awayAndBreaks: return "Away & Breaks"
        case .recording: return "Recording"
        case .privacy: return "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .sessions: return "target"
        case .awayAndBreaks: return "moon.zzz"
        case .recording: return "rectangle.stack.badge.play"
        case .privacy: return "lock.shield"
        }
    }

    var sections: [SettingsSection] {
        switch self {
        case .general: return [.general, .appearance]
        case .sessions: return [.focus, .automatic]
        case .awayAndBreaks: return [.away]
        case .recording: return [.tracking]
        case .privacy: return [.data, .advanced]
        }
    }

    init(section: SettingsSection) {
        switch section {
        case .general, .appearance: self = .general
        case .focus, .automatic: self = .sessions
        case .away: self = .awayAndBreaks
        case .tracking: self = .recording
        case .data, .advanced: self = .privacy
        }
    }

    static func matching(_ query: String) -> [SettingsPage] {
        let matchingSections = Set(SettingsSection.matching(query))
        return allCases.filter { !$0.sections.filter(matchingSections.contains).isEmpty }
    }

    func sections(matching query: String) -> [SettingsSection] {
        let matchingSections = Set(SettingsSection.matching(query))
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? sections
            : sections.filter(matchingSections.contains)
    }
}

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

    /// Literal labels used by visible controls. Search does not promise a
    /// preference that cannot be reached from the page it returns.
    var controlLabels: [String] {
        switch self {
        case .general: return ["Opens on"]
        case .focus: return ["Daily goal"]
        case .away:
            return ["Ask me after", "End session after", "Full-screen prompt after",
                    "Remind me to take breaks"]
        case .automatic:
            return ["Use my activity rules", "Use legacy automatic sessions", "Activity rules",
                    "Start after", "Add application", "Auto-session gap", "Celebrate milestones"]
        case .tracking: return ["Recent app visits", "Record app usage"]
        case .appearance:
            return ["Appearance", "Interface density", "Show Story timestamps",
                    "Expand entry details by default"]
        case .data:
            return ["Privacy", "Accurate app usage from", "Legacy backup location",
                    "Reveal data folder"]
        case .advanced: return ["Version", "Build", "Recovery"]
        }
    }

    var mutableControlKeys: [SettingsControlKey] {
        switch self {
        case .general: return [.opensOn]
        case .focus: return [.dailyGoal]
        case .away: return [.breakThreshold, .longAwayCap, .fullPromptAfter, .reminders]
        case .automatic:
            return [.activityRuleAutomation, .activityRules, .automaticSessions,
                    .automaticGap, .rewards]
        case .tracking: return [.sessionsPerApp, .usageRecording]
        case .appearance: return [.appearance, .density, .timelineLabels, .entryDetails]
        case .data, .advanced: return []
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

/// All five pages remain visible at the native sheet width in one compact tab
/// row, rather than becoming a second navigation surface.
struct SettingsPageTabs: View {
    let pages: [SettingsPage]
    @Binding var selected: SettingsPage

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            ForEach(pages) { page in
                Button { selected = page } label: {
                    Text(page.title)
                        .font(Tokens.Typography.metadata.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(selected == page ? StoryStyle.well : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(page.title), \(selected == page ? "selected" : "not selected")")
                .accessibilityAddTraits(selected == page ? .isSelected : [])
            }
        }
        .padding(Tokens.Space.xs)
        .background(StoryStyle.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                                           style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
            .stroke(StoryStyle.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings pages")
    }
}
