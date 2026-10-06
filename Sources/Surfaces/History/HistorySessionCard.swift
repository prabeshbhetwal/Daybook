import SwiftUI

/// One session a search found, as a card on the spine: what, which category,
/// how long and when. Under a picked app it shows where that app was in
/// front and its share of the session; under a search, the session's apps
/// as one bar and the note line that matched.
struct HistorySessionRow: View {
    let session: DaySession
    /// The day this card lists the session under.
    let day: Date
    /// The session's apps, busiest first.
    let apps: [AppRank]
    let note: String?
    /// The picked app's use in this session, when an app is the filter.
    var use: HistoryAppLens.SessionUse?
    var appName: String?
    var bundleID: String?
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        HistorySpineItem(time: Tokens.timeOfDayOnly(session.start),
                         dot: .filled(Tokens.Palette.workType(session.workType))) {
            Button(action: onSelect) { card }
                .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: StoryStyle.entryRadius))
                .padding(.bottom, Tokens.Space.s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spokenLabel(session))
                .accessibilityValue(DurationText.spoken(in: spokenDetail))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
        .id(HistorySessionPick(thread: session.threadID, day: day).scrollID)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(session.workType.sessionTitle(named: session.name))
                    .font(Tokens.Typography.rowTitle)
                    .lineLimit(1)
                // An unnamed session's title is its category already.
                if !session.name.isEmpty { WorkTypeChip(workType: session.workType) }
                Spacer(minLength: Tokens.Space.s)
                Text(durations: session.isRunning ? "in progress" : Tokens.duration(session.worked))
                    .font(Tokens.Typography.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Text(subline)
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let note, !note.isEmpty {
                Text("“\(note)”")
                    .font(Tokens.Typography.body)
                    .lineLimit(2)
            }
            if let use {
                lensDetail(use)
            } else if !apps.isEmpty {
                appMix
            }
        }
        .padding(StoryStyle.entryInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.card, in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous)
            .strokeBorder(isSelected ? Tokens.Colour.focus.opacity(0.55) : Tokens.Colour.line,
                          lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
        .contentShape(Rectangle())
    }

    /// `1:54 am – 3:13 am · mostly Dia, with Gemini and ChatGPT`. Under a
    /// picked app the list leaves that app out: the card says it below.
    private var subline: String {
        let range = Tokens.timeRange(session.start, session.end)
        guard use != nil else { return range }
        let others = apps.filter { $0.bundleID != bundleID && $0.total >= 60 }
        guard let first = others.first else { return range }
        let rest = others.dropFirst().prefix(2).map(\.appName)
        if first.share > 0.5 {
            return range + " · mostly \(first.appName)" + (rest.isEmpty ? "" : ", with \(Self.list(rest))")
        }
        return range + " · with \(Self.list(others.prefix(3).map(\.appName)))"
    }

    /// Where the app was in front along the session, and its share of it.
    private func lensDetail(_ use: HistoryAppLens.SessionUse) -> some View {
        let share = DurationText.percent(use.share)
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HistoryAppMomentsBar(use: use)
                .padding(.top, Tokens.Space.s)
            HStack(spacing: Tokens.Space.s) {
                Text(Tokens.timeOfDayOnly(use.span.start))
                Spacer(minLength: Tokens.Space.xs)
                if let first = use.moments.first, let last = use.moments.last {
                    Text((appName.map { "\($0) in front " } ?? "In front ") + Tokens.timeRange(first.start, last.end))
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.xs)
                Text(Tokens.timeOfDayOnly(use.span.end))
            }
            .font(Tokens.Typography.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack(spacing: Tokens.Space.s) {
                if let bundleID { AppIcon(bundleID: bundleID, size: 16, appName: appName ?? "") }
                Text(durations: Self.figure(use.seconds))
                    .font(Tokens.Typography.label)
                Text("of this session · \(share)")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Tokens.Space.xs)
        }
    }

    /// The session's apps as one bar: the three busiest, then the rest.
    private var appMix: some View {
        let top = Array(apps.prefix(3))
        let restShare = max(0, 1 - top.reduce(0) { $0 + $1.share })
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, app in
                        Rectangle().fill(Tokens.Palette.app(rank: index))
                            .frame(width: max(2, geometry.size.width * app.share))
                    }
                    if restShare > 0.005 {
                        Rectangle().fill(Tokens.Palette.untracked.opacity(0.5))
                    }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())
            .padding(.top, Tokens.Space.s)
            .accessibilityHidden(true)
            HStack(spacing: Tokens.Space.m) {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, app in
                    legend(Tokens.Palette.app(rank: index), "\(app.appName) \(Self.percent(app.share))")
                }
                if restShare > 0.005 {
                    legend(Tokens.Palette.untracked.opacity(0.5), "Others \(Self.percent(restShare))")
                }
            }
        }
    }

    private func legend(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous).fill(colour).frame(width: 9, height: 9)
            Text(label).font(Tokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var spokenDetail: String {
        if let use, let appName {
            return "\(appName) \(Self.figure(use.seconds)) of this session"
        }
        return Self.detail(apps: apps.map(\.appName), note: note) ?? ""
    }

    /// Whole minutes, or seconds under one: a 45-second visit is not `0m`.
    static func figure(_ seconds: TimeInterval) -> String {
        seconds >= 60 ? Tokens.duration(seconds) : Tokens.preciseDuration(seconds)
    }

    static func percent(_ share: Double) -> String { DurationText.percent(share) }

    /// `Dia`, `Dia and Gemini`, `Dia, Gemini and ChatGPT`.
    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
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
