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
/// "Arrange Cards" had nothing to act on.
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
    /// The notes Today offers, held here and built again only when their
    /// cause changes: the rail redraws every second with the store.
    @State private var noteOffers = TodayNoteOffers()
    @Environment(\.storyTilesAreDraggable) private var tilesAreDraggable
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.haptics) private var haptics

    var body: some View {
        // The interval projection is the rail's most expensive read; one pass
        // serves the visibility test, On this Mac and the goal card.
        let evidence = breakdown
        let shownTiles = visibleTiles(evidence)
        // The model's availability costs about 215 µs a read: once per redraw.
        let notesUsable = navigation.notes?.isUsable == true
        VStack(alignment: .leading, spacing: StoryStyle.railSpacing(for: density)) {
            if day == nil {
                if store.isToday {
                    TodayNotes(store: store, writer: navigation.notes, usable: notesUsable, offers: $noteOffers)
                }
                BackupOfferNotice(settings: settings)
            }
            // Hairlines, not cards: the rail is one inspector column.
            ForEach(shownTiles, id: \.self) { kind in
                if kind != shownTiles.first { Divider() }
                arrangedTile(kind, shownTiles: shownTiles, evidence: evidence)
            }
            // Cards are arranged on the dashboard; History shows them in that order.
            if day == nil { droppable(footer(shownTiles), before: nil) }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: store.dayOffset) { selectedApp.text = "" }
        .onChange(of: day) { selectedApp.text = "" }
        .onChange(of: settings.storyTileOrder) { _, order in arrangement.synchronise(order) }
        .onChange(of: TodayNoteOffers.cause(store: store, usable: notesUsable), initial: true) {
            if day == nil { noteOffers = TodayNoteOffers(store: store, usable: notesUsable) }
        }
        // Asking is the rail's to start, not the notice's: the notice draws
        // nothing until there is an offer, and a view with nothing in it runs
        // no task. The key moves with the session archive, notes, corrections,
        // Keep as is and the day; not with the clock or with app use.
        .task(id: store.nameSuggestionKey) { if day == nil { navigation.nameSuggester?.refresh() } }
        .onChange(of: store.appleIntelligenceEnabled) { _, enabled in
            if !enabled { navigation.nameSuggester?.cancelAll() } else if day == nil { navigation.nameSuggester?.refresh() }
        }
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
                Label(arrangement.isArranging ? "Done" : "Arrange Cards",
                      systemImage: arrangement.isArranging ? "checkmark" : "pencil")
                    .labelStyle(.iconOnly)
                    .symbolSwap()
                    .font(Tokens.Typography.label)
                    .frame(width: AccessibilityMetrics.minimumTargetSize,
                           height: AccessibilityMetrics.minimumTargetSize)
                    .background(arrangement.isArranging ? AnyShapeStyle(StoryStyle.action)
                                                        : AnyShapeStyle(Tokens.Colour.elevated),
                                in: Circle())
                    .foregroundStyle(arrangement.isArranging ? AnyShapeStyle(Tokens.Colour.onFocus)
                                                             : AnyShapeStyle(StoryStyle.supportingInk))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help(arrangement.isArranging ? "Save this order" : "Arrange Cards")
            .accessibilityLabel(arrangement.isArranging ? "Save card order" : "Arrange Cards")
            if arrangement.isArranging {
                Button("Reset Order") { resetOrder() }
                    .buttonStyle(StoryLinkStyle())
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
                    Button("Move \(kind.title) Up") { moveVertically(kind, by: -1) }
                        .disabled(!canMoveUp)
                    Button("Move \(kind.title) Down") { moveVertically(kind, by: 1) }
                        .disabled(!canMoveDown)
                }
                // Offered only where they can act, so VoiceOver never lists a
                // move that would do nothing.
                .accessibilityActions {
                    if canMoveUp {
                        Button("Move Up") { moveVertically(kind, by: -1) }
                    }
                    if canMoveDown {
                        Button("Move Down") { moveVertically(kind, by: 1) }
                    }
                }
        } else {
            content
        }
    }

    /// Takes the body's tile list: each pass over it re-reads the archive.
    private func footer(_ shownTiles: [StoryTileKind]) -> some View {
        VStack(alignment: .leading, spacing: 10.zoomed) {
            arrangeControl(shownTiles)
            if let note = footnote(shownTiles) {
                Text(note)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
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
                                                                                dash: [4.zoomed, 3.zoomed])))
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
                move: { moved, before in
                    move(moved, before: before)
                    haptics(.tileDropped)
                }))
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
        return StoryTile(title: "Today's goals", trailing: day.map { Tokens.dayLabel($0) },
                         info: goalsHelp(logged: evidence.focused, counted: goal.achieved)) {
            HStack(alignment: .bottom, spacing: Tokens.Space.m) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    if goal.goal > 0 {
                        // Keyed on the printed text, not the seconds behind it: keyed
                        // on the seconds, the roll restarted every tick and drew the
                        // same figure again each time.
                        Text(durations: Tokens.preciseDuration(goal.achieved))
                            .font(Tokens.Typography.figure)
                            .rollingDigits(Tokens.preciseDuration(goal.achieved))
                        Text(durations: "of \(Tokens.duration(goal.goal)) focus"
                             + (goal.isMet ? " · goal met" : ""))
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No daily goal set")
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
                    }
                }
                Spacer(minLength: 0)
                if let share = goalShare {
                    GoalRing(progress: share, diameter: 63.zoomed, lineWidth: 7.zoomed,
                             label: DurationText.percent(share),
                             isMet: share >= 1,
                             accessibilityTitle: "Share of goal")
                }
            }
            if !categoryGoals.isEmpty || !activityTargets.isEmpty || !appLimits.isEmpty || !activityLimits.isEmpty
                || !siteLimits.isEmpty {
                categoryGoalRows
            }
            // The Yesterday notice says it when it is offered; without one (no focus
            // session, or the on-device model unavailable) the card does.
            if day == nil, noteOffers.yesterday == nil, store.yesterdayWasPerfect {
                Label("Yesterday was a perfect day", systemImage: "checkmark.seal.fill")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.successInk)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Yesterday was a perfect day: every goal met or kept")
            }
            // Today's tile only: the tidy-up is about the record as it is now.
            if day == nil {
                NameCategoryNotice(store: store, settings: settings)
                if let suggester = navigation.nameSuggester {
                    NameSuggestionNotice(suggester: suggester, store: store)
                }
            }
        }
    }

    /// Category goals from the goal list, each against the day's focus with
    /// app use recorded: the ring's own accounting, so a row never outruns it.
    private var categoryGoals: [(type: WorkType, goal: TimeInterval, achieved: TimeInterval)] {
        let credit = store.storyRailDay(on: shownDay).creditByCategory
        return WorkType.startable.compactMap { type in
            guard let goal = type.dailyGoal, goal > 0 else { return nil }
            return (type, goal, credit[type.rawValue] ?? 0)
        }
    }

    /// What the card means, behind its info mark. The line joining the ring's
    /// figure to the logged focus (sessions less time with no app use) lives
    /// here rather than under the ring.
    private func goalsHelp(logged: TimeInterval, counted: TimeInterval) -> [HelpEntry] {
        var entries = [HelpEntry("The ring", "Your focus for the day against your daily goal. Only focus time "
                                 + "with an app in use counts."),
                       HelpEntry("Goals", "Each goal row with a bar is a target, counted the same way, so "
                                 + "it never adds up to more than the ring."),
                       HelpEntry("Limits", "A row marked as a limit is an app you want to keep under a time. "
                                 + "It counts all the time the app was in front, in a session or not.")]
        if let equation = StoryRailFigures.goalEquation(logged: logged, counted: counted) {
            entries.append(HelpEntry("Today", equation + "."))
        }
        return entries
    }

    /// One quiet line per category goal: mark, name, figure, a thin bar. The
    /// ring above stays the day's; these are its slices.
    private var categoryGoalRows: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Divider()
            ForEach(categoryGoals, id: \.type) { item in
                // A session named "Coding" under Deep work is not here: the
                // goal counts the category, and says so. An activity goal counts it.
                goalTargetRow(symbol: item.type.symbolName, tint: Tokens.Palette.workType(item.type),
                              name: item.type.displayName, goal: item.goal, achieved: item.achieved,
                              help: "Counts sessions filed under \(item.type.displayName)")
            }
            ForEach(activityTargets, id: \.id) { item in activityTargetRow(item) }
            ForEach(appLimits, id: \.bundleID) { limit in limitRow(limit) }
            ForEach(activityLimits, id: \.id) { limit in
                limitRow((limit.purpose.rawValue, limit.purpose.displayName, limit.limit, limit.used),
                         symbol: limit.purpose.symbolName,
                         // Browser time with no purpose could break it: the day will not count it as kept.
                         unread: limit.unjudged,
                         help:"Counts every app Daybook files under \(limit.purpose.displayName) today, in a session or not. Browsers count only with a purpose you set.")
            }
            ForEach(siteLimits, id: \.id) { limit in siteLimitRow(limit) }
        }
    }

    /// Today's limits only: a past day is shown by what it recorded, and a limit
    /// added, changed or removed since would otherwise rewrite it.
    private var appLimits: [(bundleID: String, name: String, limit: TimeInterval, used: TimeInterval)] {
        day == nil ? store.appLimits(ranked: apps) : []
    }

    /// An app kept under a limit: icon, name, "45m of 2h limit", a neutral bar
    /// and what is left. Past the limit it reads "15m over" in the attention
    /// ink, with no alarm: a limit is information, not a verdict.
    private func limitRow(_ item: (bundleID: String, name: String, limit: TimeInterval, used: TimeInterval),
                          symbol: String? = nil, unread: Bool = false, help: String? = nil)
        -> some View {
        let status = DailyGoalList.limitStatus(used: item.used, limit: item.limit)
        let detail = unread ? "Can't tell: browser time" : status.detail
        let share = min(1, item.used / max(1, item.limit))
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.xs) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(StoryStyle.supportingInk)
                        .accessibilityHidden(true)
                } else {
                    AppIcon(bundleID: item.bundleID, size: 14.zoomed, appName: item.name)
                }
                Text(item.name)
                    .font(Tokens.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Tokens.Space.s)
                Text(store.isTrackingEnabled ? status.figure : "\(Tokens.duration(item.limit)) limit")
                    .font(Tokens.Typography.body.monospacedDigit())
                    .fixedSize()
                    .foregroundStyle(StoryStyle.supportingInk)
            }
            if store.isTrackingEnabled {
                GeometryReader { geometry in
                    Capsule().fill(StoryStyle.line)
                        .overlay(alignment: .leading) {
                            Capsule().fill(status.isOver ? StoryStyle.attentionInk : StoryStyle.supportingInk)
                                .frame(width: geometry.size.width * share)
                        }
                }
                .frame(height: 3.zoomed)
                Text(detail)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(status.isOver ? StoryStyle.attentionInk : StoryStyle.supportingInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // Nothing is being recorded, so no allowance can be worked out.
                Text("App recording is off")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DurationText.spoken(in: "\(item.name): \(status.figure), \(detail)"))
        .help(help ?? "Counts all the time \(item.name) was in front today, in a session or not")
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
                    .font(Tokens.Typography.heading.monospacedDigit())
                Text("recorded app use")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
            }
            if trackedValue > 0 {
                // Three parts that add up to the figure above: the goal's
                // own focus, app use during a session's pauses, and the rest.
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Tokens.Palette.appUse)
                            .frame(width: geometry.size.width * width(of: minutes(rows.duringFocus), total: trackedValue))
                        Rectangle()
                            .fill(Tokens.Palette.appUse.opacity(0.7))
                            .frame(width: geometry.size.width * width(of: minutes(rows.duringPauses), total: trackedValue))
                        Rectangle()
                            .fill(Tokens.Palette.appUse.opacity(0.42))
                            .frame(width: geometry.size.width * width(of: minutes(rows.outside), total: trackedValue))
                    }
                }
                .frame(height: 7.zoomed)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                legendRow(colour: Tokens.Palette.appUse,
                          label: "During focus",
                          value: Tokens.duration(minutes(rows.duringFocus)))
                if rows.duringPauses > 0 {
                    legendRow(colour: Tokens.Palette.appUse.opacity(0.7),
                              label: "During pauses",
                              value: Tokens.duration(minutes(rows.duringPauses)))
                }
                legendRow(colour: Tokens.Palette.appUse.opacity(0.42),
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
                .frame(width: 10.zoomed, height: 10.zoomed)
            Text(label)
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
            Spacer(minLength: Tokens.Space.xs)
            Text(value)
                .font(Tokens.Typography.label.monospacedDigit())
                .foregroundStyle(StoryStyle.supportingInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DurationText.spoken(in: "\(label), \(value)"))
    }

    // MARK: - Apps

    var apps: [AppRank] { reading?.apps ?? store.rankedApps }

    private var appsTile: some View {
        // The trailing label is the period, as on the goal tile; the info mark
        // says what counts and how many apps the list was cut from. "10
        // recorded" beside the title left readers asking: a day, week or month?
        let limit = store.engine.store.menuAppCount
        let dayLabel = day.map { Tokens.dayLabel($0) } ?? store.dayLabel
        return StoryTile(title: "Top apps", trailing: dayLabel,
                         info: StoryRailFigures.appsHelp(shown: min(limit, apps.count),
                                                         total: apps.count, dayLabel: dayLabel)) {
            ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { _, app in
                StoryAppRow(app: app) { selectedApp.text = app.bundleID }
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

    /// Eight 3-hour columns with focus told apart from other app use, under
    /// a headline naming when focus peaked. Hourly bars of any app use could
    /// not say when someone was most productive.
    private var rhythmTile: some View {
        let blocks = store.storyRailDay(on: shownDay).blocks
        return StoryTile(title: "Time of day", trailing: day.map { Tokens.dayLabel($0) },
                         info: TimeOfDayChart.help) {
            if let headline = TimeOfDayChart.headline(blocks) {
                Text(headline)
                    .font(Tokens.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TimeOfDayChart(blocks: blocks)
        }
    }

    // MARK: - Streak

    private var streakTile: some View {
        let minimum = store.engine.store.streakMinimum
        // Today's focus with the running session in it, as the streak figure
        // counts it; the archive alone left today's dot empty mid-session.
        let today = store.todayTotal
        let todayCounts = today >= minimum
        let past = store.streakDays().dropLast()
        let minimumText = Tokens.preciseDuration(minimum)
        return StoryTile(title: "Focus streak",
                         trailing: store.streak == 1 ? "1 day" : "\(store.streak) days",
                         info: [HelpEntry("What counts",
                                          "Days in a row with at least \(minimumText) of focus. "
                                          + "Today only breaks the streak if it ends short."),
                                HelpEntry("The dots",
                                          "Each dot is a day, oldest on the left; a tick means it counted. "
                                          + "Today's dot fills as you focus."
                                          + (StreakStatus.outrunsDots(streak: store.streak, todayCounts: todayCounts,
                                                                      dots: past.count + 1)
                                             ? " Showing the last \(past.count + 1) days." : ""))]) {
            HStack(spacing: 3.zoomed) {
                ForEach(Array(past.enumerated()), id: \.offset) { _, entry in
                    streakDot(filled: entry.met ? 1 : 0)
                }
                streakDot(filled: min(1, today / max(1, minimum)), isToday: true)
            }
            // The strip's news is which days met the minimum; the streak
            // length is already the card's trailing figure.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Days met")
            .accessibilityValue("\(past.filter(\.met).count + (todayCounts ? 1 : 0)) of the last \(past.count + 1)"
                                + (todayCounts ? ", today included" : ", today still open"))
            if let first = past.first {
                HStack {
                    Text(Tokens.dayLabel(first.day))
                    Spacer(minLength: Tokens.Space.xs)
                    Text("Today")
                }
                .font(Tokens.Typography.caption)
                .foregroundStyle(StoryStyle.supportingInk)
                .accessibilityHidden(true)
            }
            // The link has its own line beneath the sentence: beside it, it
            // read as the sentence's last words once the sentence wrapped.
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(durations: StreakStatus.line(streak: store.streak, today: today, minimum: minimum))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
                // The link style lifts the target to 28pt; the negative
                // padding keeps the row where the 15pt word had it.
                Button("Awards") { navigation.openSheet(.awards) }
                    .buttonStyle(StoryLinkStyle())
                    .padding(.vertical, -7.zoomed)
                    .coachAnchor(.awards)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One day of the streak. A counted day is filled and ticked, so it reads
    /// without colour; today is outlined and fills as focus accrues, so an
    /// unfinished today never looks like a missed day.
    private func streakDot(filled: Double, isToday: Bool = false) -> some View {
        let shape = Capsule(style: .continuous)
        return shape.fill(Tokens.Colour.elevated)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    shape.fill(Tokens.Colour.focus).frame(width: geometry.size.width * filled)
                }
            }
            .overlay {
                if filled >= 1 {
                    Image(systemName: "checkmark")
                        .font(Tokens.Typography.micro)
                        .foregroundStyle(Tokens.Colour.onFocus)
                }
            }
            .overlay { if isToday { shape.strokeBorder(Tokens.Colour.focus, lineWidth: 1.5.zoomed) } }
            .clipShape(shape)
            .frame(height: 12.zoomed)
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
    /// What the tile means, behind a circled "i" beside the trailing label:
    /// the explanation is one click away instead of lines under the chart.
    var info: [HelpEntry] = []
    @ViewBuilder let content: Content
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.storyTileMoves) private var moves

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text(title)
                    .font(Tokens.Typography.label)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Tokens.Space.xs)
                if let trailing {
                    // Any card may put a duration here; it is spoken in words.
                    Text(durations: trailing)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                        .lineLimit(1)
                }
                if !info.isEmpty { InfoMark(title: title, entries: info) }
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
        .padding(.vertical, Tokens.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
