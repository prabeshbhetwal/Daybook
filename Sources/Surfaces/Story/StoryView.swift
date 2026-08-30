import SwiftUI

/// Which span the story is telling. The scope control changes only what the
/// story is about; it never changes surface.
enum StoryScope: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    var period: TrackingPeriod? {
        switch self {
        case .day: return nil
        case .week: return .week
        case .month: return .month
        }
    }
}

/// The day, week or month told as one story with the detail alongside: a single
/// column read top to bottom, and a rail of tiles that follow the same scope.
/// Selecting a day anywhere in the week or month opens that day's story here —
/// the drill-in never leaves the surface.
struct StoryView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `ImageRenderer` gives a `ScrollView` no intrinsic content.
    var scrolls = true

    var body: some View {
        VStack(spacing: 0) {
            StoryScopeBar(store: store, navigation: navigation)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Group {
                    if scrolls {
                        ScrollView { column }
                    } else {
                        column.frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Divider()
                Group {
                    if scrolls {
                        ScrollView { StoryRail(store: store, navigation: navigation) }
                    } else {
                        StoryRail(store: store, navigation: navigation)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(width: StoryLayout.railWidth)
                .background(Tokens.Colour.ground)
            }
        }
        .background(Tokens.Colour.surface)
        .onAppear {
            store.setDashboardVisible(true)
            if let period = navigation.storyScope.period {
                store.setReviewVisible(true)
                store.refreshReview(period: period)
            }
        }
        .onDisappear {
            store.setDashboardVisible(false)
            store.setReviewVisible(false)
        }
        .onChange(of: navigation.storyScope) { scope in
            if let period = scope.period {
                store.setReviewVisible(true)
                store.refreshReview(period: period)
            } else {
                store.setReviewVisible(false)
            }
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            switch navigation.storyScope {
            case .day: DayStoryColumn(store: store)
            case .week: WeekStoryColumn(store: store, navigation: navigation)
            case .month: MonthStoryColumn(store: store, navigation: navigation)
            }
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Tokens.Motion.animation(Tokens.Motion.rise, reduceMotion: reduceMotion),
                   value: navigation.storyScope)
    }
}

enum StoryLayout {
    /// The rail is fixed so the story column keeps a stable reading measure.
    static let railWidth: CGFloat = 336
}

// MARK: - Scope bar

/// Scope on the leading edge, the period it resolves to in the middle, and the
/// running session on the trailing edge — the one row that says what you are
/// looking at and what is happening now.
struct StoryScopeBar: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        HStack(spacing: Tokens.Space.l) {
            StoryScopePills(selection: Binding(get: { navigation.storyScope },
                                               set: { navigation.storyScope = $0 }))
            Spacer(minLength: Tokens.Space.m)
            HStack(spacing: Tokens.Space.m) {
                IconButton(systemImage: "chevron.left", help: previousHelp) { step(-1) }
                    .disabled(!canStepBack)
                Text(periodLabel)
                    .font(Tokens.Typography.rowTitle)
                    .frame(minWidth: 150)
                    .accessibilityLabel("\(periodLabel), selected period")
                IconButton(systemImage: "chevron.right", help: nextHelp) { step(1) }
                    .disabled(!canStepForward)
            }
            Spacer(minLength: Tokens.Space.m)
            StoryRunningPill(store: store)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
        .background(Tokens.Colour.surface)
    }

    private var periodLabel: String {
        switch navigation.storyScope {
        case .day: return store.dayLabel
        case .week, .month: return store.reviewPeriodLabel
        }
    }

    private var previousHelp: String {
        switch navigation.storyScope {
        case .day: return "Previous day"
        case .week: return "Previous week"
        case .month: return "Previous month"
        }
    }

    private var nextHelp: String {
        switch navigation.storyScope {
        case .day: return "Next day"
        case .week: return "Next week"
        case .month: return "Next month"
        }
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

private struct StoryScopePills: View {
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

/// The live session, always in the same place. Pressing it pauses or resumes,
/// exactly as the Focus surface does.
private struct StoryRunningPill: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        if store.isIdle {
            Text("No session running")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
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
