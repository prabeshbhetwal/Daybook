import SwiftUI
import Charts

// Small views over plain values — no store dependency — so the gallery can drive
// them directly from fixtures.

struct StreakBadge: View {
    let days: Int

    var body: some View {
        Label(days == 1 ? "1 day" : "\(days) days", systemImage: "flame.fill")
            .foregroundStyle(days > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .accessibilityLabel(days == 1 ? "1 day streak" : "\(days) day streak")
            // No `.help` here. The one caller wraps this in `.explains`, which
            // appears instantly; a system tooltip underneath it would fade in a
            // second later saying much the same thing.
    }
}

struct StartButton: View {
    var title: String = "Start Focus"
    /// The caller decides how wide. It used to force `maxWidth: .infinity`,
    /// which was right in a 320pt panel and absurd in a 560pt one.
    var fills: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: fills ? .infinity : nil)
                .padding(.horizontal, Tokens.Space.m)
                .padding(.vertical, 7)
                .background(Color.accentColor,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.control,
                                                 style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct LiveTimer: View {
    let seconds: TimeInterval
    let paused: Bool
    let intent: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(Tokens.clock(seconds))
                .font(Tokens.heroTimerFont)
                .foregroundStyle(paused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .accessibilityLabel("Elapsed \(Tokens.duration(seconds))")
            Text(paused ? "Paused · \(intent)" : intent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct IntentField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        TextField("What are you working on?", text: $text)
            .textFieldStyle(.plain)
            .font(.title3)
            .onSubmit(onSubmit)
            .accessibilityLabel("Session intent")
    }
}

/// A pull-down, not a pop-up.
///
/// `Picker(.menu)` is a *pop-up*: AppKit positions the list so the selected row
/// sits over the button. Pick the third of four and it needs two rows above the
/// button — and this button lives a few points below the menu bar, so the list
/// ran off the top of the screen and appeared scrolled, with "Deep work" hidden
/// behind a chevron. A `Menu` always opens downward from its label, so the list
/// is whole whichever item is selected and wherever the panel sits.
struct WorkTypePicker: View {
    @Binding var selection: WorkType

    var body: some View {
        Menu {
            ForEach(WorkType.startable, id: \.self) { type in
                Button { selection = type } label: {
                    Label(type.displayName, systemImage: type.symbolName)
                }
            }
        } label: {
            Label(selection.displayName, systemImage: selection.symbolName)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Work type, \(selection.displayName)")
    }
}

struct QuickStartRow: View {
    let items: [QuickStart]
    let onPick: (QuickStart) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Quick start")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s) {
                    ForEach(items) { item in
                        Button { onPick(item) } label: {
                            Label(item.name, systemImage: item.workType.symbolName)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Start \(item.name), \(item.workType.displayName)")
                    }
                }
            }
        }
    }
}

extension DayBar {
    /// All-zero bars draw nothing while the frame keeps its height — the
    /// "150pt of dead space" defect. The caller shows an empty state instead.
    static func hasData(_ bars: [DayBar]) -> Bool {
        bars.contains { $0.minutes > 0 }
    }
}

struct WeekChart: View {
    let bars: [DayBar]
    var height: CGFloat = 54

    var body: some View {
        if DayBar.hasData(bars) {
            // The x value must be the date, not the weekday letter: two days in
            // any seven share a first letter and Charts merges equal categorical
            // values, silently collapsing the week into five bars.
            Chart(bars) { bar in
                BarMark(x: .value("Day", bar.id, unit: .day),
                        y: .value("Minutes", bar.minutes))
                    .foregroundStyle(bar.isToday ? AnyShapeStyle(.tint)
                                                 : AnyShapeStyle(.quaternary))
                    .cornerRadius(3)
            }
            .chartYScale(domain: 0...max(60, bars.map(\.minutes).max() ?? 60))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: bars.map(\.id)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2)
                }
            }
            .frame(height: height)
            .accessibilityLabel("Focused minutes for the last seven days")
        } else {
            Text("No sessions this week yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: height, alignment: .leading)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Tokens.statNumberFont)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Tokens.Space.m)
        .accessibilityElement(children: .combine)
    }
}

/// Non-blocking resolution of a long absence, as a card: the grid inside a
/// frame, or bare when it already sits in another card.
struct ResolveCard: View {
    let away: TimeInterval
    var range: (start: Date, end: Date)?
    var framed: Bool = true
    var note: String?
    let onAnswer: (UserDecision) -> Void
    var onReason: ((String) -> Void)?

    var body: some View {
        let grid = AwayAnswerGrid(away: away, range: range, compact: true, note: note,
                                  onAnswer: onAnswer, onReason: onReason)
            .frame(maxWidth: .infinity, alignment: .leading)
        if framed {
            grid.card(padding: Tokens.Space.m)
        } else {
            grid
        }
    }
}

/// Observing wrapper for the menu bar label. A `Scene` body does not observe
/// an `ObservableObject`, so the label must be a `View` holding
/// `@ObservedObject` or it renders once, at launch, and never again.
struct MenuBarLabelView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        MenuBarLabel(state: store.state,
                     elapsed: store.elapsed,
                     needsAttention: store.pendingAway != nil,
                     goal: store.goal)
            .accessibilityLabel(store.state == .idle
                                ? "FocusContinuity, \(Int((store.goal.share * 100).rounded())) "
                                  + "percent of today's goal, no session running"
                                : "Current session \(Tokens.spent(store.elapsed))")
    }
}

/// The menu bar's ambient state: a goal ring always, elapsed while a session
/// runs, a pause mark when paused, a dot when a question is waiting.
struct MenuBarLabel: View {
    let state: SessionState
    let elapsed: TimeInterval
    let needsAttention: Bool
    var goal = GoalProgress(goal: FocusConstants.defaultDailyGoal, achieved: 0, typical: nil)

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let glyph = MenuBarGlyph.image(progress: goal.share,
                                              paused: state.isPaused,
                                              attention: needsAttention,
                                              isMet: goal.isMet) {
                Image(nsImage: glyph)
            } else {
                Image(systemName: needsAttention ? "exclamationmark.circle.fill" : "infinity")
            }
            if state != .idle {
                Text(Tokens.duration(elapsed))
                    .font(Tokens.menuBarFont)
            }
        }
        .foregroundStyle(state.isPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}
