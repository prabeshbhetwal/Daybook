import SwiftUI
import AppKit

enum StoryScopeKeyCommand {
    case left
    case right
    case home
    case end
}

/// One selection rule shared by the AppKit adapter and headless checks. The
/// ends clamp rather than wrap, matching a native segmented control.
enum ScopeKeyboardSelection {
    static func apply(_ command: StoryScopeKeyCommand, to index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        switch command {
        case .left: return max(0, index - 1)
        case .right: return min(count - 1, index + 1)
        case .home: return 0
        case .end: return count - 1
        }
    }

    static func accessibilityValue(title: String) -> String { "\(title), selected" }
}

/// How keyboard focus reached a control. A focus cue answers "where will my
/// next key press land?", which only someone using the keyboard is asking; a
/// control that draws it after a click is answering a question nobody put.
enum ControlFocusOrigin {
    case pointer
    case keyboard
}

/// macOS 13-compatible native scope target. AppKit owns pointer selection and
/// standard focus semantics; this subclass adds Home/End and an integrated,
/// local focus cue after suppressing only AppKit's detached outer ring.
///
/// The control accepts first responder unconditionally so Tab reaches it
/// without Full Keyboard Access, which means a click focuses it too. The cue
/// is shown only when focus arrived from the keyboard — the rule Apple's own
/// controls follow, where a click never draws a ring.
final class ScopeNSSegmentedControl: NSSegmentedControl {
    var onKeyboardSelection: ((StoryScopeKeyCommand) -> Void)?
    private(set) var focusOrigin: ControlFocusOrigin = .keyboard
    /// The cue's corner. SwiftUI hands it down on every update, so the cue
    /// follows the interface zoom.
    var focusCueRadius: CGFloat = Tokens.Radius.control

    override var acceptsFirstResponder: Bool { true }

    var showsFocusCue: Bool {
        window?.firstResponder === self && focusOrigin == .keyboard
    }

    func noteFocus(from origin: ControlFocusOrigin) {
        focusOrigin = origin
        updateIntegratedFocusCue()
    }

    override func mouseDown(with event: NSEvent) {
        noteFocus(from: .pointer)
        super.mouseDown(with: event)
        updateIntegratedFocusCue()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        // A window that opens hands focus to its first key view by itself.
        // That is not the keyboard: only a key press (Tab), or a direct
        // request with no event behind it, arrives as keyboard focus.
        if let event = NSApp.currentEvent, event.type != .keyDown, event.type != .keyUp {
            focusOrigin = .pointer
        }
        updateIntegratedFocusCue()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        // The next arrival is keyboard unless a click says otherwise.
        focusOrigin = .keyboard
        updateIntegratedFocusCue()
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        // A key press while focused means the keyboard is in use now, however
        // focus first arrived.
        noteFocus(from: .keyboard)
        let commandModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(commandModifiers).isEmpty else {
            super.keyDown(with: event)
            return
        }
        let command: StoryScopeKeyCommand?
        switch event.keyCode {
        case 123: command = .left
        case 124: command = .right
        case 115: command = .home
        case 119: command = .end
        default: command = nil
        }
        if let command {
            onKeyboardSelection?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    /// Draws nothing. `ScopePills` behind this control is the appearance; the
    /// control remains the single keyboard, pointer and accessibility target,
    /// so AppKit's own segmented chrome — separators included — must not show
    /// through the pill it sits on.
    override func draw(_ dirtyRect: NSRect) {}

    func updateIntegratedFocusCue() {
        wantsLayer = true
        layer?.cornerRadius = focusCueRadius
        layer?.borderWidth = showsFocusCue ? 2.zoomed : 0
        layer?.borderColor = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.75).cgColor
    }
}

/// Retained name for the Story chrome's own checks.
typealias StoryScopeNSSegmentedControl = ScopeNSSegmentedControl

/// The native target every scope row sits under: one keyboard focus, arrow,
/// Home and End handling, and one accessibility value — where a row of SwiftUI
/// buttons would be one tab stop per pill.
struct NativeScopeControl: NSViewRepresentable {
    let titles: [String]
    @Binding var selectedIndex: Int
    let controlLabel: String
    var cueRadius: CGFloat = Tokens.Radius.control

    final class Coordinator: NSObject {
        var selectedIndex: Binding<Int>
        var titles: [String]

        init(selectedIndex: Binding<Int>, titles: [String]) {
            self.selectedIndex = selectedIndex
            self.titles = titles
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard titles.indices.contains(sender.selectedSegment) else { return }
            selectedIndex.wrappedValue = sender.selectedSegment
            sender.setAccessibilityValue(
                ScopeKeyboardSelection.accessibilityValue(title: titles[sender.selectedSegment]))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex, titles: titles)
    }

    func makeNSView(context: Context) -> ScopeNSSegmentedControl {
        let control = ScopeNSSegmentedControl(
            labels: titles,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded
        control.controlSize = .regular
        control.focusRingType = .none
        control.setAccessibilityLabel(controlLabel)
        control.onKeyboardSelection = { [weak control, weak coordinator = context.coordinator] command in
            guard let control, let coordinator else { return }
            let next = ScopeKeyboardSelection.apply(command,
                                                    to: coordinator.selectedIndex.wrappedValue,
                                                    count: coordinator.titles.count)
            coordinator.selectedIndex.wrappedValue = next
            control.selectedSegment = next
            control.setAccessibilityValue(
                ScopeKeyboardSelection.accessibilityValue(title: coordinator.titles[next]))
        }
        configure(control, coordinator: context.coordinator)
        return control
    }

    func updateNSView(_ control: ScopeNSSegmentedControl, context: Context) {
        configure(control, coordinator: context.coordinator)
    }

    private func configure(_ control: ScopeNSSegmentedControl, coordinator: Coordinator) {
        coordinator.selectedIndex = $selectedIndex
        coordinator.titles = titles
        control.selectedSegment = selectedIndex
        // A row with nothing chosen reads -1; VoiceOver heard ", selected"
        // with no name.
        control.setAccessibilityValue(
            titles[safe: selectedIndex].map(ScopeKeyboardSelection.accessibilityValue(title:))
                ?? "Custom span")
        control.setAccessibilityHelp("Use Left, Right, Home or End to choose "
                                     + titles.joined(separator: ", "))
        control.focusCueRadius = cueRadius
        control.updateIntegratedFocusCue()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// A scope row: the shared pill appearance, with the native control over it
/// owning interaction, keyboard traversal and accessibility.
struct ScopePillRow: View {
    let titles: [String]
    @Binding var selectedIndex: Int
    let controlLabel: String

    var body: some View {
        ZStack {
            ScopePills(titles: titles, selectedIndex: selectedIndex)
            NativeScopeControl(titles: titles, selectedIndex: $selectedIndex,
                               controlLabel: controlLabel)
        }
        .fixedSize()
    }
}
