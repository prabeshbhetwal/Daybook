import SwiftUI
import AppKit

/// `NSDatePicker` reports a 20–24 pt intrinsic height even when a SwiftUI frame
/// around it is taller. Publishing the practical minimum from the native view
/// makes both its real target and its accessibility frame grow with it.
final class HistoryNSDatePicker: NSDatePicker {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = max(size.height, AccessibilityMetrics.minimumTargetSize)
        return size
    }
}

struct HistoryNativeDatePicker: NSViewRepresentable {
    let label: String
    @Binding var selection: Date
    let range: ClosedRange<Date>

    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> HistoryNSDatePicker {
        let picker = HistoryNSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.controlSize = .large
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        configure(picker, coordinator: context.coordinator)
        return picker
    }

    func updateNSView(_ picker: HistoryNSDatePicker, context: Context) {
        configure(picker, coordinator: context.coordinator)
    }

    private func configure(_ picker: HistoryNSDatePicker, coordinator: Coordinator) {
        coordinator.selection = $selection
        if picker.dateValue != selection { picker.dateValue = selection }
        picker.minDate = range.lowerBound
        picker.maxDate = range.upperBound
        picker.setAccessibilityLabel("\(label) date")
        picker.setAccessibilityHelp("Selected History date")
    }
}

/// Visible context plus one native keyboard/VoiceOver date target. The label is
/// hidden from accessibility because the native control already carries it.
struct HistoryDateControl: View {
    let label: String
    @Binding var selection: Date
    let range: ClosedRange<Date>

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            Text(label)
                .accessibilityHidden(true)
            HistoryNativeDatePicker(label: label, selection: $selection, range: range)
                .fixedSize()
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

/// The History range as one readable phrase. Endpoints are sorted for display
/// only — the stored filter is never rewritten — and the year is stated once
/// unless the range actually spans two. Australian English, so the compact
/// control reads the same on every machine.
struct HistoryRangePresentation: Equatable {
    let label: String
    let accessibilityLabel: String

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = format
        return formatter
    }

    init(start: Date, end: Date, calendar: Calendar = .current) {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        let day = Self.formatter("d MMM")
        let dayYear = Self.formatter("d MMM yyyy")
        let spoken = Self.formatter("EEEE d MMMM yyyy")

        if calendar.isDate(first, inSameDayAs: last) {
            label = dayYear.string(from: first)
        } else if calendar.component(.year, from: first)
                    == calendar.component(.year, from: last) {
            label = "\(day.string(from: first)) – \(dayYear.string(from: last))"
        } else {
            label = "\(dayYear.string(from: first)) – \(dayYear.string(from: last))"
        }
        accessibilityLabel = "History range, from \(spoken.string(from: first)) "
            + "to \(spoken.string(from: last))"
    }
}

/// Fixed widths for the numeric columns, shared by the header and every row so
/// the figures form readable columns instead of drifting with content.
enum HistoryTableLayout {
    static let trackedWidth: CGFloat = 88
    static let focusedWidth: CGFloat = 88
    static let sessionWidth: CGFloat = 72
    /// Reserved for the row disclosure, so the header's last column lines up.
    static let disclosureWidth: CGFloat = 14
}

/// The selected History row owns its detail. Keeping this compact state in one
/// presentation value makes the arrow, action and joined visual surface move
/// together rather than leaving a row to imply one state and its content another.
struct HistoryDayDisclosurePresentation: Equatable {
    let isExpanded: Bool

    var chevronSystemName: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }

    var usesJoinedSurface: Bool { isExpanded }
}

/// One compact summary of the selected range that opens a focused choice
/// surface. The permanent stepper pair it replaces put two spin controls in the
/// filter bar for a value the user changes rarely.
struct HistoryRangeControl: View {
    @Binding var start: Date
    @Binding var end: Date
    let bounds: ClosedRange<Date>
    let onReset: () -> Void
    var goal: TimeInterval = 0
    var facts: (Date) -> [Date: DayFacts] = { _ in [:] }
    var chrome = false
    @StateObject private var shown = BoolBox()

    private var presentation: HistoryRangePresentation {
        HistoryRangePresentation(start: start, end: end)
    }

