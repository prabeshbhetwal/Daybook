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

    /// Set on a tile while the rail is being arranged; its header then shows
    /// up and down buttons.
    var storyTileMoves: StoryTileMoves? {
        get { self[StoryTileMovesKey.self] }
        set { self[StoryTileMovesKey.self] = newValue }
    }
}

/// The keyboard's way to reorder a tile. A drag needs a pointer and the tile's
/// menu a right-click, so without these a Full Keyboard Access user who chose
/// "Arrange cards" had nothing to act on.
struct StoryTileMoves {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
}

private struct StoryTileMovesKey: EnvironmentKey {
    static let defaultValue: StoryTileMoves? = nil
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
    /// A day History has open; nil is the dashboard's own day. Every figure
    /// is that day's, and the streak — which is about now — is left out.
    var day: Date?
    /// The tile under the pointer during a drag, so the drop target is visible
    /// before the mouse is released.
    @StateObject private var dropTarget = TileBox()
    @StateObject private var selectedApp = TextBox()
    @StateObject private var arrangement = StoryRailArrangement()
    @Environment(\.storyTilesAreDraggable) private var tilesAreDraggable
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        // The interval projection is the rail's most expensive read; one pass
        // serves the visibility test, On this Mac and the goal card.
        let evidence = breakdown
        let shownTiles = visibleTiles(evidence)
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 14) {
            ForEach(shownTiles, id: \.self) { kind in
                arrangedTile(kind, shownTiles: shownTiles, evidence: evidence)
            }
            // Cards are arranged on the dashboard; History shows them in that order.
            if day == nil { droppable(footer(shownTiles), before: nil) }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: store.dayOffset) { _ in selectedApp.text = "" }
        .onChange(of: day) { _ in selectedApp.text = "" }
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
                // The 28pt frame sits inside the label: outside the button it
                // made room but left only the words clickable.
                Button { resetOrder() } label: {
                    Text("Reset order")
                        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(StoryPressStyle())
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reset card order")
            }
        }
        .fixedSize()
    }

    @ViewBuilder private func arrangedTile(_ kind: StoryTileKind,
                                            shownTiles: [StoryTileKind],
                                            evidence: StoryUsageBreakdown) -> some View {
        let content = draggable(tile(kind, evidence: evidence)
            .coachAnchor(Self.coachAnchor(for: kind)), as: kind)
        if arrangement.isArranging {
            let canMoveUp = shownTiles.first != kind
            let canMoveDown = shownTiles.last != kind
            content
                .environment(\.storyTileMoves,
                             StoryTileMoves(name: kind.title, canMoveUp: canMoveUp,
                                            canMoveDown: canMoveDown,
                                            move: { moveVertically(kind, by: $0) }))
                .contextMenu {
                    Button("Move \(kind.title) up") { moveVertically(kind, by: -1) }
                        .disabled(!canMoveUp)
                    Button("Move \(kind.title) down") { moveVertically(kind, by: 1) }
                        .disabled(!canMoveDown)
                }
                // Offered only where they can act, so VoiceOver never lists a
                // move that would do nothing.
                .accessibilityActions {
                    if canMoveUp {
                        Button("Move up") { moveVertically(kind, by: -1) }
                    }
                    if canMoveDown {
                        Button("Move down") { moveVertically(kind, by: 1) }
                    }
                }
        } else {
            content
        }
    }

    /// Takes the body's tile list: each pass over it re-reads the archive.
    private func footer(_ shownTiles: [StoryTileKind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            arrangeControl(shownTiles)
            if let note = footnote(shownTiles) {
                Text(note)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Only says what the visible cards need explaining. A note about the
    /// streak on a rail with no streak card explains nothing, and on today
    /// "Last 14 days" already says it.
    private func footnote(_ shownTiles: [StoryTileKind]) -> String? {
        if arrangement.isArranging && tilesAreDraggable {
            return "Drag cards or use their arrows to reorder."
        }
        return shownTiles.contains(.streak) && !store.isToday
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
    private func visibleTiles(_ evidence: StoryUsageBreakdown) -> [StoryTileKind] {
        settings.storyTileOrder.filter { kind in
            switch kind {
            // Week and Month headlines already give the total, the focused
            // days and the average; only a day has a goal to show.
            case .focus: return true
            case .mac: return evidence.tracked > 0
            case .apps: return !apps.isEmpty
            case .rhythm: return !rhythmHours.isEmpty
            case .streak: return day == nil && store.streak > 0
            }
        }
    }

    @ViewBuilder private func tile(_ kind: StoryTileKind,
                                   evidence: StoryUsageBreakdown) -> some View {
        switch kind {
        case .focus: focusTile(evidence)
        case .mac: macTile(evidence)
        case .apps: appsTile
        case .rhythm: rhythmTile
        case .streak: streakTile
        }
    }

    private func move(_ kind: StoryTileKind, before target: StoryTileKind?) {
        arrangement.synchronise(settings.storyTileOrder)
        guard arrangement.move(kind, before: target) else { return }
        saveMove(of: kind)
    }

    private func moveVertically(_ kind: StoryTileKind, by delta: Int) {
        arrangement.synchronise(settings.storyTileOrder)
        guard arrangement.move(kind, by: delta, visible: visibleTiles(breakdown)) else { return }
        saveMove(of: kind)
    }

    /// Saves the order and says where the card landed. A sighted reader
    /// watches it move; someone listening heard nothing at all.
    private func saveMove(of kind: StoryTileKind) {
        settings.storyTileOrder = arrangement.order
        let shown = visibleTiles(breakdown)
        if let index = shown.firstIndex(of: kind) {
            Announcement.post("\(kind.title), position \(index + 1) of \(shown.count)")
        }
    }

    private func resetOrder() {
        arrangement.reset()
        settings.storyTileOrder = arrangement.order
    }

    /// The welcome rings tiles by kind.
    static func coachAnchor(for kind: StoryTileKind) -> CoachAnchor {
        switch kind {
        case .focus: return .focusTile
        case .mac: return .macTile
        case .apps: return .appsTile
        case .rhythm: return .rhythmTile
        case .streak: return .streakTile
        }
    }

    // MARK: - Daily goal

    /// The day's focus total is the headline's; this card is the goal's.
    private func focusTile(_ evidence: StoryUsageBreakdown) -> some View {
        let goal = railGoal
        return StoryTile(title: "Daily goal", trailing: day.map { Tokens.dayLabel($0) } ?? store.dayLabel) {
            HStack(alignment: .bottom, spacing: Tokens.Space.m) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    if goal.goal > 0 {
                        // Keyed on the printed text, not the seconds behind it: keyed
                        // on the seconds, the roll restarted every tick and drew the
                        // same figure again each time.
                        Text(durations: Tokens.preciseDuration(goal.achieved))
                            .font(Tokens.Typography.metricValue.monospacedDigit())
                            .rollingDigits(Tokens.preciseDuration(goal.achieved))
                        Text(durations: "counts towards your \(Tokens.duration(goal.goal)) goal"
                             + (goal.isMet ? " · goal met" : ""))
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No daily goal set")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let share = goalShare {
                    GoalRing(progress: share, diameter: 56, lineWidth: 7,
                             label: "\(Int((share * 100).rounded()))%",
                             isMet: share >= 1,
                             labelFont: .system(size: 12, weight: .bold, design: .rounded),
                             accessibilityTitle: "Share of goal")
                }
            }
            // The headline's logged figure and this card's can differ. This
            // card owns the arithmetic that joins them.
            if goal.goal > 0,
               let equation = StoryRailFigures.goalEquation(logged: evidence.focused, counted: goal.achieved) {
                Text(durations: equation)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Only focus with app use recorded counts towards the goal.")
                    .accessibilityHint("Only focus with app use recorded counts towards the goal.")
            }
            if !categoryGoals.isEmpty {
                categoryGoalRows
            }
            // Today's tile only: the tidy-up is about the record as it is now.
            if day == nil {
                NameCategoryNotice(store: store, settings: settings)
            }
        }
    }

    /// Categories with a goal of their own, with the day's seconds against it.
    private var categoryGoals: [(type: WorkType, goal: TimeInterval, achieved: TimeInterval)] {
        let seconds = store.storyCategorySeconds(on: shownDay)
        return WorkType.startable.compactMap { type in
            guard let goal = type.dailyGoal, goal > 0 else { return nil }
            return (type, goal, seconds[type] ?? 0)
        }
    }

    /// One quiet line per category goal: mark, name, figure, a thin bar. The
    /// ring above stays the day's; these are its slices.
    private var categoryGoalRows: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Divider()
            ForEach(categoryGoals, id: \.type) { item in
                let share = min(1, item.achieved / item.goal)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: item.type.symbolName)
                            .font(Tokens.Typography.microLabel)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Tokens.Palette.workType(item.type))
                            .frame(width: 14)
                        Text(item.type.displayName)
                            .font(Tokens.Typography.metadata)
                        Spacer(minLength: Tokens.Space.s)
                        Text(durations: "\(Tokens.duration(item.achieved)) of \(Tokens.duration(item.goal))"
                             + (share >= 1 ? " · met" : ""))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(share >= 1 ? AnyShapeStyle(StoryStyle.successInk)
                                                        : AnyShapeStyle(.secondary))
                    }
                    GeometryReader { geometry in
                        Capsule().fill(StoryStyle.line)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Tokens.Palette.workType(item.type))
                                    .frame(width: geometry.size.width * share)
                            }
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(DurationText.spoken(in: "\(item.type.displayName): \(Tokens.duration(item.achieved)) of a \(Tokens.duration(item.goal)) goal"))
                // A session named "Coding" under Deep work is not here: the
                // goal counts the category, and says so.
                .help("Counts sessions filed under \(item.type.displayName)")
                .accessibilityHint("Counts sessions filed under \(item.type.displayName)")
            }
        }
    }

    private var goalShare: Double? {
        guard store.goal.goal > 0 else { return nil }
        return railGoal.share
    }

    // MARK: - The day shown

    private var shownDay: Date { day ?? store.selectedDay }
    private var reading: StoryRailDay? { day.map { store.storyRailDay(on: $0) } }
    private var railGoal: GoalProgress { reading?.goal ?? store.selectedDayGoal }
    private var rhythmHours: [RhythmHour] { reading?.rhythm ?? store.rhythm }
    private var rhythmPeak: String? { day == nil ? store.rhythmPeak : reading?.rhythmPeak }

    // MARK: - On this Mac

    private func macTile(_ evidence: StoryUsageBreakdown) -> some View {
        let rows = StoryRailFigures.macRows(tracked: evidence.tracked, insideSessions: evidence.insideSessions,
                                           countedFocus: railGoal.achieved)
        let minutes = { (value: Int) in TimeInterval(value * 60) }
        let trackedValue = minutes(rows.total)
        return StoryTile(title: "On this Mac", trailing: nil) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(durations: Tokens.preciseDuration(trackedValue))
                    .rollingDigits(Tokens.preciseDuration(trackedValue))
                    .font(Tokens.Typography.rowTitle.weight(.semibold).monospacedDigit())
                Text("recorded app use")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            if trackedValue > 0 {
                // Three parts that add up to the figure above: the goal's
                // own focus, app use during a session's pauses, and the rest.
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Tokens.Palette.app(rank: 1))
                            .frame(width: geometry.size.width * width(of: minutes(rows.duringFocus), total: trackedValue))
                        Rectangle()
                            .fill(Tokens.Palette.app(rank: 1).opacity(0.7))
                            .frame(width: geometry.size.width * width(of: minutes(rows.duringPauses), total: trackedValue))
                        Rectangle()
                            .fill(Tokens.Palette.app(rank: 1).opacity(0.42))
                            .frame(width: geometry.size.width * width(of: minutes(rows.outside), total: trackedValue))
                    }
                }
                .frame(height: 7)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                legendRow(colour: Tokens.Palette.app(rank: 1),
                          label: "During focus",
                          value: Tokens.duration(minutes(rows.duringFocus)))
                if rows.duringPauses > 0 {
                    legendRow(colour: Tokens.Palette.app(rank: 1).opacity(0.7),
                              label: "During pauses",
                              value: Tokens.duration(minutes(rows.duringPauses)))
                }
                legendRow(colour: Tokens.Palette.app(rank: 1).opacity(0.42),
                          label: "Outside sessions",
                          value: Tokens.duration(minutes(rows.outside)))
            }
        }
    }

    /// Temporal membership splits observed use. Missing focus coverage is a
    /// separate measure and is never added to the observed headline or bar.
    private var breakdown: StoryUsageBreakdown {
        store.storyUsageBreakdown(on: shownDay)
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
        .accessibilityLabel(DurationText.spoken(in: "\(label), \(value)"))
    }

    // MARK: - Apps

    private var apps: [AppRank] { reading?.apps ?? store.rankedApps }

    private var appsTile: some View {
        // The title says what the list is; the trailing figure says how many
        // it was cut from. "Apps · Top 4 of 10" made the reader assemble that.
        let limit = store.engine.store.menuAppCount
        return StoryTile(title: apps.count > limit ? "Your top \(limit) apps" : "Your apps",
                  trailing: apps.isEmpty ? "None recorded"
                    : apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
            ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: index) { selectedApp.text = app.bundleID }
                    .popover(isPresented: Binding(
                        get: { selectedApp.text == app.bundleID },
                        set: { if !$0 && selectedApp.text == app.bundleID { selectedApp.text = "" } })) {
                            StoryAppDetail(store: store, bundleID: app.bundleID, day: day,
                                           onDismiss: { selectedApp.text = "" })
                        }
                    .onExitCommand { selectedApp.text = "" }
            }
        }
    }

    // MARK: - Rhythm

    private var rhythmTile: some View {
        StoryTile(title: "Rhythm", trailing: "by hour") {
            RhythmChart(hours: rhythmHours, height: 54, compactLabels: true)
            if let peak = rhythmPeak {
                Text("Most recorded app use: \(peak).")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Streak

    private var streakTile: some View {
        let days = store.streakDays()
        return StoryTile(title: "Current streak",
                  trailing: store.streak == 1 ? "1 day" : "\(store.streak) days") {
            HStack(spacing: 3) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, entry in
                    RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous)
                        .fill(entry.met ? Tokens.Palette.app(rank: 4) : Tokens.Colour.elevated)
                        .frame(height: 8)
                }
            }
            // The strip's news is which days met the minimum; the streak
            // length is already the card's trailing figure.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Days met")
            .accessibilityValue("\(days.filter(\.met).count) of the last \(days.count)")
            // On the first line's baseline, so the link stays beside the
            // sentence it follows when the sentence wraps.
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
                Text(durations: "Last 14 days. A day counts once it has "
                     + "\(Tokens.preciseDuration(store.engine.store.streakMinimum)) of focus.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // The word is about 15pt tall. The padding lifts the target
                // past 28pt; the negative padding keeps the row where it was.
                Button { navigation.openSheet(.awards) } label: {
                    Text("Awards")
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, -7)
                .coachAnchor(.awards)
                .buttonStyle(StoryPressStyle())
                .font(Tokens.Typography.metadata.weight(.semibold))
                // The link colour every other text action uses; system blue
                // was under 4.5:1 on the rail.
                .foregroundStyle(StoryStyle.action)
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
    @Environment(\.storyTileMoves) private var moves

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text(title)
                    .font(Tokens.Typography.metadata.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Tokens.Space.xs)
                if let trailing {
                    // Any card may put a duration here; it is spoken in words.
                    Text(durations: trailing)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let moves {
                    IconButton(systemImage: "arrow.up", help: "Move \(moves.name) up") {
                        moves.move(-1)
                    }
                    .disabled(!moves.canMoveUp)
                    IconButton(systemImage: "arrow.down", help: "Move \(moves.name) down") {
                        moves.move(1)
                    }
                    .disabled(!moves.canMoveDown)
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
        .accessibilityLabel(title)
    }
}
