import SwiftUI

/// The top of the dashboard: the goal ring, the session and the day's three
/// headline figures in one band, so the first line of the page answers "how
/// is this day going" in a glance. On today the middle is the running
/// session — the stretch clock, the controls; on any other day it is that
/// day's focused total and nothing that moves. A past day shows only itself:
/// the running clock lives in the menu bar and on today, and the way back is
/// the *Today* button in the title band.
struct DashboardHero: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.xl) {
            ring
            Group {
                if store.isToday { today } else { pastDay }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            headline
        }
        .card(padding: Tokens.Space.l)
    }

    // MARK: - Ring: the selected day's goal

    private var ring: some View {
        let goal = store.selectedDayGoal
        return VStack(spacing: Tokens.Space.xs) {
            GoalRing(progress: goal.share, diameter: 120, lineWidth: 10,
                     label: Tokens.duration(goal.achieved),
                     isMet: goal.isMet,
                     labelFont: Font.system(size: 22, weight: .semibold, design: .rounded)
                         .monospacedDigit())
            Text("of \(Tokens.duration(goal.goal))")
                .font(Tokens.Typography.detail)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Middle, today: the session

    @ViewBuilder private var today: some View {
        if let away = store.pendingAway {
            ResolveCard(away: away, range: store.pendingAwayRange, framed: false,
                        note: store.continuationNote,
                        onAnswer: { store.resolve($0) },
                        onReason: { store.resolve(.tookBreak, label: $0) })
        } else if store.isIdle {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Ready when you are")
                    .font(Tokens.Typography.title)
                HStack(spacing: Tokens.Space.s) {
                    IntentField(text: $store.intent) { store.start() }
                        .frame(maxWidth: 260)
                    WorkTypePicker(selection: $store.workType)
                    StartButton(fills: false) { store.start() }
                }
                goalLine
            }
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(Tokens.clock(store.elapsed))
                    .font(Tokens.Typography.heroTimer)
                    .contentTransition(.numericText())
                    .foregroundStyle(store.isPaused ? AnyShapeStyle(.secondary)
                                                    : AnyShapeStyle(.primary))
                Text(store.activeSessionSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary = store.threadSummaryLine {
                    Text(summary)
                        .font(Tokens.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                goalLine
                HStack(spacing: Tokens.Space.s) {
                    if store.isAway {
                        Button("I'm back") { store.endAway() }
                            .buttonStyle(.borderedProminent)
                        Button("Stop") { store.stop() }
                    } else {
                        IconButton(systemImage: store.isPaused ? "play.fill" : "pause.fill",
                                   help: store.isPaused ? "Resume" : "Pause") {
                            store.togglePause()
                        }
                        IconButton(systemImage: "door.right.hand.open",
                                   help: "Away — stop the session and recording until you return") {
                            store.markAway()
                        }
                        Button("Stop") { store.stop() }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, Tokens.Space.xs)
            }
        }
    }

    /// `1h 10m to the goal · on your usual pace`, or `Goal met`.
    private var goalLine: some View {
        Text(goalText)
            .font(Tokens.Typography.detail)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var goalText: String {
        if store.goal.isMet { return "Goal met" }
        let remaining = max(0, store.goal.goal - store.goal.achieved)
        var text = "\(Tokens.duration(remaining)) to the goal"
        if let ahead = store.goal.aheadBy {
            if ahead >= 60 { text += " · \(Tokens.duration(ahead)) ahead of usual" }
            else if ahead <= -60 { text += " · \(Tokens.duration(-ahead)) behind usual" }
            else { text += " · on your usual pace" }
        }
        return text
    }

    // MARK: - Middle, a past day: what the day amounted to

    /// The day's focused total where today's clock sits, with what it was made
    /// of beneath it and how it ended against the goal — still figures, in the
    /// same place and type as the live ones, so the eye lands where it always
    /// does and finds that day.
    private var pastDay: some View {
        let focused = store.focusedForSelectedDay
        let tracked = store.trackedForSelectedDay
        let goal = store.selectedDayGoal
        let sessions = store.daySessions.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        let figure = focused > 0 ? focused : tracked
        let subtitle: String
        if focused > 0 {
            let count = Set(sessions.map(\.threadID)).count
            var parts = ["focused" + (count == 1 ? " in one session" : " in \(count) sessions")]
            if let first = sessions.map(\.start).min(), let last = sessions.map(\.end).max() {
                parts.append(Tokens.timeRange(first, last))
            }
            subtitle = parts.joined(separator: " · ")
        } else if tracked > 0 {
            var parts = ["at the Mac, no focus session"]
            if let first = store.timelineSegments.map(\.start).min(),
               let last = store.timelineSegments.map(\.end).max() {
                parts.append(Tokens.timeRange(first, last))
            }
            subtitle = parts.joined(separator: " · ")
        } else {
            subtitle = "Nothing recorded on this day"
        }
        let goalText: String? = {
            guard goal.goal > 0, focused > 0 else { return nil }
            if goal.isMet { return "Goal met" }
            return "\(Tokens.duration(goal.goal - goal.achieved)) short of the \(Tokens.duration(goal.goal)) goal"
        }()
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(Tokens.duration(figure))
                .font(Tokens.Typography.heroTimer)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let goalText {
                Text(goalText)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(goal.isMet ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Headline figures: the selected day's

    private var headline: some View {
        let tracked = store.isToday ? store.trackedToday : store.trackedForSelectedDay
        let focused = store.isToday ? store.todayTotal : store.focusedForSelectedDay
        let sessions = store.isToday ? store.sessionsToday : store.sessionsForSelectedDay
        let longest = store.isToday ? store.longestToday : store.longestForSelectedDay
        let delta = SessionStore.deltaLine(tracked, against: store.trackedYesterday,
                                           label: store.isToday ? "yesterday" : "the day before")
        return HStack(alignment: .top, spacing: Tokens.Space.xl) {
            figure("Tracked", Tokens.duration(tracked),
                   context: delta?.text,
                   tint: delta?.up == true ? Tokens.Palette.app(rank: 1) : nil)
            figure("Focused", Tokens.duration(focused),
                   context: tracked > 0 && focused > 0
                       ? "\(Int((focused / tracked * 100).rounded()))% of tracked"
                       : nil, tint: nil)
            figure("Sessions", "\(sessions)",
                   context: longest > 0 ? "longest \(Tokens.preciseDuration(longest))" : nil,
                   tint: nil)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func figure(_ label: String, _ value: String, context: String?, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: label)
            Text(value)
                .font(Tokens.Typography.stat)
                .contentTransition(.numericText())
            Text(context ?? " ")
                .font(Tokens.Typography.detail)
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
        .frame(minWidth: 96, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