    var body: some View {
        Button {
            shown.value.toggle()
        } label: {
            // In the chrome it is the period label every workspace has, in
            // the same place and the same type; in a page it is a pill.
            if chrome {
                HStack(spacing: Tokens.Space.xs) {
                    Text(presentation.label)
                        .font(Tokens.Typography.rowTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(Tokens.Typography.microLabel.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Tokens.Space.s)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: Tokens.Space.xs) {
                    Image(systemName: "calendar")
                        .accessibilityHidden(true)
                    Text(presentation.label)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(Tokens.Typography.microLabel)
                        .accessibilityHidden(true)
                }
                .font(Tokens.Typography.metadata)
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.elevated, in: Capsule())
                .overlay(Capsule().strokeBorder(Tokens.Colour.line))
            }
        }
        .buttonStyle(StoryPressStyle())
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint("Choose the History date range")
        .popover(isPresented: Binding(get: { shown.value },
                                      set: { shown.value = $0 }),
                 arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        HistoryRangePopover(start: $start, end: $end, bounds: bounds, onReset: onReset,
                            goal: goal, facts: facts)
    }
}

/// The History range, chosen on the app's own calendar: the one the chrome
/// opens to jump to a day, here picking a first and a last day. Quick spans
/// sit above it; everything applies as it is picked.
struct HistoryRangePopover: View {
    @Binding var start: Date
    @Binding var end: Date
    let bounds: ClosedRange<Date>
    let onReset: () -> Void
    var goal: TimeInterval = 0
    var facts: (Date) -> [Date: DayFacts] = { _ in [:] }
    @StateObject private var revision = HistoryRangeRevision()

    private var presentation: HistoryRangePresentation {
        HistoryRangePresentation(start: start, end: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(presentation.label)
                        .font(Tokens.Typography.sectionTitle)
                        .contentTransition(.numericText())
                    Spacer(minLength: Tokens.Space.l)
                    Button("All dates") {
                        onReset()
                        revision.value += 1
                    }
                    .buttonStyle(StoryLinkStyle())
                }
                ChipFlow(spacing: Tokens.Space.xs) {
                    ForEach(HistoryRangePreset.allCases) { preset in
                        presetChip(preset)
                    }
                }
            }
            .padding([.top, .horizontal], Tokens.Space.l)
            DayPickerCalendar(range: min(start, end)...max(start, end),
                              earliest: bounds.lowerBound, goal: goal, facts: facts) { first, last in
                start = first
                end = last
            }
            // Rebuilt only when a preset moves the range, so it opens on that
            // month; picking days must not rebuild the grid under the pointer.
            .id(revision.value)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func presetChip(_ preset: HistoryRangePreset) -> some View {
        let range = preset.range(within: bounds)
        let isCurrent = Calendar.current.isDate(range.lowerBound, inSameDayAs: min(start, end))
            && Calendar.current.isDate(range.upperBound, inSameDayAs: max(start, end))
        return Button(preset.title) {
            start = range.lowerBound
            end = range.upperBound
            revision.value += 1
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: 14))
        .font(Tokens.Typography.metadata.weight(isCurrent ? .semibold : .regular))
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: 28)
        .background(isCurrent ? Tokens.Colour.focus.opacity(0.14) : Tokens.Colour.elevated, in: Capsule())
        .foregroundStyle(isCurrent ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(.primary))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Counts preset applications, which are the only reason to rebuild the grid.
final class HistoryRangeRevision: ObservableObject {
    @Published var value = 0
}

/// The spans people actually ask for, clamped to the days History has.
enum HistoryRangePreset: String, CaseIterable, Identifiable {
    case week, month, thisMonth, lastMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        }
    }

    func range(within bounds: ClosedRange<Date>, now: Date = Date(),
               calendar: Calendar = .current) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let raw: (Date, Date)
        switch self {
        case .week:
            raw = (calendar.date(byAdding: .day, value: -6, to: today) ?? today, today)
        case .month:
            raw = (calendar.date(byAdding: .day, value: -29, to: today) ?? today, today)
        case .thisMonth:
            let first = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            raw = (first, today)
        case .lastMonth:
            let first = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let previous = calendar.date(byAdding: .month, value: -1, to: first) ?? first
            let last = calendar.date(byAdding: .day, value: -1, to: first) ?? first
            raw = (previous, last)
        }
        let lower = min(max(raw.0, bounds.lowerBound), bounds.upperBound)
        let upper = min(max(raw.1, lower), bounds.upperBound)
        return lower...upper
    }
}

