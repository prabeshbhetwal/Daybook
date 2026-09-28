import SwiftUI

/// The eight logical sections keep control ownership precise; five pages make
/// the native sheet small enough to read without a second, unreachable pane.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case sessions
    case activities
    case awayAndBreaks
    case recording
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .sessions: return "Sessions"
        case .activities: return "Activities"
        case .awayAndBreaks: return "Away & Breaks"
        case .recording: return "Recording"
        case .privacy: return "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .sessions: return "target"
        case .activities: return "app.badge.checkmark"
        case .awayAndBreaks: return "moon.zzz"
        case .recording: return "rectangle.stack.badge.play"
        case .privacy: return "lock.shield"
        }
    }

    /// The colour of the page's sidebar icon: the system's own way of
    /// telling settings pages apart at a glance.
    var hue: WorkTypeHue {
        switch self {
        case .general: return .grey
        case .sessions: return .blue
        case .activities: return .purple
        case .awayAndBreaks: return .indigo
        case .recording: return .orange
        case .privacy: return .green
        }
    }

    /// The glyph drawn on the page's tile. White reaches 3:1 only on the
    /// darker hues; on grey, orange and green it fell to 2 to 2.9:1, so those
    /// take a near-black glyph.
    var glyphColour: Color {
        [.grey, .orange, .green].contains(hue) ? Color(white: 0.06) : .white
    }

    /// The page `delta` rows away in `pages`, or nil past either end: a
    /// sidebar stops at its first and last page rather than wrapping.
    func neighbour(in pages: [SettingsPage], by delta: Int) -> SettingsPage? {
        guard let index = pages.firstIndex(of: self), pages.indices.contains(index + delta) else { return nil }
        return pages[index + delta]
    }

    /// What the page is about, under its title in the detail.
    var summary: String {
        switch self {
        case .general: return "Starting at login, and what the menu bar shows."
        case .sessions: return "Your goal, your categories, and what starts a session by itself."
        case .activities: return "Rules that start and name a session from the apps you are in."
        case .awayAndBreaks: return "What happens when you step away, and when to be reminded to rest."
        case .recording: return "What is recorded about the apps you use."
        case .privacy: return "Where your data lives, and the facts about this build."
        }
    }

    var sections: [SettingsSection] {
        switch self {
        case .general: return [.general, .appearance]
        case .sessions: return [.focus, .categories, .automatic]
        case .activities: return [.activities]
        case .awayAndBreaks: return [.away]
        case .recording: return [.tracking]
        case .privacy: return [.data, .advanced]
        }
    }

    init(section: SettingsSection) {
        switch section {
        case .general, .appearance: self = .general
        case .focus, .categories, .automatic: self = .sessions
        case .activities: self = .activities
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
        case .categories: return "Categories"
        case .away: return "Away and breaks"
        case .automatic: return "Automatic and rewards"
        case .activities: return "Activity rules"
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
        case .categories: return "tag"
        case .away: return "moon.zzz"
        case .automatic: return "wand.and.stars"
        case .activities: return "app.badge.checkmark"
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
        case .general: return ["Open at login", "Show the session time in the menu bar"]
        case .focus: return ["Daily goal", "Usual pace compares with", "Suggest activities from",
                             "Streak counts a day after", "New sessions start as",
                             "Keep sessions longer than", "Offer to continue for"]
        case .categories: return ["Categories", "New category", "Category name", "Icon", "Colour"]
        case .away:
            return ["Pause after no input for", "Ask me after", "End session after",
                    "Full-screen prompt after", "Remind me to take breaks", "After 20 minutes"]
        case .automatic:
            return ["Guess sessions from the app in front", "End a paused automatic session after",
                    "Celebrate milestones"]
        case .activities:
            return ["Use my activity rules", "Activity rules", "New rule", "Activity name",
                    "Start after", "Add application", "Running now"]
        case .tracking: return ["Apps shown in a card", "Recent app visits", "Record app usage"]
        case .appearance:
            return ["Appearance", "Interface density", "Show Story timestamps",
                    "Expand entry details by default", "Fold quiet stretches after"]
        case .data:
            // "Backup" is the always-shown row; the upgrade copy's row may be absent.
            return ["Privacy", "App use measured precisely since", "Backup",
                    "Reveal data folder"]
        case .advanced: return ["Version", "Build", "Recovery"]
        }
    }

    var mutableControlKeys: [SettingsControlKey] {
        switch self {
        case .general: return [.openAtLogin, .menuBarTime]
        case .focus: return [.dailyGoal, .paceWindow, .suggestionWindow, .streakMinimum, .defaultCategory,
                             .minimumSession, .continueWindow]
        case .categories: return [.categories]
        case .away: return [.idlePause, .breakThreshold, .longAwayCap, .fullPromptAfter, .reminders, .breakTiers]
        case .automatic: return [.automaticSessions, .automaticGap, .rewards]
        case .activities: return [.activityRuleAutomation, .activityRules]
        case .tracking: return [.railApps, .sessionsPerApp, .usageRecording]
        case .appearance: return [.appearance, .density, .timelineLabels, .entryDetails, .quietFold]
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

/// The pages down the left, the way System Settings and Xcode list theirs: a
/// tinted icon and a name per row, the open page held. One navigation
/// surface, so search sits above it rather than beside a second one.
struct SettingsSidebarList: View {
    let pages: [SettingsPage]
    @Binding var selected: SettingsPage
    @FocusState private var focused: SettingsPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(pages) { page in
                Button { selected = page } label: {
                    HStack(spacing: Tokens.Space.s) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(page.glyphColour)
                            .frame(width: 24, height: 24)
                            .background(Tokens.Palette.hue(page.hue),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityHidden(true)
                        Text(page.title)
                            .font(Tokens.Typography.control.weight(selected == page ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Tokens.Space.s)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .background(selected == page ? StoryStyle.well : Color.clear,
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.well))
                .focused($focused, equals: page)
                // The trait says "selected"; words in the label said it twice.
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(selected == page ? .isSelected : [])
            }
        }
        // Up and down arrows move between pages from a focused row, as in a
        // native sidebar, and the focus follows the page.
        .onMoveCommand { direction in
            let delta: Int
            switch direction {
            case .up: delta = -1
            case .down: delta = 1
            default: return
            }
            guard let next = (focused ?? selected).neighbour(in: pages, by: delta) else { return }
            selected = next
            focused = next
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings pages")
    }
}
