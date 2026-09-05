import SwiftUI

private struct StoryTilesDraggableKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether rail tiles carry their drag affordance. The static snapshot
    /// renderer cannot draw an AppKit drag source, so it turns this off; the
    /// product never does.
    var storyTilesAreDraggable: Bool {
        get { self[StoryTilesDraggableKey.self] }
        set { self[StoryTilesDraggableKey.self] = newValue }
    }
}

/// Deliberate rail-order state. Every drag, drop and keyboard move passes
/// through this gate before SettingsModel persists the resulting order.
final class StoryRailArrangement: ObservableObject {
    @Published private(set) var isArranging = false
    @Published private(set) var order: [StoryTileKind]
    var allowsDrag: Bool { isArranging }

    init(order: [StoryTileKind] = StoryTileKind.allCases) {
        self.order = StoryTileKind.order(from: StoryTileKind.raw(from: order))
    }

    func synchronise(_ persisted: [StoryTileKind]) {
        guard !isArranging else { return }
        order = StoryTileKind.order(from: StoryTileKind.raw(from: persisted))
    }

    func begin() { isArranging = true }
    func finish() { isArranging = false }
    func escape() { finish() }

    @discardableResult
    func move(_ kind: StoryTileKind, by delta: Int,
              visible: [StoryTileKind]? = nil) -> Bool {
        guard isArranging, abs(delta) == 1 else { return false }
        let shown = visible ?? order
        guard let index = shown.firstIndex(of: kind),
              shown.indices.contains(index + delta) else { return false }
        let target = delta < 0 ? shown[index - 1]
            : (index + 2 < shown.count ? shown[index + 2] : nil)
        return move(kind, before: target)
    }

    @discardableResult
    func move(_ kind: StoryTileKind, before target: StoryTileKind?) -> Bool {
        guard isArranging else { return false }
        let changed = StoryTileKind.moving(kind, before: target, in: order)
        guard changed != order else { return false }
        order = changed
        return true
    }

    func reset() {
        guard isArranging else { return }
        order = StoryTileKind.allCases
    }
}

