import SwiftUI

enum StoryChromeFocus: Hashable {
    case session
    case settings
}

/// The window's one chrome row, in the design's order: clearance for the native
/// traffic lights, the scope, the period it resolves to, the live session, and
/// Settings. It never scrolls and it is the only global navigation.
enum ChromeSessionControl {
    /// The chrome's control is a way in to the strip, not a second copy of it.
    /// Idle, both said "Start focus" for two different acts. Running, both
    /// ticked the same clock — the chrome's at 12pt and the strip's at 23pt,
    /// one row apart. Either way the strip is the fuller view, so whenever it
    /// is on screen the chrome stands down.
    static func isShown(stripVisible: Bool) -> Bool { !stripVisible }
}

struct StoryChromeBar: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    /// Whether the session strip is on screen. It carries the real Start
    /// focus; the chrome's only reveals it, so both showing at once offers the
    /// same words for two different acts.
    var sessionControlsVisible = false
    @FocusState private var focusedControl: StoryChromeFocus?
    @StateObject private var gearHovered = BoolBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A scope pill is the target floor plus the container's 3pt inset each side.
    static let controlRowHeight: CGFloat = AccessibilityMetrics.minimumTargetSize + 6
    /// Holds the chevrons still across "Today", "Wed 30 Sep", "28 Dec – 3 Jan"
    /// and "September 2026"; a rarer label grows the column for its stay.
    static let periodLabelWidth: CGFloat = 150

    var body: some View {
        HStack(spacing: Tokens.Space.l) {
            // The real window controls live here; the bar must not draw its own.
            Color.clear
                .frame(width: MainWindowChrome.trafficLightClearance, height: 1)
                .accessibilityHidden(true)
            backSlot
            workspaceControls
                .coachAnchor(.scopePills)
            if ChromeSessionControl.isShown(stripVisible: sessionControlsVisible) {
                StorySessionControl(store: store,
                                    focus: $focusedControl,
                                    onDetails: {
                                        navigation.performSessionControlsAction(.timerPill)
                                    })
                    .transition(Tokens.Motion.transition(
                        .opacity.combined(with: .scale(scale: 0.9)), reduceMotion: reduceMotion))
                    .coachAnchor(.sessionControl)
            }
            Button { navigation.openSheet(.settings) } label: {
                Image(systemName: "gearshape")
                    .font(Tokens.Typography.tabLabel)
                    .symbolRenderingMode(.hierarchical)
                    // A gear that turns a little under the pointer is a gear.
                    .rotationEffect(.degrees(gearHovered.value ? 30 : 0))
                    .animation(Tokens.Motion.animation(Tokens.Motion.release, reduceMotion: reduceMotion),
                               value: gearHovered.value)
                    .frame(width: AccessibilityMetrics.minimumTargetSize,
                           height: AccessibilityMetrics.minimumTargetSize)
                    .background(Tokens.Colour.elevated, in: Circle())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PressableStyle())
            .onHover { gearHovered.value = $0 }
            .focused($focusedControl, equals: .settings)
            .help("Settings")
            .accessibilityLabel("Settings")
            .coachAnchor(.settings)
        }
        // The row is as tall as the scope control whether or not the scope
        // control is in it. History has none, and the bar shrank by six
        // points on entry, taking the divider and the page with it.
        .frame(minHeight: Self.controlRowHeight)
        .padding(.horizontal, Tokens.Space.l)
        .padding(.vertical, Tokens.Space.s)
        .background(StoryStyle.canvas)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: sessionControlsVisible)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: navigation.workspace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Toolbar")
        .onChange(of: navigation.focusRestorationRequest) { target in
            guard let target else { return }
            switch target {
            case .sessionControls: focusedControl = .session
            case .settings: focusedControl = .settings
            }
            navigation.consumeFocusRestorationRequest()
        }
    }

    /// The way back, in a slot that exists in every workspace. "‹ Story" used
    /// to be inserted in front of the scope pills on Insights and History, so
    /// the pills — and everything after them — moved right by its width and
    /// back again on return. The slot is the width of one round button; Story
    /// leaves it empty, and the pills sit in the same place in every view.
    private var backSlot: some View {
        ZStack {
            if navigation.workspace != .story {
                IconButton(systemImage: "chevron.left", help: "Back to Story") {
                    navigation.returnToStory()
                }
                .accessibilityLabel("Return to Story")
                .transition(Tokens.Motion.transition(
                    .opacity.combined(with: .scale(scale: 0.8)), reduceMotion: reduceMotion))
            }
        }
        .frame(width: AccessibilityMetrics.minimumTargetSize,
               height: AccessibilityMetrics.minimumTargetSize)
    }

    /// Every workspace lays out the same three columns — context, period,
    /// links — between the same spacers, and the links sit against the session
    /// control, so a change of workspace changes words, not positions. The bar
    /// holds controls and the way back; a workspace names itself in its page.
    @ViewBuilder private var workspaceControls: some View {
        switch navigation.workspace {
        case .story:
            // The story is a day; how far back to look is History's.
            Spacer(minLength: Tokens.Space.s)
            periodNavigation
                .coachAnchor(.periodNav)
            Spacer(minLength: Tokens.Space.s)
            crossLinks
        case .history:
            // History reads how far back the reader asks; its bars group by
            // day, week or month to suit. A span picked on the calendar
            // selects none of these.
            ScopePillRow(titles: HistoryRange.allCases.map(\.title),
                         selectedIndex: Binding(
                            get: { navigation.historyRange.flatMap { HistoryRange.allCases.firstIndex(of: $0) } ?? -1 },
                            set: { navigation.selectHistoryRange(HistoryRange.allCases[$0]) }),
                         controlLabel: "History range")
            Spacer(minLength: Tokens.Space.s)
            insightNavigation
                .coachAnchor(.periodNav)
            Spacer(minLength: Tokens.Space.s)
            // No "History" label and no search button: the label named the
            // page being read beside its back button, and the search field
            // heads the page itself (⌘F puts the cursor in it).
        }
    }

    /// The way to History, as a link. Navigation belongs in the chrome; it
    /// sat below every rail card, so reaching it meant scrolling past the
    /// content first. History's own bar has the back button instead.
    private var crossLinks: some View {
        Button("History") { navigation.open(tab: .review) }
            .buttonStyle(StoryLinkStyle())
    }

    /// History's period control: arrows page by the range's length, and the
    /// label opens the calendar to pick a span of its own, first day then
    /// last. Back stops at the first day on record; there is nothing before it.
    private var insightNavigation: some View {
        HStack(spacing: Tokens.Space.s) {
            IconButton(systemImage: "chevron.left", help: "Earlier") {
                navigation.pageInsights(by: -1)
            }
            .disabled(!navigation.insightCanPageBack)
            Button { historyCalendarShown.value.toggle() } label: {
                HStack(spacing: Tokens.Space.xs) {
                    Text(navigation.insightWindowLabel)
                        .font(Tokens.Typography.rowTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(Tokens.Typography.microLabel.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Tokens.Space.s)
                .frame(minWidth: Self.periodLabelWidth, minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle())
            .accessibilityLabel("\(navigation.insightWindowLabel), History period. Opens the calendar to pick a span.")
            .popover(isPresented: Binding(get: { historyCalendarShown.value },
                                          set: { historyCalendarShown.value = $0 }),
                     arrowEdge: .bottom) {
                DayPickerCalendar(
                    range: shownHistorySpan,
                    earliest: store.earliestSelectableDay,
                    goal: store.goal.goal,
                    facts: { store.dayFacts(inMonthOf: $0) }) { start, end in
                        navigation.setCustomHistoryRange(start, end)
                        // The first click marks a start; the second completes it.
                        if start != end { historyCalendarShown.value = false }
                    }
            }
            IconButton(systemImage: "chevron.right", help: "Later") {
                navigation.pageInsights(by: 1)
            }
            .disabled(!navigation.insightCanPageForward)
        }
    }

    @StateObject private var historyCalendarShown = BoolBox()

    /// The days History shows, as the calendar paints them.
    private var shownHistorySpan: ClosedRange<Date> {
        let calendar = Calendar.current
        guard let window = navigation.insightWindow,
              let last = calendar.date(byAdding: .day, value: -1, to: window.end) else {
            return navigation.insightAnchor...navigation.insightAnchor
        }
        return calendar.startOfDay(for: window.start)...calendar.startOfDay(for: max(window.start, last))
    }

    private var periodNavigation: some View {
        HStack(spacing: Tokens.Space.s) {
            IconButton(systemImage: "chevron.left", help: stepHelp(back: true)) { step(-1) }
                .disabled(!canStepBack)
            // The period's name is the way to the calendar: click it and the
            // month opens, the same map the day picker draws, with each day's
            // focus under its date. Picking a day reads that day.
            Button { calendarShown.value.toggle() } label: {
                HStack(spacing: Tokens.Space.xs) {
                    Text(periodLabel)
                        .font(Tokens.Typography.rowTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(Tokens.Typography.microLabel.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Tokens.Space.s)
                .frame(minWidth: Self.periodLabelWidth, minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.well))
            .help("Open the calendar")
            .accessibilityLabel("\(periodLabel), selected period. Opens the calendar.")
            .popover(isPresented: Binding(get: { calendarShown.value },
                                          set: { calendarShown.value = $0 }),
                     arrowEdge: .bottom) {
                DayPickerCalendar(
                    selected: store.selectedDay,
                    earliest: store.earliestSelectableDay,
                    goal: store.goal.goal,
                    facts: { store.dayFacts(inMonthOf: $0) }) { day in
                        navigation.jumpToDay(day)
                        calendarShown.value = false
                    }
            }
            IconButton(systemImage: "chevron.right", help: stepHelp(back: false)) { step(1) }
                .disabled(!canStepForward)
        }
    }

    @StateObject private var calendarShown = BoolBox()

    private var periodLabel: String { store.dayLabel }

    private func stepHelp(back: Bool) -> String { back ? "Previous day" : "Next day" }

    private var canStepBack: Bool { store.canStepBack }

    private var canStepForward: Bool { store.canStepForward }

    private func step(_ delta: Int) {
        navigation.stepStoryPeriod(by: delta)
    }
}

/// The live session in the chrome. Running, it shows the clock and pauses on
/// click; idle, it starts one — the window must be able to begin work, not only
/// describe it.
struct StorySessionControl: View {
    @ObservedObject var store: SessionStore
    var focus: FocusState<StoryChromeFocus?>.Binding
    var onDetails: () -> Void = {}

    var body: some View {
        if store.isIdle {
            Button(action: onDetails) {
                HStack(spacing: Tokens.Space.xs) {
                    Image(systemName: "play.fill").font(Tokens.Typography.microLabel.weight(.bold))
                    Text("Start focus").font(Tokens.Typography.metadata.weight(.semibold))
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.focus, in: Capsule())
                .foregroundStyle(Tokens.Colour.onFocus)
            }
            .buttonStyle(PressableStyle())
            .focused(focus, equals: .session)
            .accessibilityLabel("Start focus")
            .accessibilityHint("Opens the session controls to choose an activity")
        } else {
            Button(action: onDetails) {
                HStack(spacing: Tokens.Space.s) {
                    // The story's focus ink: system blue on its own tint was
                    // 3.3:1 in the light appearance.
                    Circle()
                        .fill(StoryStyle.focus)
                        .frame(width: 7, height: 7)
                        .opacity(store.isPaused ? 0.4 : 1)
                    // Seconds swap plainly; only a new minute rolls, so the
                    // corner of the window is not in motion every second.
                    Text(Tokens.clock(store.elapsed))
                        .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                        .foregroundStyle(StoryStyle.focus)
                        .rollingDigits(DurationText.wholeSeconds(store.elapsed).map { $0 / 60 })
                    if store.pendingAway != nil {
                        Divider().frame(height: 12)
                        Text("Review away")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    } else if store.isPaused {
                        // A dimmer dot was the only sign the clock had stopped.
                        Divider().frame(height: 12)
                        Text("Paused")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(StoryStyle.focus.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .focused(focus, equals: .session)
            .accessibilityLabel("Session, \(Tokens.spokenElapsed(store.elapsed)), "
                                + (store.pendingAway != nil ? "away question waiting"
                                   : store.isPaused ? "paused" : "running"))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityHint("Open session controls, including pause, resume and end")
        }
    }
}
