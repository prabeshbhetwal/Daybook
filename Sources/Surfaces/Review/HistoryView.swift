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

/// History finds anything and shows everything. Without a query the column
/// is the map: every day on record, a year per block. With one it is the
/// sessions that matched, across the whole archive. The rail holds whatever
/// is picked, and the archive's own totals. Reading a period closely is the
/// Story's job; nothing here pages through time.
struct HistoryView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scrolls = true
    /// The day under the pointer on the map, echoed in the caption.
    @StateObject private var hoveredDay = HoverBox()
    /// The session hit picked from search results.
    @StateObject private var pickedHit = HoverBox()

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
        .onChange(of: store.historyFilter) { _ in pickedHit.id = nil }
    }

    @ViewBuilder private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var searching: Bool { store.historyFilter.isActive }
    private var facts: HistoryArchiveFacts { store.historyArchiveFacts() }

    // MARK: - Column

    private var column: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            StoryHeadline(eyebrow: searching ? "History · matches" : "History · everything on record",
                          sentence: sentence, facts: headlineFacts,
                          highlight: Tokens.duration(facts.focused))
            ForEach(store.historyIntegrityNotices, id: \.self) { notice in
                IntegrityNotice(notice)
            }
            filterBar
            if store.historyDays.isEmpty {
                EmptyState("No recorded history yet",
                           detail: "Tracked days and focus sessions will appear here locally.",
                           icon: "calendar")
            } else if searching {
                results
            } else {
                map
            }
        }
        .padding(StoryStyle.columnInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion), value: searching)
    }

    private var sentence: String {
        guard !store.historyDays.isEmpty else { return "Your recorded days will gather here." }
        if searching {
            let hits = store.historySearchHits()
            guard !hits.isEmpty else { return "No session matches." }
            let word = hits.count == 1 ? "session matches" : "sessions match"
            return "\(hits.count) \(word), \(Tokens.duration(hits.reduce(0) { $0 + $1.worked })) of focus between them."
        }
        let days = facts.dayCount == 1 ? "1 day" : "\(facts.dayCount) days"
        let sessions = facts.sessionCount == 1 ? "1 session" : "\(facts.sessionCount) sessions"
        guard facts.focused > 0 else { return "\(days) on record, with no focus session yet." }
        var text = "\(days) on record, \(sessions), \(Tokens.duration(facts.focused)) of focus"
        if let first = facts.firstDay { text += " since \(Tokens.longDate(first))" }
        return text + "."
    }

    private var headlineFacts: [String] {
        guard !searching else { return [] }
        var parts: [String] = []
        if let best = facts.bestMonth {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = "MMMM yyyy"
            parts.append("best month \(formatter.string(from: best.start)), \(Tokens.duration(best.focused))")
        }
        if facts.longestStreak > 1 { parts.append("longest streak \(facts.longestStreak) days") }
        return parts
    }

    /// The map: a block per year, newest first.
    private var map: some View {
        let today = Calendar.current.startOfDay(for: store.now())
        return VStack(alignment: .leading, spacing: Tokens.Space.l) {
            ForEach(facts.years(now: store.now()), id: \.self) { year in
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(year))
                            .font(Tokens.Typography.metadata.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: Tokens.Space.m)
                        Text("\(Tokens.duration(facts.focused(inYear: year))) focused")
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HistoryYearMap(year: year, facts: facts, goal: store.goal.goal, today: today,
                                   selected: selectedSpan,
                                   onHover: { hoveredDay.id = $0?.description },
                                   onPick: { day, extends in pick(day, extending: extends) })
                }
            }
            Text(mapCaption)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mapCaption: String {
        if let id = hoveredDay.id, let day = facts.focusByDay.keys.first(where: { $0.description == id })
            ?? facts.trackedByDay.keys.first(where: { $0.description == id }) {
            let focused = facts.focusByDay[day] ?? 0, tracked = facts.trackedByDay[day] ?? 0
            var parts = [Tokens.longDate(day)]
            if focused > 0 { parts.append("\(Tokens.duration(focused)) focused") }
            if tracked > 0 { parts.append("\(Tokens.duration(tracked)) recorded app use") }
            return parts.joined(separator: " · ") + "."
        }
        let scale = store.goal.goal > 0 ? "a stronger square is more of your \(Tokens.duration(store.goal.goal)) daily goal"
                                        : "a stronger square is more focus"
        return "Each square is a day; \(scale). Click a day to preview it; shift-click another to preview the span between them."
    }

    /// The days picked on the map: one, or a shift-extended span.
    private var selectedSpan: ClosedRange<Date>? {
        guard let start = navigation.reviewSelectedDate else { return nil }
        let end = navigation.historySelectedPeriod ?? start
        return min(start, end)...max(start, end)
    }

    private func pick(_ day: Date, extending: Bool) {
        withAnimation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion)) {
            if extending, navigation.reviewSelectedDate != nil {
                navigation.historySelectedPeriod = day
            } else if navigation.reviewSelectedDate == day, navigation.historySelectedPeriod == nil {
                navigation.clearReviewDay()
            } else {
                navigation.selectReviewDay(day)
                navigation.historySelectedPeriod = nil
            }
        }
    }

    /// Matches across the archive, under the month they fall in.
    private var results: some View {
        let hits = store.historySearchHits()
        let months = HistoryHitMonth.group(hits)
        return LazyVStack(alignment: .leading, spacing: Tokens.Space.l) {
            if hits.isEmpty {
                EmptyState("No matching sessions",
                           detail: "Try a session name, a word from a note, an app, a category or a date.",
                           icon: "magnifyingglass")
            }
            ForEach(months) { month in
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.title)
                        .font(Tokens.Typography.metadata.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.bottom, Tokens.Space.xs)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(month.hits) { hit in
                        HistoryHitRow(hit: hit, isSelected: pickedHit.id == hit.id.uuidString) {
                            withAnimation(Tokens.Motion.animation(Tokens.Motion.selection,
                                                                  reduceMotion: reduceMotion)) {
                                let id = hit.id.uuidString
                                pickedHit.id = pickedHit.id == id ? nil : id
                                if pickedHit.id != nil { navigation.selectReviewDay(hit.day) } else { navigation.clearReviewDay() }
                            }
                        } onOpen: {
                            navigation.openStory(.day, containing: hit.day)
                        }
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s) {
                searchField
                appMenu
                workTypeMenu
                clearFilters
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                searchField
                HStack(spacing: Tokens.Space.s) {
                    appMenu
                    workTypeMenu
                    clearFilters
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search sessions, notes, apps, categories or dates", text: queryBinding)
                .textFieldStyle(.plain)
            if !store.historyFilter.query.isEmpty {
                Button { store.setHistoryQuery("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
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
            Button("Clear") { store.clearHistoryFilters() }
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

    private var selectedDayProjection: StoryDayProjection? {
        guard let date = navigation.reviewSelectedDate else { return nil }
        return store.storyDayProjection(on: date)
    }

    /// A shift-extended span on the map, as the days History has for it.
    private var selectedSpanGroup: HistoryPeriodGroup? {
        guard let span = selectedSpan, span.lowerBound != span.upperBound else { return nil }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: span.upperBound) ?? span.upperBound
        let days = store.historyDays.filter { span.contains(calendar.startOfDay(for: $0.date)) }
        return HistoryPeriodGroup(scope: .week, start: span.lowerBound, end: end, days: days,
                                  customTitle: Tokens.dateRange(span.lowerBound, span.upperBound))
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if let span = selectedSpanGroup {
                HistoryPeriodPreview(store: store, period: span) {
                    navigation.openStory(.week, containing: span.start)
                }
                .id(span.id)
                .accessibilityIdentifier("history-story-detail-content-span")
                .storyRenderEvidence(.historyDetail)
                .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            } else if let projection = selectedDayProjection {
                HistoryDayPreview(store: store, projection: projection) {
                    navigation.openStory(.day, containing: projection.date)
                }
                .id(projection.id)
                .accessibilityIdentifier("history-story-detail-content-\(projection.id)")
                .storyRenderEvidence(.historyDetail)
                .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            }
            if !store.historyDays.isEmpty {
                archiveTiles
            }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The archive's own figures, always present under whatever is picked.
    @ViewBuilder private var archiveTiles: some View {
        StoryTile(title: "On record", trailing: facts.firstDay.map { "since \(Self.sinceLabel($0))" }) {
            Text(Tokens.preciseDuration(facts.focused))
                .font(Tokens.Typography.metricValue.monospacedDigit())
            Text(archiveNote)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !facts.categories.isEmpty {
            StoryTile(title: "All-time categories", trailing: nil) {
                CategoryShareBar(shares: facts.categories)
            }
        }
        if !facts.apps.isEmpty {
            StoryTile(title: facts.apps.count > 4 ? "All-time top 4 apps" : "All-time apps",
                      trailing: facts.apps.count == 1 ? "1 recorded" : "\(facts.apps.count) recorded") {
                ForEach(Array(facts.apps.prefix(4).enumerated()), id: \.element.id) { index, app in
                    StoryAppRow(app: app, rank: index)
                }
            }
        }
    }

    private var archiveNote: String {
        var parts = [facts.dayCount == 1 ? "1 day" : "\(facts.dayCount) days",
                     facts.sessionCount == 1 ? "1 session" : "\(facts.sessionCount) sessions"]
        if facts.longestStreak > 1 { parts.append("longest streak \(facts.longestStreak) days") }
        return parts.joined(separator: " · ")
    }

    private static func sinceLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private var queryBinding: Binding<String> {
        Binding(get: { store.historyFilter.query }, set: store.setHistoryQuery)
    }
}

/// Search hits under the month they fall in, newest first.
struct HistoryHitMonth: Identifiable {
    let start: Date
    let hits: [HistorySearchHit]
    var id: Date { start }

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: start)
    }

    static func group(_ hits: [HistorySearchHit], calendar: Calendar = .current) -> [HistoryHitMonth] {
        var groups: [HistoryHitMonth] = []
        var current: [HistorySearchHit] = []
        var open: Date?
        for hit in hits {
            let start = calendar.dateInterval(of: .month, for: hit.day)?.start ?? hit.day
            if let openStart = open, openStart != start {
                groups.append(HistoryHitMonth(start: openStart, hits: current))
                current = []
            }
            open = start
            current.append(hit)
        }
        if let openStart = open, !current.isEmpty { groups.append(HistoryHitMonth(start: openStart, hits: current)) }
        return groups
    }
}

/// One matched session: when, what, which category, how long, and the words
/// that matched when they were not in the name.
struct HistoryHitRow: View {
    let hit: HistorySearchHit
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: HistoryRowLayout.spacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Calendar.current.component(.day, from: hit.start))")
                        .font(Tokens.Typography.sectionTitle.monospacedDigit())
                    Text(Tokens.weekdayName(hit.start).prefix(3).uppercased())
                        .font(Tokens.Typography.microLabel)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                                                    : AnyShapeStyle(.secondary))
                }
                .frame(width: HistoryRowLayout.dateWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(hit.name)
                            .font(Tokens.Typography.rowTitle.weight(.medium))
                            .lineLimit(1)
                        WorkTypeChip(workType: hit.workType)
                    }
                    Text(detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.s)
                Text(Tokens.duration(hit.worked))
                    .font(Tokens.Typography.rowTitle.weight(.semibold).monospacedDigit())
                    .frame(width: HistoryRowLayout.figureWidth, alignment: .trailing)
            }
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .accessibilityLabel("\(hit.name), \(hit.workType.displayName), \(Tokens.longDate(hit.start)), "
                            + "\(Tokens.spent(hit.worked))" + (isSelected ? ", selected" : ""))
        .accessibilityHint(isSelected ? "Clears the preview" : "Previews this day beside the list")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open as a story", onOpen)
    }

    private var detail: String {
        var parts = [Tokens.timeRange(hit.start, hit.end)]
        if let note = hit.noteSnippet { parts.append("“\(note)”") }
        if !hit.matchedApps.isEmpty { parts.append(hit.matchedApps.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
