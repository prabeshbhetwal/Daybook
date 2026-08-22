import SwiftUI

/// The popover's hero: the goal ring beside the thing the user is doing — a
/// running timer, the start form, or the away question. One card, so the
/// figures that belong together sit together.
struct HeroCard: View {
    @ObservedObject var store: SessionStore
    var intentFocused: FocusState<Bool>.Binding
    var dense: Bool = false
    var twoColumn: Bool = true

    private var ringDiameter: CGFloat { dense ? 56 : 64 }

    var body: some View {
        HStack(alignment: .center, spacing: twoColumn ? Tokens.Space.l : Tokens.Space.m) {
            GoalRing(progress: store.goal.share,
                     diameter: ringDiameter,
                     lineWidth: dense ? 6 : 7,
                     label: "\(Int((min(store.goal.share, 9.99) * 100).rounded()))%",
                     isMet: store.goal.isMet)
                .explains("goal", "Focus time towards today's goal", goalDetail)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                if let away = store.pendingAway {
                    ResolveCard(away: away, range: store.pendingAwayRange, framed: false,
                                note: store.continuationNote,
                                onAnswer: { store.resolve($0) },
                                onReason: { store.resolve(.tookBreak, label: $0) })
                } else if store.isIdle {
                    idleBody
                } else {
                    runningBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: dense ? Tokens.Space.m : Tokens.Space.l)
    }

    // MARK: - Idle

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Ready when you are")
                .font(Tokens.Typography.title)
            IntentField(text: $store.intent) { store.start() }
                .focused(intentFocused)
                .frame(maxWidth: Tokens.formMeasure, alignment: .leading)
            HStack(spacing: Tokens.Space.s) {
                WorkTypePicker(selection: $store.workType)
                StartButton(fills: false) { store.start() }
            }
            if !store.quickStarts.isEmpty {
                QuickStartRow(items: store.quickStarts) { store.startQuick($0) }
            }
            goalCaption
        }
    }

    // MARK: - Running

    private var runningBody: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(Tokens.clock(store.elapsed))
                .font(Tokens.Typography.heroTimer)
                .contentTransition(.numericText())
                .foregroundStyle(store.isPaused ? AnyShapeStyle(.secondary)
                                                : AnyShapeStyle(.primary))
                .accessibilityLabel("Elapsed \(Tokens.duration(store.elapsed))")
                .explains("timer", "This stretch, not the day",
                          "Time since this stretch of work began — since you pressed "
                          + "Start, or since you came back and answered the card. It "
                          + "pauses itself after "
                          + "\(Int(FocusConstants.idlePauseThreshold / 60)) minutes without "
                          + "a keypress, so thinking time counts and lunch does not. The "
                          + "line beneath it is the same piece of work across every "
                          + "stretch today; the ring beside it is the whole day.")
            Text(store.isPaused ? "Paused · \(store.activeIntent)" : store.activeIntent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let summary = store.threadSummaryLine {
                Text(summary)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            goalCaption
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
                    Button("Stop") { store.stop() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                if store.isAutoSession {
                    Button("Undo") { store.undoAutoSession() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Discard this automatic session without recording it")
                }
            }
            .padding(.top, Tokens.Space.xs)
            if store.isAutoSession {
                Text("Started automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: Tokens.Space.s) {
                    IntentField(text: $store.intent) { store.start() }
                        .focused(intentFocused)
                    WorkTypePicker(selection: $store.workType)
                    StartButton(title: store.startWouldContinue ? "Continue this" : "Start new",
                                fills: false) { store.start() }
                }
            }
        }
    }

    // MARK: - Goal caption

    /// `2h 31m of 4h · 1h 42m behind usual`. The ring shows the share; this
    /// names the figures, and the tooltip on the ring explains them.
    private var goalCaption: some View {
        HStack(spacing: Tokens.Space.xs) {
            Text(Tokens.duration(store.goal.achieved))
                .font(.caption.weight(.medium).monospacedDigit())
            Text("of \(Tokens.duration(store.goal.goal))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.goal.isMet {
                Text("· Goal met")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else if let pace = paceNote {
                Text("· \(pace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var paceNote: String? {
        guard let ahead = store.goal.aheadBy else { return nil }
        if ahead >= 60 { return "\(Tokens.duration(ahead)) ahead of usual" }
        if ahead <= -60 { return "\(Tokens.duration(-ahead)) behind usual" }
        return "on your usual pace"
    }

    private var goalDetail: String {
        let base = "The ring fills as your focus sessions add up towards the goal you "
            + "set, counting only the minutes you were actually using the Mac inside "
            + "a session. Pausing, going Away or sitting idle stops it. "
        guard let typical = store.goal.typicalByNow else {
            return base + "Once there are a couple of weeks of history, the caption "
                + "compares today with a normal day."
        }
        return base + "On a normal day you would have about "
            + "\(Tokens.duration(typical)) done by this hour, which is what the caption "
            + "compares you with. 'Normal' means the middle day out of your last "
            + "\(FocusConstants.goalMedianWindowDays) that had any focus on them."
    }
}