/// The tiles beside the story. Each one follows the scope above it, carries its
/// own colour, and shows nothing when it has nothing to say — a tile is never a
/// zero-valued placeholder.
struct StoryRail: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @ObservedObject var settings: SettingsModel
    /// The tile under the pointer during a drag, so the drop target is visible
    /// before the mouse is released.
    @StateObject private var dropTarget = TileBox()
    @StateObject private var selectedApp = TextBox()
    @StateObject private var arrangement = StoryRailArrangement()
    @Environment(\.storyTilesAreDraggable) private var tilesAreDraggable
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        let shownTiles = visibleTiles
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 14) {
            ForEach(shownTiles, id: \.self) { kind in
                arrangedTile(kind, shownTiles: shownTiles)
            }
            droppable(footer, before: nil)
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: navigation.storyScope) { _ in selectedApp.text = "" }
        .onChange(of: store.dayOffset) { _ in selectedApp.text = "" }
        .onChange(of: store.reviewAnchor) { _ in selectedApp.text = "" }
        .onChange(of: settings.storyTileOrder) { arrangement.synchronise($0) }
        .onAppear { arrangement.synchronise(settings.storyTileOrder) }
        .onExitCommand { arrangement.escape() }
    }

    /// One button, two states. This was a menu: open it, choose "Arrange
    /// cards", and while arranging every move sat two levels down in it —
    /// though each card already had its own menu, its drag handle and its
    /// accessibility actions for the same moves. The pencil enters, the tick
    /// saves and leaves; Reset shows only while there is an order to reset.
    private func arrangeControl(_ shownTiles: [StoryTileKind]) -> some View {
        HStack(spacing: Tokens.Space.m) {
            Button {
                if arrangement.isArranging {
                    settings.storyTileOrder = arrangement.order
                    arrangement.finish()
                } else {
                    arrangement.synchronise(settings.storyTileOrder)
                    arrangement.begin()
                }
            } label: {
                Label(arrangement.isArranging ? "Done" : "Arrange cards",
                      systemImage: arrangement.isArranging ? "checkmark" : "pencil")
                    .labelStyle(.iconOnly)
                    .symbolSwap()
                    .symbolNod(on: arrangement.isArranging)
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .frame(width: AccessibilityMetrics.minimumTargetSize,
                           height: AccessibilityMetrics.minimumTargetSize)
                    .background(arrangement.isArranging ? AnyShapeStyle(StoryStyle.action)
                                                        : AnyShapeStyle(Tokens.Colour.elevated),
                                in: Circle())
                    .foregroundStyle(arrangement.isArranging ? AnyShapeStyle(Tokens.Colour.onFocus)
                                                             : AnyShapeStyle(.secondary))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help(arrangement.isArranging ? "Save this order" : "Arrange cards")
            .accessibilityLabel(arrangement.isArranging ? "Save card order" : "Arrange cards")
            if arrangement.isArranging {
                Button("Reset order") { resetOrder() }
                    .buttonStyle(StoryPressStyle())
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                    .accessibilityLabel("Reset card order")
            }
        }
        .fixedSize()
    }

    @ViewBuilder private func arrangedTile(_ kind: StoryTileKind,
                                            shownTiles: [StoryTileKind]) -> some View {
        let content = draggable(tile(kind), as: kind)
        if arrangement.isArranging {
            content
                .contextMenu {
                    Button("Move \(kind.title) up") { moveVertically(kind, by: -1) }
                        .disabled(shownTiles.first == kind)
                    Button("Move \(kind.title) down") { moveVertically(kind, by: 1) }
                        .disabled(shownTiles.last == kind)
                }
                .accessibilityAction(named: "Move up") { moveVertically(kind, by: -1) }
                .accessibilityAction(named: "Move down") { moveVertically(kind, by: 1) }
        } else {
            content
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            arrangeControl(visibleTiles)
            if let note = footnote {
                Text(note)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Only says what the visible cards need explaining. A note about the
    /// streak on a rail with no streak card explains nothing.
    private var footnote: String? {
        if arrangement.isArranging && tilesAreDraggable {
            return "Drag cards to reorder, or use their menu."
        }
        return visibleTiles.contains(.streak)
            ? "The streak always describes recent days." : nil
    }

    @ViewBuilder private func draggable(_ content: some View,
                                        as kind: StoryTileKind) -> some View {
        if tilesAreDraggable && arrangement.allowsDrag {
            droppable(content.opacity(dropTarget.kind == kind ? 0.55 : 1)
                .overlay(RoundedRectangle(cornerRadius: StoryStyle.tileRadius)
                    .stroke(StoryStyle.action.opacity(0.45), style: StrokeStyle(lineWidth: 1,
                                                                                dash: [4, 3])))
                .onDrag {
                    dropTarget.dragging = kind
                    return NSItemProvider(object: kind.rawValue as NSString)
                }, before: kind)
        } else {
            content
        }
    }

    @ViewBuilder private func droppable(_ content: some View,
                                        before target: StoryTileKind?) -> some View {
        if tilesAreDraggable && arrangement.allowsDrag {
            content.onDrop(of: [.text], delegate: TileDropDelegate(
                target: target, box: dropTarget,
                move: { moved, before in move(moved, before: before) }))
        } else {
            content
        }
    }

    /// Only the tiles that have something to say, in the stored order.
    private var visibleTiles: [StoryTileKind] {
        settings.storyTileOrder.filter { kind in
            switch kind {
            case .focus: return focusValue > 0 || navigation.storyScope == .day
            case .mac:
                let evidence = breakdown
                return evidence.tracked > 0 || evidence.uncoveredFocus > 0
            case .apps: return !apps.isEmpty
            case .rhythm: return navigation.storyScope == .day && !store.rhythm.isEmpty
            case .streak: return store.streak > 0
            }
        }
    }

    @ViewBuilder private func tile(_ kind: StoryTileKind) -> some View {
        switch kind {
        case .focus: focusTile
        case .mac: macTile
        case .apps: appsTile
        case .rhythm: rhythmTile
        case .streak: streakTile
        }
    }

    private func move(_ kind: StoryTileKind, before target: StoryTileKind?) {
        arrangement.synchronise(settings.storyTileOrder)
        guard arrangement.move(kind, before: target) else { return }
        settings.storyTileOrder = arrangement.order
    }

    private func moveVertically(_ kind: StoryTileKind, by delta: Int) {
        arrangement.synchronise(settings.storyTileOrder)
        guard arrangement.move(kind, by: delta, visible: visibleTiles) else { return }
        settings.storyTileOrder = arrangement.order
    }

    private func resetOrder() {
        arrangement.reset()
        settings.storyTileOrder = arrangement.order
    }

    // MARK: - Focus

    private var focusTile: some View {
        StoryTile(title: focusTitle,
                  trailing: scopeLabel) {
            HStack(alignment: .bottom, spacing: Tokens.Space.m) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(Tokens.preciseDuration(focusValue))
                        .font(Tokens.Typography.metricValue.monospacedDigit())
                        .rollingDigits(focusValue)
                    Text(focusNote)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if goalShare != nil {
                    GoalRing(progress: goalShare ?? 0, diameter: 56, lineWidth: 7,
                             label: "\(Int(((goalShare ?? 0) * 100).rounded()))%",
                             isMet: (goalShare ?? 0) >= 1,
                             labelFont: .system(size: 12, weight: .bold, design: .rounded))
                        .accessibilityLabel("\(Int(((goalShare ?? 0) * 100).rounded())) per cent of the goal for \(store.dayLabel)")
                }
            }
        }
    }

    private var focusTitle: String {
        switch navigation.storyScope {
        case .day: return "Focus time"
        case .week: return "Focus this week"
        case .month: return "Focus this month"
        }
    }

    private var focusValue: TimeInterval {
        switch navigation.storyScope {
        case .day: return store.storyFocusedSeconds(on: store.selectedDay)
        case .week, .month: return store.reviewFocusedSeconds
        }
    }

    /// Only the day has a goal to be a share of; a week or a month reports its
    /// own shape instead of inventing a period target.
    private var goalShare: Double? {
        guard navigation.storyScope == .day, store.goal.goal > 0 else { return nil }
        return store.selectedDayGoal.share
    }

    private var focusNote: String {
        switch navigation.storyScope {
        case .day:
            let goal = store.selectedDayGoal
            guard goal.goal > 0 else { return "No daily goal set" }
            let credit = "\(Tokens.duration(goal.achieved)) of \(Tokens.duration(goal.goal)) goal credit"
            return credit + (goal.isMet ? " · goal met" : " · session work with recorded app use")
        case .week, .month:
            let summary = store.storyFocusSummary
            guard summary.activeDays > 0 else { return "No focus recorded" }
            let dayWord = summary.activeDays == 1 ? "focused day" : "focused days"
            return "\(summary.activeDays) \(dayWord) · "
                + "\(Tokens.duration(summary.averagePerActiveDay)) average"
        }
    }

    private var scopeLabel: String {
        navigation.storyScope == .day ? store.dayLabel : store.reviewPeriodLabel
    }

    // MARK: - On this Mac

    private var macTile: some View {
        // Resolve the relatively expensive interval projection once for this
        // tile, not again for every label, bar part and denominator.
        let evidence = breakdown
        let trackedValue = evidence.tracked
        let insideValue = evidence.insideSessions
        let looseValue = evidence.outsideSessions
        let unrecordedValue = evidence.uncoveredFocus
        return StoryTile(title: "On this Mac", trailing: nil) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(Tokens.preciseDuration(trackedValue))
                    .rollingDigits(trackedValue)
                    .font(Tokens.Typography.rowTitle.weight(.semibold).monospacedDigit())
                Text("recorded app use")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            if trackedValue > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Tokens.Palette.app(rank: 1))
                            .frame(width: geometry.size.width * width(of: insideValue, total: trackedValue))
                        Rectangle()
                            .fill(Tokens.Palette.app(rank: 1).opacity(0.42))
                            .frame(width: geometry.size.width * width(of: looseValue, total: trackedValue))
                    }
                }
                .frame(height: 7)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                legendRow(colour: Tokens.Palette.app(rank: 1),
                          label: "In a focus session",
                          value: Tokens.duration(insideValue))
                legendRow(colour: Tokens.Palette.app(rank: 1).opacity(0.42),
                          label: "Outside sessions",
                          value: Tokens.duration(looseValue))
            }
            if unrecordedValue > 0 {
                    Divider()
                    Text("\(Tokens.duration(unrecordedValue)) of focused work has no app-use coverage.")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
            }
            Text("A session may include pauses. Goal credit counts only focus with recorded app use.")
                .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Temporal membership splits observed use. Missing focus coverage is a
    /// separate measure and is never added to the observed headline or bar.
    private var breakdown: StoryUsageBreakdown {
        navigation.storyScope == .day
            ? store.storyUsageBreakdown(on: store.selectedDay) : store.storyUsageBreakdown
    }
    private func width(of value: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    private func legendRow(colour: Color, label: String, value: String) -> some View {
        HStack(spacing: Tokens.Space.s) {
            RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous)
                .fill(colour)
                .frame(width: 10, height: 10)
            Text(label)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.xs)
            Text(value)
                .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Apps

    private var apps: [AppRank] {
        navigation.storyScope == .day
            ? store.rankedApps
            : store.reviewAppGroups.map {
                AppRank(bundleID: $0.bundleID, appName: $0.appName,
                        total: $0.total, share: $0.share, longest: $0.longest)
            }
    }

    private var appsTile: some View {
        // The title says what the list is; the trailing figure says how many
        // it was cut from. "Apps · Top 4 of 10" made the reader assemble that.
        StoryTile(title: apps.count > 4 ? "Your top 4 apps" : "Your apps",
                  trailing: apps.isEmpty ? "None recorded"
                    : apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
            ForEach(Array(apps.prefix(4).enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: index) { selectedApp.text = app.bundleID }
                    .popover(isPresented: Binding(
                        get: { selectedApp.text == app.bundleID },
                        set: { if !$0 && selectedApp.text == app.bundleID { selectedApp.text = "" } })) {
                            StoryAppDetail(store: store, bundleID: app.bundleID,
                                           scope: navigation.storyScope,
                                           onDismiss: { selectedApp.text = "" })
                        }
                    .onExitCommand { selectedApp.text = "" }
            }
        }
    }

    // MARK: - Rhythm

    private var rhythmTile: some View {
        StoryTile(title: "Rhythm", trailing: "by hour") {
            RhythmChart(hours: store.rhythm, height: 54, compactLabels: true)
            if let peak = store.rhythmPeak {
                Text("Most recorded app use: \(peak).")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Streak

    private var streakTile: some View {
        StoryTile(title: "Current streak",
                  trailing: store.streak == 1 ? "1 day" : "\(store.streak) days") {
            HStack(spacing: 3) {
                ForEach(Array(store.streakDays().enumerated()), id: \.offset) { _, entry in
                    RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous)
                        .fill(entry.met ? Tokens.Palette.app(rank: 4) : Tokens.Colour.elevated)
                        .frame(height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.streak) day streak")
            HStack(spacing: Tokens.Space.xs) {
                Text("Last 14 days. At least "
                     + "\(Tokens.preciseDuration(FocusConstants.streakMinimum)) of focus.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                Button("Awards") { navigation.openSheet(.awards) }
                    .buttonStyle(StoryPressStyle())
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .foregroundStyle(Tokens.Colour.focus)
            }
        }
    }
}

/// Which tile is being dragged and which one the pointer is over. `@State` is
/// unavailable on this toolchain, so the drag needs an object behind it.
final class TileBox: ObservableObject {
    @Published var kind: StoryTileKind?
    var dragging: StoryTileKind?
}

/// Drops one tile before another. A drop onto the rail's own footer moves the
/// tile to the end, so the last position is reachable.
struct TileDropDelegate: DropDelegate {
    let target: StoryTileKind?
    let box: TileBox
    let move: (StoryTileKind, StoryTileKind?) -> Void

    func dropEntered(info: DropInfo) { box.kind = target }

    func dropExited(info: DropInfo) {
        if box.kind == target { box.kind = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            box.kind = nil
            box.dragging = nil
        }
        guard let dragged = box.dragging, dragged != target else { return false }
        move(dragged, target)
        return true
    }
}

/// One rail tile: a coloured title, an optional scope note, and its content.
struct StoryTile<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder let content: Content
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text(title)
                    .font(Tokens.Typography.metadata.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Tokens.Space.xs)
                if let trailing {
                    Text(trailing)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            content
        }
        .padding(StoryStyle.tileInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.card,
                    in: RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous)
            .strokeBorder(StoryStyle.line))
        .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
        .accessibilityElement(children: .contain)
    }
}
