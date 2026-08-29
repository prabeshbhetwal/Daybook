import SwiftUI

/// The Today header's pure day-scoped copy. `dayOffset` is explicit so a
/// preview or injected clock never falls back to the host's real calendar when
/// deciding whether the selected day is Today or Yesterday.
struct TodayPresentation: Equatable {
    let title: String
    let subtitle: String
    let showsTodayReset: Bool

    init(day: Date, focused: TimeInterval, sessions: Int, dayOffset: Int) {
        switch dayOffset {
        case 0: title = "Today"
        case 1: title = "Yesterday"
        default: title = Tokens.dayLabel(day)
        }

        var parts = [Tokens.longDate(day)]
        if focused > 0 { parts.append("\(Tokens.duration(focused)) focused") }
        if sessions > 0 {
            parts.append(sessions == 1 ? "1 session" : "\(sessions) sessions")
        }
        subtitle = parts.joined(separator: " · ")
        showsTodayReset = dayOffset > 0
    }
}

/// One day title and the only navigation that can change its scope. The global
/// tab rail is deliberately absent from this component: switching tabs must not
/// silently answer a different date when the user returns.
struct TodayHeader: View {
    @ObservedObject var store: SessionStore
    @StateObject private var calendarShown = BoolBox()

    private var presentation: TodayPresentation {
        TodayPresentation(
            day: store.selectedDay,
            focused: store.isToday ? store.todayTotal : store.focusedForSelectedDay,
            sessions: store.isToday ? store.sessionsToday : store.sessionsForSelectedDay,
            dayOffset: store.dayOffset)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(Tokens.Typography.pageTitle)
                Text(presentation.subtitle)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.l)
            dayControls
        }
        .accessibilityElement(children: .contain)
    }

    private var dayControls: some View {
        HStack(spacing: Tokens.Space.s) {
            IconButton(systemImage: "chevron.left", help: "Previous day") {
                store.stepDay(by: -1)
            }
            .opacity(store.canStepBack ? 1 : 0.35)
            .disabled(!store.canStepBack)

            Button { calendarShown.value.toggle() } label: {
                Label(store.dayLabel, systemImage: "calendar")
                    .font(Tokens.Typography.tabLabel)
                    .padding(.horizontal, Tokens.Space.m)
                    .frame(height: 28)
                    .background(Tokens.Colour.elevated, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Pick a date")
            .popover(isPresented: Binding(get: { calendarShown.value },
                                          set: { calendarShown.value = $0 })) {
                DayPickerCalendar(
                    selected: store.selectedDay,
                    earliest: store.earliestSelectableDay,
                    goal: store.goal.goal,
                    facts: { store.dayFacts(inMonthOf: $0) }) { day in
                        store.selectDate(day)
                        calendarShown.value = false
                    }
            }

            IconButton(systemImage: "chevron.right", help: "Next day") {
                store.stepDay(by: 1)
            }
            .opacity(store.canStepForward ? 1 : 0.35)
            .disabled(!store.canStepForward)

            if presentation.showsTodayReset {
                Button("Today") { store.goToToday() }
                    .buttonStyle(.plain)
                    .font(Tokens.Typography.tabLabel)
                    .foregroundStyle(Tokens.Colour.focus)
                    .padding(.horizontal, Tokens.Space.s)
                    .frame(height: 28)
                    .background(Tokens.Colour.focus.opacity(0.10), in: Capsule())
                    .help("Return to the current day")
            }
        }
    }
}
