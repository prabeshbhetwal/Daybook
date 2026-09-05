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

    var body: some View {
        HStack(spacing: Tokens.Space.l) {
            // The real window controls live here; the bar must not draw its own.
            Color.clear
                .frame(width: MainWindowChrome.trafficLightClearance, height: 1)
                .accessibilityHidden(true)
            backSlot
            workspaceControls
            Spacer(minLength: Tokens.Space.s)
            if ChromeSessionControl.isShown(stripVisible: sessionControlsVisible) {
                StorySessionControl(store: store,
                                    focus: $focusedControl,
                                    onDetails: {
                                        navigation.performSessionControlsAction(.timerPill)
                                    })
                    .transition(Tokens.Motion.transition(
                        .opacity.combined(with: .scale(scale: 0.9)), reduceMotion: reduceMotion))
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
        }
        .padding(.horizontal, Tokens.Space.l)
        .padding(.vertical, Tokens.Space.s)
        .background(StoryStyle.canvas)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: sessionControlsVisible)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: navigation.workspace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window chrome")
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

    /// Every workspace lays out the same three columns — pills, period, links —
    /// so a change of workspace changes words, not positions.
    @ViewBuilder private var workspaceControls: some View {
        switch navigation.workspace {
        case .story:
            ScopePillRow(titles: StoryScope.allCases.map(\.title),
                         selectedIndex: Binding(
                            get: { StoryScope.allCases.firstIndex(of: navigation.storyScope) ?? 0 },
                            set: { navigation.selectScope(StoryScope.allCases[$0]) }),
                         controlLabel: "Story scope")
            Spacer(minLength: Tokens.Space.s)
            periodNavigation
            Spacer(minLength: Tokens.Space.s)
            crossLinks
        case .history:
            Text("History")
                .font(Tokens.Typography.rowTitle)
                .accessibilityAddTraits(.isHeader)
            Text("\(store.filteredHistoryDays.count) dated records")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.s)
            crossLinks
        case .insights:
            ScopePillRow(titles: InsightRange.allCases.map(\.title),
                         selectedIndex: Binding(
                            get: { InsightRange.allCases.firstIndex(of: navigation.insightRange) ?? 0 },
                            set: { navigation.selectInsightRange(InsightRange.allCases[$0]) }),
                         controlLabel: "Insights range")
            Spacer(minLength: Tokens.Space.s)
            insightNavigation
            Spacer(minLength: Tokens.Space.s)
            crossLinks
        }
    }

    /// The other workspaces, as links. Navigation belongs in the chrome; these
    /// sat below every rail card, so reaching them meant scrolling past the
    /// content first. The column keeps its width whichever links it holds, so
    /// the period control between the spacers stays centred on the same point.
    private var crossLinks: some View {
        HStack(spacing: Tokens.Space.xs) {
            ForEach(links, id: \.0) { title, sheet in
                Button { navigation.openSheet(sheet) } label: {
                    Text(title)
                        .padding(.horizontal, Tokens.Space.s)
                        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                }
                .buttonStyle(StoryPressStyle(hovers: true))
            }
        }
        .font(Tokens.Typography.metadata.weight(.semibold))
        .foregroundStyle(StoryStyle.action)
        .frame(minWidth: 132, alignment: .trailing)
    }

    private var links: [(String, StorySheetKind)] {
        switch navigation.workspace {
        case .story: return [("History", .history), ("Insights", .insights)]
        case .history: return [("Insights", .insights)]
        case .insights: return [("History", .history)]
        }
    }

    private var insightNavigation: some View {
        HStack(spacing: Tokens.Space.s) {
            IconButton(systemImage: "chevron.left", help: "Earlier Insights period") {
                navigation.stepInsightPeriod(by: -1)
            }
            Text(navigation.insightAnchorLabel)
                .font(Tokens.Typography.rowTitle)
                .lineLimit(1)
                .frame(minWidth: 168)
                .accessibilityLabel("Insights anchored at \(navigation.insightAnchorLabel)")
            IconButton(systemImage: "chevron.right", help: "Later Insights period") {
                navigation.stepInsightPeriod(by: 1)
            }
            .disabled(Calendar.current.isDate(navigation.insightAnchor,
                                              inSameDayAs: store.now()))
        }
    }

    private var periodNavigation: some View {
        HStack(spacing: Tokens.Space.s) {
            IconButton(systemImage: "chevron.left", help: stepHelp(back: true)) { step(-1) }
                .disabled(!canStepBack)
            Text(periodLabel)
                .font(Tokens.Typography.rowTitle)
                .lineLimit(1)
                .frame(minWidth: 168)
                .accessibilityLabel("\(periodLabel), selected period")
                .accessibilityAddTraits(.isSelected)
            IconButton(systemImage: "chevron.right", help: stepHelp(back: false)) { step(1) }
                .disabled(!canStepForward)
        }
    }

    private var periodLabel: String {
        switch navigation.storyScope {
        case .day: return store.dayLabel
        case .week, .month: return store.reviewPeriodLabel
        }
    }

    private func stepHelp(back: Bool) -> String {
        let unit: String
        switch navigation.storyScope {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        }
        return "\(back ? "Previous" : "Next") \(unit)"
    }

    private var canStepBack: Bool {
        navigation.storyScope == .day ? store.canStepBack : true
    }

    private var canStepForward: Bool {
        navigation.storyScope == .day ? store.canStepForward : store.reviewCanMoveForward
    }

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
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.focus, in: Capsule())
                .foregroundStyle(Tokens.Colour.onFocus)
            }
            .buttonStyle(PressableStyle())
            .focused(focus, equals: .session)
            .accessibilityLabel("Start a focus session")
        } else {
            Button(action: onDetails) {
                HStack(spacing: Tokens.Space.s) {
                    Circle()
                        .fill(Tokens.Colour.focus)
                        .frame(width: 7, height: 7)
                        .opacity(store.isPaused ? 0.4 : 1)
                    Text(Tokens.clock(store.elapsed))
                        .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Tokens.Colour.focus)
                        .rollingDigits(store.elapsed)
                    Divider().frame(height: 12)
                    Text(store.pendingAway != nil ? "Review away" : "Session")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.focus.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .focused(focus, equals: .session)
            .accessibilityLabel("\(Tokens.spent(store.elapsed)) elapsed, "
                                + (store.isPaused ? "paused" : "running"))
            .accessibilityHint("Open session controls, including pause, resume and end")
        }
    }
}
