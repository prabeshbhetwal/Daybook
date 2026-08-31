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
    @StateObject private var shown = BoolBox()

    private var presentation: HistoryRangePresentation {
        HistoryRangePresentation(start: start, end: end)
    }

    var body: some View {
        Button {
            shown.value.toggle()
        } label: {
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: "calendar")
                    .accessibilityHidden(true)
                Text(presentation.label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(Tokens.Typography.metadata)
            .padding(.horizontal, Tokens.Space.m)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(Tokens.Colour.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Tokens.Colour.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint("Choose the History date range")
        .popover(isPresented: Binding(get: { shown.value },
                                      set: { shown.value = $0 }),
                 arrowEdge: .bottom) {
            popoverContent
        }
    }

    /// A temporary choice surface: a reset, two native date targets, and the
    /// selected range in words. Native controls apply immediately, so there is
    /// nothing to stage behind an Apply action.
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text("Date range")
                    .font(Tokens.Typography.sectionTitle)
                Spacer(minLength: Tokens.Space.l)
                Button("All dates", action: onReset)
                    .buttonStyle(.borderless)
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            }
            HistoryDateControl(label: "From", selection: $start, range: bounds)
            HistoryDateControl(label: "To", selection: $end, range: bounds)
            Text(presentation.accessibilityLabel)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.l)
        .frame(minWidth: 260)
    }
}

