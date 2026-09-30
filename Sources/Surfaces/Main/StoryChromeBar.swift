import SwiftUI

enum StoryChromeFocus: Hashable {
    case session
    case settings
}

/// The window's one chrome row, in the design's order: clearance for the native
/// traffic lights, the scope, the period it resolves to, the live session, and
/// Settings. It never scrolls and it is the only global navigation.
enum ChromeSessionControl {
    /// The story's chrome holds the full controls, so it has no small pill;
    /// History's chrome holds its own centre, so the pill is its way back to
    /// the session.
    static func isShown(workspace: MainReadingWorkspace) -> Bool { workspace == .history }
}

struct StoryChromeBar: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @FocusState private var focusedControl: StoryChromeFocus?
    /// The activity field in the bar, so ⌘7 and the tour can hand it the cursor.
    @FocusState private var intentFocused: Bool
    @StateObject private var gearHovered = BoolBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A scope pill is the target floor plus the container's 3pt inset each side.
    static let controlRowHeight: CGFloat = AccessibilityMetrics.minimumTargetSize + 6
    var body: some View {
        HStack(spacing: Tokens.Space.l) {
            // The real window controls live here; the bar must not draw its own.
            Color.clear
                .frame(width: MainWindowChrome.trafficLightClearance, height: 1)
                .accessibilityHidden(true)
            backSlot
            workspaceControls
            if ChromeSessionControl.isShown(workspace: navigation.workspace) {
                StorySessionControl(store: store,
                                    focus: $focusedControl,
                                    onDetails: { navigation.focusSessionControls() })
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
                   value: navigation.workspace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Toolbar")
        .onChange(of: navigation.focusRestorationRequest) { target in
            guard let target else { return }
            switch target {
            case .sessionControls:
                // The field is only in the story's bar; History has the pill.
                if navigation.workspace == .story { intentFocused = true } else { focusedControl = .session }
            case .settings: focusedControl = .settings
            }
            navigation.consumeFocusRestorationRequest()
        }
        .onChange(of: intentFocused) { if $0 { navigation.noteActivityFieldEngaged() } }
    }

    /// The way back, in a slot that exists in every workspace. "‹ Story" used
    /// to be inserted in front of the scope pills on History, so
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
            // The story is today, and the bar is where a session begins,
            // pauses and ends: the controls are its centre.
            Group {
                FocusHero(store: store, intentFocused: $intentFocused, compact: true, wide: true,
                          showsGoal: false, chromePart: .row)
                    .coachAnchor(.activityField)
            }
            .coachAnchor(.sessionControl)
            .storyRenderEvidence(.storyChromeControls)
            crossLinks
        case .history:
            // History is one list, newest first: the bar names it and offers
            // the calendar. Scrolling replaces paging, so there are no arrows.
            Text("History")
                .font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tokens.Space.s)
            jumpToDate
                .coachAnchor(.periodNav)
            Spacer(minLength: Tokens.Space.s)
        }
    }

    /// The way to History, as a link. Navigation belongs in the chrome; it
    /// sat below every rail card, so reaching it meant scrolling past the
    /// content first. History's own bar has the back button instead.
    private var crossLinks: some View {
        Button("History") { navigation.open(tab: .review) }
            .buttonStyle(StoryLinkStyle())
    }

    @StateObject private var historyCalendarShown = BoolBox()

    /// History's calendar: pick a day and the journal selects it and scrolls
    /// there. Each date shows its focus, so the calendar is also a map.
    private var jumpToDate: some View {
        Button { historyCalendarShown.value.toggle() } label: {
            Label("Jump to date", systemImage: "calendar")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.well))
        .help("Pick a day to read in History")
        .accessibilityHint("Opens the calendar; the day you pick is selected in the list")
        .popover(isPresented: Binding(get: { historyCalendarShown.value },
                                      set: { historyCalendarShown.value = $0 }),
                 arrowEdge: .bottom) {
            DayPickerCalendar(
                selected: navigation.reviewSelectedDate ?? Calendar.current.startOfDay(for: store.now()),
                earliest: store.earliestSelectableDay,
                goal: store.goal.goal,
                facts: { store.dayFacts(inMonthOf: $0) }) { day in
                    navigation.openHistory(day: day)
                    historyCalendarShown.value = false
                }
        }
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
                    ClockText(seconds: store.elapsed)
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .foregroundStyle(StoryStyle.focus)
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
