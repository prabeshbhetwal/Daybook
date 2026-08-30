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
            StoryScopePills(selection: Binding(get: { navigation.storyScope },
                                               set: { navigation.storyScope = $0 }))
            Spacer(minLength: Tokens.Space.s)
            periodNavigation
            Spacer(minLength: Tokens.Space.s)
            StorySessionControl(store: store)
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
        .background(Tokens.Colour.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window chrome")
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
        switch navigation.storyScope {
        case .day: store.stepDay(by: delta)
        case .week, .month: store.moveReviewPeriod(by: delta)
        }
    }
}

/// The live session in the chrome. Running, it shows the clock and pauses on
/// click; idle, it starts one — the window must be able to begin work, not only
/// describe it.
struct StorySessionControl: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        if store.isIdle {
            Button { store.start() } label: {
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
            Button { store.togglePause() } label: {
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
                    Text(store.isPaused ? "Resume" : "Pause")
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
            .accessibilityHint(store.isPaused ? "Resume the session" : "Pause the session")
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
        .background(Tokens.Colour.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Colour.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Story scope")
    }

    private func pill(_ scope: StoryScope) -> some View {
        let isSelected = selection == scope
        return Button { selection = scope } label: {
            Text(scope.title)
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(isSelected ? Tokens.Colour.onFocus : Color.secondary)
                .frame(width: 62, height: AccessibilityMetrics.minimumTargetSize)
                .background(isSelected ? Tokens.Colour.focus : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scope.title), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