/// Search and intersection filters over canonical day rows. Controls only
/// select evidence; there are deliberately no edit, repair or export actions.
struct HistoryView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            ForEach(store.historyIntegrityNotices, id: \.self) { notice in
                IntegrityNotice(notice)
            }
            SurfacePanel(showsHeader: false) {
                SectionHeader(title: "History filters",
                              trailing: resultLabel)
                filterBar
                if let activeFilterSummary {
                    Text(activeFilterSummary)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }

            SurfacePanel(showsHeader: false) {
                SectionHeader(title: "Days", trailing: "newest first")
                if store.historyDays.isEmpty {
                    EmptyState("No recorded history yet",
                               detail: "Tracked days and focus sessions will appear here locally.",
                               icon: "calendar")
                } else if store.filteredHistoryDays.isEmpty {
                    EmptyState("No matching days",
                               detail: "Adjust the date range or clear one of the intersecting filters.",
                               icon: "line.3.horizontal.decrease.circle")
                } else {
                    tableHeader
                    ForEach(Array(store.filteredHistoryDays.enumerated()),
                            id: \.element.id) { index, day in
                        if index > 0 { Divider() }
                        historyDayEntry(day)
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s) {
                searchField
                rangeControl
                appMenu
                workTypeMenu
                clearFilters
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                searchField
                HStack(spacing: Tokens.Space.s) {
                    rangeControl
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
                                onReset: { store.resetHistoryRange() })
        }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search date, app or work type", text: queryBinding)
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
                .buttonStyle(.borderless)
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
            Button("All work types") { store.setHistoryWorkType(nil) }
            Divider()
            ForEach(WorkType.allCases, id: \.rawValue) { type in
                Button(type.displayName) { store.setHistoryWorkType(type) }
            }
        } label: {
            Label(store.historyFilter.workType?.displayName ?? "All work types",
                  systemImage: "square.grid.2x2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("Work type filter, selected "
                            + (store.historyFilter.workType?.displayName ?? "all work types"))
    }

    /// The same canonical detail a chart selection opens. Nil unless the
    /// selected day survives the active filters.
    private var selectedDayDetail: ReviewDayDetail? {
        guard let date = navigation.reviewSelectedDate,
              store.reviewDayIsAvailable(date, section: .history) else { return nil }
        return store.reviewDayDetail(for: date)
    }

    /// The measures are named once, here.
    private var tableHeader: some View {
        HStack(alignment: .center, spacing: Tokens.Space.l) {
            TableColumnHeader(title: "Day and context", alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            TableColumnHeader(title: "Tracked", width: HistoryTableLayout.trackedWidth)
            TableColumnHeader(title: "Focused", width: HistoryTableLayout.focusedWidth)
            TableColumnHeader(title: "Sessions", width: HistoryTableLayout.sessionWidth)
            Spacer().frame(width: HistoryTableLayout.disclosureWidth)
        }
        .padding(.horizontal, Tokens.Space.xs)
        .padding(.bottom, Tokens.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Columns: day and context, tracked, focused, sessions")
    }

    @ViewBuilder private func historyDayEntry(_ day: HistoryDay) -> some View {
        let disclosure = HistoryDayDisclosurePresentation(
            isExpanded: isSelected(day) && selectedDayDetail != nil)
        VStack(spacing: 0) {
            // Keep the row in the same structural position when expanded, so
            // keyboard focus does not jump to the following day.
            dayRow(day, disclosure: disclosure)
            if disclosure.usesJoinedSurface, let detail = selectedDayDetail {
                Divider().padding(.horizontal, Tokens.Space.m)
                ReviewDayDetailPanel(
                    detail: detail,
                    onOpenInToday: { navigation.openStoryDay(detail.day.date) },
                    onClose: { navigation.clearReviewDay() },
                    presentation: .joined)
            }
        }
        .background(disclosure.usesJoinedSurface ? Tokens.Colour.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                         style: .continuous))
    }

    private func dayRow(_ day: HistoryDay,
                        disclosure: HistoryDayDisclosurePresentation) -> some View {
        Button {
            if disclosure.isExpanded {
                navigation.clearReviewDay()
            } else {
                ReviewDayRoute.select(store: store, navigation: navigation)(day.date)
            }
        } label: {
            HStack(alignment: .center, spacing: Tokens.Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tokens.longDate(day.date))
                        .font(Tokens.Typography.rowTitle)
                    Text(dayContext(day))
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.l)
                HistoryMetric(value: Tokens.duration(day.tracked),
                              width: HistoryTableLayout.trackedWidth)
                HistoryMetric(value: Tokens.duration(day.focused),
                              width: HistoryTableLayout.focusedWidth)
                HistoryMetric(value: "\(day.sessions)",
                              width: HistoryTableLayout.sessionWidth)
                Image(systemName: disclosure.chevronSystemName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: HistoryTableLayout.disclosureWidth)
            }
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, Tokens.Space.xs)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowAccessibilityLabel(day))
        .accessibilityHint(disclosure.isExpanded
                           ? "Hides this day's detail"
                           : "Shows this day's detail below the row")
        .accessibilityAddTraits(isSelected(day) ? .isSelected : [])
    }

    /// Built outside the view builder: a long chain of interpolated fragments
    /// inside the body defeats the type checker.
    private func rowAccessibilityLabel(_ day: HistoryDay) -> String {
        var parts = [Tokens.longDate(day.date),
                     "\(Tokens.duration(day.tracked)) tracked",
                     "\(Tokens.duration(day.focused)) focused",
                     day.sessions == 1 ? "1 session" : "\(day.sessions) sessions"]
        if isSelected(day) { parts.append("selected") }
        return parts.joined(separator: ", ")
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

    private var activeFilterSummary: String? {
        var parts: [String] = []
        let query = store.historyFilter.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("Matching “\(query)”") }
        if let bundleID = store.historyFilter.appBundleID {
            parts.append("App: \(store.historyAppName(for: bundleID))")
        }
        if let workType = store.historyFilter.workType {
            parts.append("Work type: \(workType.displayName)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var resultLabel: String {
        let count = store.filteredHistoryDays.count
        return count == 1 ? "1 day" : "\(count) days"
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

/// A value only: the column header above it already names the measure.
private struct HistoryMetric: View {
    let value: String
    let width: CGFloat

    var body: some View {
        Text(value)
            .font(.callout.weight(.semibold).monospacedDigit())
            .frame(width: width, alignment: .trailing)
    }
}
