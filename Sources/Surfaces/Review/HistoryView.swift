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
                if !store.historyDays.isEmpty {
                    Divider()
                    rangeBar
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
                    ForEach(Array(store.filteredHistoryDays.enumerated()),
                            id: \.element.id) { index, day in
                        if index > 0 { Divider() }
                        dayRow(day)
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

    private var rangeBar: some View {
        ViewThatFits(in: .horizontal) {
            rangeControls(horizontal: true)
            rangeControls(horizontal: false)
        }
        .font(Tokens.Typography.metadata)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History date range")
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

    @ViewBuilder private func rangeControls(horizontal: Bool) -> some View {
        let from = HistoryDateControl(label: "From", selection: startBinding,
                                      range: dateBounds)
        let to = HistoryDateControl(label: "To", selection: endBinding,
                                    range: dateBounds)
        let all = Button("All dates") { store.resetHistoryRange() }
            .buttonStyle(.borderless)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)

        if horizontal {
            HStack(spacing: Tokens.Space.m) { from; to; Spacer(); all }
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HStack(spacing: Tokens.Space.m) { from; to }
                all
            }
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

    private func dayRow(_ day: HistoryDay) -> some View {
        Button {
            ReviewDayRoute.callback(store: store, navigation: navigation)(day.date)
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
                HistoryMetric(label: "Tracked", value: Tokens.duration(day.tracked))
                HistoryMetric(label: "Focused", value: Tokens.duration(day.focused))
                HistoryMetric(label: "Sessions", value: "\(day.sessions)")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, Tokens.Space.s)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Tokens.longDate(day.date)), "
                            + "\(Tokens.duration(day.tracked)) tracked, "
                            + "\(Tokens.duration(day.focused)) focused, "
                            + "\(day.sessions) sessions, open in Today")
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

private struct HistoryMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .frame(minWidth: 76, alignment: .trailing)
    }
}
