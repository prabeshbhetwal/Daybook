import SwiftUI

/// The words about one app in one session, and about the app's whole record,
/// kept apart from the views so the checks read them without rendering.
enum HistoryAppLensText {
    /// `3 visits · longest 5m`.
    static func visits(_ use: HistoryAppLens.SessionUse) -> String {
        let visits = HistoryAppLens.merged(use.moments)
        let longest = visits.map(\.duration).max() ?? 0
        let count = visits.count == 1 ? "1 visit" : "\(visits.count) visits"
        return "\(count) · longest \(HistorySessionRow.figure(longest))"
    }

    /// `More than its typical session (6m, the middle of 23) · 3rd longest`.
    static func comparison(_ use: HistoryAppLens.SessionUse, in lens: HistoryAppLens) -> String? {
        guard lens.sessions.count > 1, let typical = lens.typicalSessionSeconds else { return nil }
        let figure = HistorySessionRow.figure(typical)
        let middle = "\(figure), the middle of \(lens.sessions.count)"
        let relation: String
        switch StoryRailFigures.minutes(use.seconds) - StoryRailFigures.minutes(typical) {
        case 0: relation = "About its typical session (\(middle))"
        case let difference where difference > 0: relation = "More than its typical session (\(middle))"
        default: relation = "Less than its typical session (\(middle))"
        }
        return relation + " · " + ordinal(lens.rank(of: use)) + " longest"
    }

    /// `All time in Deep work sessions: 3h 10m of 26h 55m`.
    static func categoryLine(_ workType: WorkType, in lens: HistoryAppLens) -> String {
        let inType = lens.inSessionByType[workType] ?? 0
        return "All time in \(workType.displayName) sessions: \(HistorySearchText.lensFigure(inType, in: lens)) of "
            + HistorySearchText.lensTotal(lens)
    }

    /// `Last 7 days 1h 2m · last 30 days 4h 10m`.
    static func recent(_ lens: HistoryAppLens, today: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: today)
        let week = calendar.date(byAdding: .day, value: -6, to: day) ?? day
        let month = calendar.date(byAdding: .day, value: -29, to: day) ?? day
        return "Last 7 days \(HistorySessionRow.figure(lens.total(since: week))) · "
            + "last 30 days \(HistorySessionRow.figure(lens.total(since: month)))"
    }

    /// Said when part of the whole comes from before the record was accurate.
    static func legacyNote(_ lens: HistoryAppLens) -> String? {
        guard let from = lens.accurateFrom, lens.legacy >= 60 else { return nil }
        return "\(Tokens.duration(lens.legacy)) of this is from before \(Tokens.longDate(from)), "
            + "when app use was recorded even with nobody at the Mac."
    }

    static func ordinal(_ number: Int) -> String {
        let tens = number % 100
        let suffix: String
        if (11...13).contains(tens) {
            suffix = "th"
        } else {
            switch number % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(number)\(suffix)"
    }
}

/// The picked app's part in the picked session, from the same figures as the
/// session's card: its time and share, where it fell, how this session
/// compares with the app's others, and its time in sessions of this kind.
struct HistoryAppSessionTile: View {
    let use: HistoryAppLens.SessionUse
    let lens: HistoryAppLens
    let appName: String

    var body: some View {
        StoryTile(title: "\(appName) in this session", trailing: nil) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                AppIcon(bundleID: lens.bundleID, size: 16.zoomed, appName: appName)
                    .alignmentGuide(.firstTextBaseline) { [lift = 3.zoomed] in $0[.bottom] - lift }
                Text(durations: HistorySessionRow.figure(use.seconds))
                    .font(Tokens.Typography.heading.monospacedDigit())
                Text("· \(DurationText.percent(use.share)) of the session")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
            HistoryAppMomentsBar(use: use)
            line(HistoryAppLensText.visits(use))
            if let comparison = HistoryAppLensText.comparison(use, in: lens) { line(comparison) }
            line(HistoryAppLensText.categoryLine(use.workType, in: lens))
        }
    }

    private func line(_ text: String) -> some View {
        Text(durations: text)
            .font(Tokens.Typography.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