/// Search and intersection filters over canonical day rows, laid out as the
/// story window is: the days to scan in the column, the picked day in the
/// rail. Controls only select evidence; nothing here edits, repairs or exports.
struct HistoryView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scrolls = true
    /// The main window's bar carries the range where every workspace keeps
    /// its period; a sheet has no such bar and keeps the control in the page.
    var rangeInChrome = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            pane { column }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(StoryStyle.canvas)
            Divider()
            pane { rail }
                .frame(width: StoryLayout.railWidth)
                .background(StoryStyle.rail)
        }
        .background(Tokens.Colour.ground)
    }

    @ViewBuilder private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Column

    /// A search or a filter reaches across the whole archive; otherwise the
    /// list is the window the chrome is paged to.
    private var searching: Bool { rangeInChrome && store.historyFilter.isActive }

    private var visibleDays: [HistoryDay] {
        let days = store.filteredHistoryDays
        guard rangeInChrome, !searching, let window = navigation.historyWindow else { return days }
        return days.filter { window.contains($0.date) }
    }

    private var column: some View {
        let days = visibleDays
        return VStack(alignment: .leading, spacing: Tokens.Space.l) {
            StoryHeadline(eyebrow: eyebrow, sentence: sentence(days), facts: facts(days),
                          highlight: Tokens.duration(days.reduce(0) { $0 + $1.focused }))
            ForEach(store.historyIntegrityNotices, id: \.self) { notice in
                IntegrityNotice(notice)
            }
            filterBar
            if store.historyDays.isEmpty {
                EmptyState("No recorded history yet",
                           detail: "Tracked days and focus sessions will appear here locally.",
                           icon: "calendar")
            } else if days.isEmpty, searching || !rangeInChrome {
                EmptyState("No matching days",
                           detail: "Clear one of the intersecting filters or search for something else.",
                           icon: "line.3.horizontal.decrease.circle")
            } else if days.isEmpty {
                EmptyState("Nothing recorded in \(navigation.historyWindowLabel)",
                           detail: "Use the arrows above to page to another period, or search for a day.",
                           icon: "calendar")
            } else {
                dayList(days)
            }
        }
        .padding(StoryStyle.columnInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var eyebrow: String {
        guard rangeInChrome else { return "History" }
        if searching { return "History · matches" }
        return navigation.historyScope == .month ? "History · every month" : "History · \(navigation.historyWindowLabel)"
    }

    private func sentence(_ days: [HistoryDay]) -> String {
        guard !store.historyDays.isEmpty else { return "Your recorded days will gather here." }
        if days.isEmpty {
            return searching || !rangeInChrome ? "No day matches these filters."
                : "Nothing was recorded in \(navigation.historyWindowLabel)."
        }
        let focused = days.reduce(0) { $0 + $1.focused }
        let dayWord = days.count == 1 ? "day" : "days"
        let scope = store.historyFilter.isActive ? "matching " : ""
        let where_ = rangeInChrome && !searching && navigation.historyScope != .month
            ? " in \(navigation.historyWindowLabel)" : " on record"
        guard focused > 0 else {
            return "\(days.count) \(scope)\(dayWord)\(where_), with no focus session."
        }
        return "\(days.count) \(scope)\(dayWord)\(where_), \(Tokens.duration(focused)) of focus between them."
    }

    private func facts(_ days: [HistoryDay]) -> [String] {
        guard let newest = days.first?.date, let oldest = days.last?.date else { return [] }
        var parts = [Tokens.dateRange(oldest, newest)]
        let sessions = days.reduce(0) { $0 + $1.sessions }
        if sessions > 0 { parts.append(sessions == 1 ? "1 session" : "\(sessions) sessions") }
        return parts
    }

    /// Days under the month they fall in, newest first. Each month states its
    /// own total, so a long list still has landmarks.
    @ViewBuilder private func dayList(_ days: [HistoryDay]) -> some View {
        if navigation.historyScope == .day {
            dayRows(days)
        } else {
            periodRows(days)
        }
    }

    /// One row per day, newest first, under the month it falls in.
    private func dayRows(_ days: [HistoryDay]) -> some View {
        let months = HistoryMonthGroup.group(days)
        return LazyVStack(alignment: .leading, spacing: Tokens.Space.l, pinnedViews: []) {
            HistoryStripAxis()
            ForEach(months) { month in
                VStack(alignment: .leading, spacing: 2) {
                    // A month name is a landmark in search results that span
                    // months; a page that is one month already says so above.
                    if searching || !rangeInChrome {
                        Text(month.title)
                            .font(Tokens.Typography.metadata.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Tokens.Space.s)
                            .padding(.bottom, Tokens.Space.xs)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(month.days) { day in
                        HistoryDayRow(day: day,
                                      projection: store.storyDayProjection(on: day.date),
                                      context: dayContext(day),
                                      isSelected: isSelected(day)) {
                            withAnimation(Tokens.Motion.animation(Tokens.Motion.selection,
                                                                  reduceMotion: reduceMotion)) {
                                if isSelected(day) {
                                    navigation.clearReviewDay()
                                } else {
                                    ReviewDayRoute.select(store: store, navigation: navigation)(day.date)
                                }
                            }
                        } onOpen: {
                            navigation.openStory(.day, containing: day.date)
                        }
                    }
                }
            }
        }
        .onMoveCommand { direction in moveSelection(direction, in: days) }
    }

    /// One row per week or month, newest first, each day a small bar on one
    /// shared scale.
    private func periodRows(_ days: [HistoryDay]) -> some View {
        let periods = HistoryPeriodGroup.group(days, scope: navigation.historyScope)
        let peak = days.map(\.focused).max() ?? 0
        return LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(periods) { period in
                HistoryPeriodRow(period: period, peak: peak,
                                 isSelected: navigation.historySelectedPeriod == period.start) {
                    withAnimation(Tokens.Motion.animation(Tokens.Motion.selection,
                                                          reduceMotion: reduceMotion)) {
                        navigation.historySelectedPeriod =
                            navigation.historySelectedPeriod == period.start ? nil : period.start
                    }
                } onOpen: {
                    // One level down the ladder; the story is in the rail.
                    navigation.zoomHistory(into: period.start)
                }
            }
        }
    }

    /// Up and down walk the picked day through the list, as a native list does.
    private func moveSelection(_ direction: MoveCommandDirection, in days: [HistoryDay]) {
        guard direction == .up || direction == .down, !days.isEmpty else { return }
        let current = days.firstIndex(where: isSelected)
        let next: Int
        if let current {
            next = min(days.count - 1, max(0, current + (direction == .down ? 1 : -1)))
        } else {
            next = 0
        }
        ReviewDayRoute.select(store: store, navigation: navigation)(days[next].date)
    }

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s) {
                searchField
                if !rangeInChrome { rangeControl }
                appMenu
                workTypeMenu
                clearFilters
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                searchField
                HStack(spacing: Tokens.Space.s) {
                    if !rangeInChrome { rangeControl }
                    appMenu
                    workTypeMenu
                    clearFilters
                }
            }
        }
    }

    @ViewBuilder private var rangeControl: some View {
        if !store.historyDays.isEmpty {
            HistoryRangeControl(start: startBinding, end: endBinding,
                                bounds: dateBounds,
                                onReset: { store.resetHistoryRange() },
                                goal: store.goal.goal,
                                facts: { store.dayFacts(inMonthOf: $0) })
        }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search date, app or category", text: queryBinding)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: 32)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                         style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                  style: .continuous)
            .strokeBorder(Tokens.Colour.line))
        .accessibilityLabel("Search History")
    }

    @ViewBuilder private var clearFilters: some View {
        if store.historyFilter.isActive {
            Button("Clear filters") { store.clearHistoryFilters() }
                .buttonStyle(StoryLinkStyle())
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        }
    }

    private var appMenu: some View {
        Menu {
            Button("All apps") { store.setHistoryApp(nil) }
            Divider()
            ForEach(store.historyAppBundleIDs, id: \.self) { bundleID in
                Button(store.historyAppName(for: bundleID)) {
                    store.setHistoryApp(bundleID)
                }
            }
        } label: {
            Label(store.historyFilter.appBundleID.map(store.historyAppName(for:)) ?? "All apps",
                  systemImage: "app")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("App filter, selected "
                            + (store.historyFilter.appBundleID.map(store.historyAppName(for:))
                               ?? "all apps"))
    }

    private var workTypeMenu: some View {
        Menu {
            Button { store.setHistoryWorkType(nil) } label: {
                Label("All categories", systemImage: "square.grid.2x2")
                    .labelStyle(.titleAndIcon)
            }
            Divider()
            ForEach(WorkType.allCases) { type in
                Button { store.setHistoryWorkType(type) } label: {
                    Label(type.displayName, systemImage: type.symbolName)
                        .labelStyle(.titleAndIcon)
                }
            }
        } label: {
            Label(store.historyFilter.workType?.displayName ?? "All categories",
                  systemImage: store.historyFilter.workType?.symbolName ?? "square.grid.2x2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("Category filter, selected "
                            + (store.historyFilter.workType?.displayName ?? "all categories"))
    }

    // MARK: - Rail

    /// The same canonical detail a chart selection opens. Nil unless the
    /// selected day survives the active filters.
    private var selectedDayProjection: StoryDayProjection? {
        guard let date = navigation.reviewSelectedDate,
              store.reviewDayIsAvailable(date, section: .history) else { return nil }
        return store.storyDayProjection(on: date)
    }

    private var selectedPeriod: HistoryPeriodGroup? {
        guard navigation.historyScope != .day, let start = navigation.historySelectedPeriod else { return nil }
        return HistoryPeriodGroup.group(visibleDays, scope: navigation.historyScope)
            .first { $0.start == start }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if let period = selectedPeriod {
                HistoryPeriodPreview(store: store, period: period,
                                     zoomTitle: navigation.historyScope == .month ? "Show its weeks" : "Show its days",
                                     onZoom: { navigation.zoomHistory(into: period.start) }) {
                    navigation.openStory(navigation.historyScope == .week ? .week : .month,
                                         containing: period.start)
                }
                .id(period.id)
                .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            } else if navigation.historyScope == .day, let projection = selectedDayProjection {
                HistoryDayPreview(store: store, projection: projection) {
                    navigation.openStory(.day, containing: projection.date)
                }
                .id(projection.id)
                .accessibilityIdentifier("history-story-detail-content-\(projection.id)")
                .storyRenderEvidence(.historyDetail)
                .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            } else if !store.filteredHistoryDays.isEmpty {
                let unit = navigation.historyScope.title.lowercased()
                StoryTile(title: "Pick a \(unit)", trailing: nil) {
                    Text(navigation.historyScope == .day
                         ? "Select a day to see its sessions, apps and notes here. Double-click one to open it as a story."
                         : "Select a \(unit) to see its days and apps here. Double-click one to see "
                           + (navigation.historyScope == .month ? "its weeks." : "its days."))
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSelected(_ day: HistoryDay) -> Bool {
        guard let selected = navigation.reviewSelectedDate else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: selected)
    }

    private func dayContext(_ day: HistoryDay) -> String {
        var types = day.workTypes
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
        if let selected = store.historyFilter.workType?.displayName,
           let index = types.firstIndex(of: selected) {
            types.insert(types.remove(at: index), at: 0)
        }
        var apps = day.appBundleIDs
            .map(store.historyAppName(for:))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if let selectedID = store.historyFilter.appBundleID {
            let selected = store.historyAppName(for: selectedID)
            if let index = apps.firstIndex(of: selected) {
                apps.insert(apps.remove(at: index), at: 0)
            }
        }
        let typeText = types.isEmpty ? nil : types.joined(separator: ", ")
        let appText = apps.isEmpty ? nil : apps.prefix(3).joined(separator: ", ")
            + (apps.count > 3 ? " +\(apps.count - 3)" : "")
        return [typeText, appText].compactMap { $0 }.joined(separator: " · ")
    }

    private var queryBinding: Binding<String> {
        Binding(get: { store.historyFilter.query }, set: store.setHistoryQuery)
    }

    private var startBinding: Binding<Date> {
        Binding(get: { store.historyRangeStart ?? dateBounds.lowerBound },
                set: { store.historyRangeStart = $0 })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { store.historyRangeEnd ?? dateBounds.upperBound },
                set: { store.historyRangeEnd = $0 })
    }

    private var dateBounds: ClosedRange<Date> {
        let oldest = store.historyDays.last?.date ?? Date()
        let newest = store.historyDays.first?.date ?? oldest
        return oldest...newest
    }
}

/// History's range where the Story keeps its period: the bar's centre, opening
/// the same calendar.
struct HistoryChromeRange: View {
    @ObservedObject var store: SessionStore

    private var bounds: ClosedRange<Date> {
        let oldest = store.historyDays.last?.date ?? Date()
        let newest = store.historyDays.first?.date ?? oldest
        return oldest...newest
    }

    var body: some View {
        if !store.historyDays.isEmpty {
            HistoryRangeControl(
                start: Binding(get: { store.historyRangeStart ?? bounds.lowerBound },
                               set: { store.historyRangeStart = $0 }),
                end: Binding(get: { store.historyRangeEnd ?? bounds.upperBound },
                             set: { store.historyRangeEnd = $0 }),
                bounds: bounds,
                onReset: { store.resetHistoryRange() },
                goal: store.goal.goal,
                facts: { store.dayFacts(inMonthOf: $0) },
                chrome: true)
        }
    }
}
