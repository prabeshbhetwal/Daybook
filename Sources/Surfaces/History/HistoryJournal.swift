import SwiftUI
import AppKit

/// History below the chrome: the tree, and beside it the rail for the
/// deepest open row.
struct HistoryWorkspace: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @ObservedObject var settings: SettingsModel
    var scrolls = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HistoryTree(store: store, navigation: navigation, scrolls: scrolls)
            Divider()
            Group {
                if scrolls {
                    ScrollView { HistoryJournalRail(store: store, navigation: navigation, settings: settings) }
                } else {
                    HistoryJournalRail(store: store, navigation: navigation, settings: settings)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: StoryLayout.railWidth)
            .background(StoryStyle.rail)
        }
        .background(Tokens.Colour.ground)
    }
}

/// A month's name, for the search results' month lines.
enum HistoryMonthHeader {
    static func title(_ start: Date) -> String {
        DateFormats.australian("MMMM yyyy").string(from: start)
    }
}

/// One bar per calendar day, height by focus. The dates are in the rows
/// below, so the bars carry no labels.
struct HistoryMonthBars: View {
    let daily: [TimeInterval]

    var body: some View {
        let peak = max(daily.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(daily.enumerated()), id: \.offset) { _, seconds in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(seconds > 0 ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(StoryStyle.line))
                    .frame(maxWidth: .infinity)
                    .frame(height: seconds > 0 ? max(3, 18 * seconds / peak) : 2)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// A day's title and whether its figure is said on its row.
enum HistoryDayHeader {
    /// The day's focus, unless the day is one finished session and nothing else
    /// and its row shows the same figure: then the header would say it twice.
    /// A running session's row says "in progress", so the header keeps the figure.
    static func showsTotal(day: JournalDay, rows: [DayEntry]) -> Bool {
        guard day.focused > 0 else { return false }
        if rows.count == 1, case .session(let session) = rows[0], !session.isRunning,
           Tokens.duration(day.focused) == Tokens.duration(session.worked) { return false }
        return true
    }

    static func title(_ date: Date, isToday: Bool) -> String {
        isToday ? "Today" : DateFormats.australian("EEE d MMM").string(from: date)
    }
}

/// One session: when, what, which category, how long; then the apps it used
/// and the first line of its note.
struct HistorySessionRow: View {
    let session: DaySession
    let apps: [String]
    let note: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Circle()
                    .fill(Tokens.Palette.workType(session.workType))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text(Tokens.timeRange(session.start, session.end))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(session.workType.sessionTitle(named: session.name))
                            .font(Tokens.Typography.rowTitle.weight(.medium))
                            .lineLimit(1)
                        // An unnamed session's title is its category already.
                        if !session.name.isEmpty { WorkTypeChip(workType: session.workType) }
                        Spacer(minLength: Tokens.Space.s)
                        Text(durations: session.isRunning ? "in progress" : Tokens.duration(session.worked))
                            .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                    }
                    if let detail = Self.detail(apps: apps, note: note) {
                        Text(detail)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, Tokens.Space.xs)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(session))
        .accessibilityValue(Self.detail(apps: apps, note: note) ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(HistoryTree.keyboardHint)
    }

    /// `8:30 am – 11:35 am, Refactor, Deep work, 2 hours 5 minutes`.
    static func spokenLabel(_ session: DaySession) -> String {
        var parts = [Tokens.timeRange(session.start, session.end)]
        if !session.name.isEmpty { parts.append(session.name) }
        parts.append(session.workType.displayName)
        parts.append(session.isRunning ? "in progress" : Tokens.spent(session.worked))
        return parts.joined(separator: ", ")
    }

    /// `Xcode, Terminal, Safari · “fixed the parser”`.
    static func detail(apps: [String], note: String?) -> String? {
        var parts: [String] = []
        if !apps.isEmpty { parts.append(apps.prefix(3).joined(separator: ", ")) }
        if let note, !note.isEmpty { parts.append("“\(note)”") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A recorded break between sessions, named when it was named.
struct HistoryBreakRow: View {
    let rest: RestEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Circle()
                .fill(Tokens.Palette.warmGrey.opacity(0.55))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(Tokens.timeRange(rest.start, rest.end))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(rest.name.isEmpty ? "Break" : rest.name)
                .font(Tokens.Typography.metadata)
            Spacer(minLength: Tokens.Space.s)
            Text(durations: Tokens.duration(rest.length))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, HistoryRowLayout.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Tokens.timeRange(rest.start, rest.end)), \(StoryBreakRow.label(rest.name)), "
                            + Tokens.spent(rest.length))
    }
}
