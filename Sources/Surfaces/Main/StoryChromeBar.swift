import SwiftUI

/// The window's one chrome row, in the design's order: clearance for the native
/// traffic lights, the scope, the period it resolves to, the live session, and
/// Settings. It never scrolls and it is the only global navigation.
struct StoryChromeBar: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        HStack(spacing: Tokens.Space.l) {
            // The real window controls live here; the bar must not draw its own.
            Color.clear
                .frame(width: MainWindowChrome.trafficLightClearance, height: 1)
                .accessibilityHidden(true)
            workspaceControls
            Spacer(minLength: Tokens.Space.s)
            StorySessionControl(store: store, onDetails: { navigation.openSheet(.focus) })
            Button { navigation.openSheet(.settings) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: AccessibilityMetrics.minimumTargetSize,
                           height: AccessibilityMetrics.minimumTargetSize)
                    .background(Tokens.Colour.elevated, in: Circle())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Tokens.Space.l)
        .padding(.vertical, Tokens.Space.s)
        .background(StoryStyle.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window chrome")
    }

    @ViewBuilder private var workspaceControls: some View {
        switch navigation.workspace {
        case .story:
            StoryScopePills(selection: Binding(get: { navigation.storyScope },
                                               set: { navigation.selectScope($0) }))
            Spacer(minLength: Tokens.Space.s)
            periodNavigation
        case .history:
            returnToStory
            Text("History")
                .font(Tokens.Typography.rowTitle)
                .accessibilityAddTraits(.isHeader)
            Text("\(store.filteredHistoryDays.count) dated records")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
        case .insights:
            returnToStory
            InsightRangePills(selection: Binding(
                get: { navigation.insightRange },
                set: { navigation.selectInsightRange($0) }))
            insightNavigation
        }
    }

    private var returnToStory: some View {
        Button(action: navigation.returnToStory) {
            Label("Story", systemImage: "chevron.left")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StoryStyle.action)
        .accessibilityLabel("Return to Story")
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
    var onDetails: () -> Void = {}

    var body: some View {
        if store.isIdle {
            Button(action: onDetails) {
                HStack(spacing: Tokens.Space.xs) {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                    Text("Start focus").font(Tokens.Typography.metadata.weight(.semibold))
                }
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.focus, in: Capsule())
                .foregroundStyle(Tokens.Colour.onFocus)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a focus session")
        } else {
            Button(action: onDetails) {
                HStack(spacing: Tokens.Space.s) {
                    Circle()
                        .fill(Tokens.Colour.focus)
                        .frame(width: 7, height: 7)
                        .opacity(store.isPaused ? 0.4 : 1)
                    Text(Tokens.clock(store.elapsed))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Tokens.Colour.focus)
                        .contentTransition(.numericText())
                    Divider().frame(height: 12)
                    Text(store.pendingAway != nil ? "Review away" : "Session")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.focus.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Tokens.spent(store.elapsed)) elapsed, "
                                + (store.isPaused ? "paused" : "running"))
            .accessibilityHint("Open session controls, including pause, resume and end")
        }
    }
}

/// Day · Week · Month. The scope changes what the story is about; it never
/// changes surface.
struct StoryScopePills: View {
    @Binding var selection: StoryScope

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StoryScope.allCases) { scope in
                pill(scope)
            }
        }
        .padding(3)
        .background(StoryStyle.well,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Story scope")
    }

    private func pill(_ scope: StoryScope) -> some View {
        let isSelected = selection == scope
        return Button { selection = scope } label: {
            Text(scope.title)
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 62, height: AccessibilityMetrics.minimumTargetSize)
                .background(isSelected ? StoryStyle.card : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(isSelected ? 0.10 : 0), radius: 1, y: 1)
        }
        .buttonStyle(StoryPressStyle())
        .accessibilityLabel("\(scope.title), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
