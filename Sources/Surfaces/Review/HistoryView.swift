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
        Tokens.australianDate(format)
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

