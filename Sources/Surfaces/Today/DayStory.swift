import SwiftUI

/// The day told top to bottom: every session, rest and unresolved gap as one
/// entry on a single rule. A gap is an entry too, so unrecorded time is part of
/// the day rather than a hole in it. Each entry opens in place — nothing here
/// navigates away.
struct DayStory: View {
    @ObservedObject var store: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Entries the reader has opened. Local: it is a reading aid, not state the
    /// product remembers.
    @StateObject private var opened = SetBox()

    /// The gutter that carries the clock times, and the rule beside it.
    private let timeColumn: CGFloat = 62
    private let railColumn: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(store.daySessions.enumerated()), id: \.element.id) { index, entry in
                row(entry, isFirst: index == 0,
                    isLast: index == store.daySessions.count - 1 && !hasAwayQuestion)
            }
            if hasAwayQuestion { awayRow }
            if store.daySessions.isEmpty && !hasAwayQuestion { empty }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasAwayQuestion: Bool { store.isToday && store.pendingAway != nil }

    // MARK: - One entry

    @ViewBuilder private func row(_ entry: DayEntry, isFirst: Bool, isLast: Bool) -> some View {
        switch entry {
        case .session(let session):
            storyRow(time: session.start,
                     tint: Tokens.Palette.workType(session.workType),
                     dotSize: session.isRunning ? 13 : 11,
                     isFirst: isFirst, isLast: isLast) {
                SessionEntryCard(session: session,
                                 apps: store.appRanks(within: session.spans),
                                 isOpen: opened.ids.contains(session.id),
                                 clock: session.isRunning ? Tokens.clock(store.elapsed) : nil,
                                 onToggle: { toggle(session.id) })
            }
        case .rest(let rest):
            storyRow(time: rest.start,
                     tint: Tokens.Palette.workType(.breakTime),
                     dotSize: 7,
                     isFirst: isFirst, isLast: isLast) {
                RestEntryRow(rest: rest)
            }
        }
    }

    /// The away question sits in the story where the absence happened, so the
    /// answer is given in context rather than in a separate surface.
    @ViewBuilder private var awayRow: some View {
        if let away = store.pendingAway {
            storyRow(time: store.pendingAwayRange?.start ?? Date(),
                     tint: Tokens.Colour.attention,
                     dotSize: 9,
                     isFirst: store.daySessions.isEmpty, isLast: true) {
                AwayEntryCard(away: away,
                              range: store.pendingAwayRange,
                              note: store.continuationNote,
                              onAnswer: { store.resolve($0) },
                              onReason: { store.resolve(.tookBreak, label: $0) })
            }
        }
    }

    private func storyRow<Content: View>(time: Date,
                                         tint: Color,
                                         dotSize: CGFloat,
                                         isFirst: Bool,
                                         isLast: Bool,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(Tokens.timeOfDayOnly(time))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: timeColumn, alignment: .trailing)
                .padding(.top, 14)
                .accessibilityHidden(true)
            rail(tint: tint, dotSize: dotSize, isFirst: isFirst, isLast: isLast)
                .frame(width: railColumn)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Tokens.Space.m)
        }
    }

    /// One continuous rule down the story, with this entry's dot on it. The
    /// first and last rows stop the rule at their own dot so the line has ends
    /// rather than running into the page.
    private func rail(tint: Color, dotSize: CGFloat, isFirst: Bool, isLast: Bool) -> some View {
        GeometryReader { geometry in
            let dotCentre: CGFloat = 19
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Tokens.Colour.line)
                    .frame(width: 2)
                    .padding(.top, isFirst ? dotCentre : 0)
                    .padding(.bottom, isLast ? max(0, geometry.size.height - dotCentre) : 0)
                Circle()
                    .fill(tint)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(Circle().strokeBorder(Tokens.Colour.surface, lineWidth: 3))
                    .offset(y: dotCentre - dotSize / 2)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    private var empty: some View {
        Text("Nothing recorded on this day yet.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, Tokens.Space.m)
    }

    private func toggle(_ id: UUID) {
        withAnimation(Tokens.Motion.animation(Tokens.Motion.rise, reduceMotion: reduceMotion)) {
            if opened.ids.contains(id) { opened.ids.remove(id) } else { opened.ids.insert(id) }
        }
    }
}

/// One focus session in the story. Closed it is a title, a type and a duration;
/// opened it shows the apps that made it up and what the app can say about its
/// shape. A running session carries the live clock instead of a total.
struct SessionEntryCard: View {
    let session: DaySession
    let apps: [AppRank]
    let isOpen: Bool
    let clock: String?
    let onToggle: () -> Void

    private var tint: Color { Tokens.Palette.workType(session.workType) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                        Text(session.name.isEmpty ? session.workType.displayName : session.name)
                            .font(Tokens.Typography.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: Tokens.Space.s)
                        Text(clock ?? Tokens.preciseDuration(session.worked))
                            .font(.callout.weight(clock == nil ? .regular : .semibold)
                                .monospacedDigit())
                            .foregroundStyle(clock == nil ? AnyShapeStyle(.secondary)
                                                          : AnyShapeStyle(tint))
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    HStack(spacing: Tokens.Space.s) {
                        Text(session.workType.displayName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.14), in: Capsule())
                            .foregroundStyle(tint)
                        Text(session.isRunning
                             ? "running now"
                             : Tokens.timeRange(session.start, session.end))
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                        if session.stretches > 1 {
                            Text("· \(session.stretches) stretches")
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(Tokens.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen { detail }
        }
        .background(Tokens.Colour.surface,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
            .strokeBorder(session.isRunning ? tint.opacity(0.45) : Tokens.Colour.line,
                          lineWidth: session.isRunning ? 1.5 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isOpen ? "Hide this session's detail" : "Show this session's detail")
    }

    private var accessibilityLabel: String {
        var parts = [session.name.isEmpty ? session.workType.displayName : session.name,
                     session.workType.displayName]
        parts.append(session.isRunning
                     ? "running since \(Tokens.timeOfDayOnly(session.start))"
                     : Tokens.timeRange(session.start, session.end))
        parts.append(Tokens.spent(session.worked))
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var detail: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Divider()
            if apps.isEmpty {
                Text("No app use was recorded inside this session.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            } else {
                Text("Apps in this session")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                ForEach(Array(apps.prefix(4).enumerated()), id: \.element.id) { index, app in
                    AppUsageRow(appName: app.appName, bundleID: app.bundleID,
                                rank: index, seconds: app.total, share: app.share,
                                layout: .compact)
                }
                if apps.count > 4 {
                    Text("\(apps.count - 4) more app\(apps.count - 4 == 1 ? "" : "s") "
                         + "used inside this session")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.bottom, Tokens.Space.m)
    }
}

/// Rest is not work, so it is a quiet row rather than a card: named where the
/// user named it, and never coloured like a session.
struct RestEntryRow: View {
    let rest: RestEntry

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Text("\(rest.name) — rest, not counted as focus")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: Tokens.Space.s)
            Text(Tokens.preciseDuration(rest.length))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rest.name), rest, \(Tokens.spent(rest.length)), "
                            + Tokens.timeRange(rest.start, rest.end))
    }
}

/// The unresolved gap, asked where it happened. The answers are the existing
/// canonical decisions; this is a placement, not a new verdict.
struct AwayEntryCard: View {
    let away: TimeInterval
    let range: (start: Date, end: Date)?
    let note: String?
    let onAnswer: (UserDecision) -> Void
    let onReason: (String) -> Void

    var body: some View {
        AwayAnswerGrid(away: away, range: range, note: note,
                       onAnswer: onAnswer, onReason: onReason)
            .padding(Tokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colour.attention.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.attention.opacity(0.35)))
    }
}
