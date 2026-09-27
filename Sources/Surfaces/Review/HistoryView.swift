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

