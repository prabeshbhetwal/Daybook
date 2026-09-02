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
enum StoryScopeKeyboardSelection {
    static func apply(_ command: StoryScopeKeyCommand, to selection: StoryScope) -> StoryScope {
        let scopes = StoryScope.allCases
        let index = scopes.firstIndex(of: selection) ?? 0
        switch command {
        case .left: return scopes[max(0, index - 1)]
        case .right: return scopes[min(scopes.count - 1, index + 1)]
        case .home: return scopes[0]
        case .end: return scopes[scopes.count - 1]
        }
    }

    static func accessibilityValue(for selection: StoryScope) -> String {
        "\(selection.title), selected"
    }
}

/// macOS 13-compatible native scope target. AppKit owns pointer selection and
/// standard focus semantics; this subclass adds Home/End and an integrated,
/// local focus cue after suppressing only AppKit's detached outer ring.
final class StoryScopeNSSegmentedControl: NSSegmentedControl {
    var onKeyboardSelection: ((StoryScopeKeyCommand) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateIntegratedFocusCue()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        updateIntegratedFocusCue()
        return resigned
    }

    override func keyDown(with event: NSEvent) {
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
        layer?.cornerRadius = 7
        layer?.borderWidth = window?.firstResponder === self ? 2 : 0
        layer?.borderColor = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.75).cgColor
    }
}

struct NativeStoryScopeControl: NSViewRepresentable {
    @Binding var selection: StoryScope

    final class Coordinator: NSObject {
        var selection: Binding<StoryScope>

        init(selection: Binding<StoryScope>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard StoryScope.allCases.indices.contains(sender.selectedSegment) else { return }
            let selected = StoryScope.allCases[sender.selectedSegment]
            selection.wrappedValue = selected
            sender.setAccessibilityValue(StoryScopeKeyboardSelection.accessibilityValue(for: selected))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> StoryScopeNSSegmentedControl {
        let control = StoryScopeNSSegmentedControl(
            labels: StoryScope.allCases.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded
        control.controlSize = .regular
        control.focusRingType = .none
        control.setAccessibilityLabel("Story scope")
        control.onKeyboardSelection = { [weak control, weak coordinator = context.coordinator] command in
            guard let control, let coordinator else { return }
            let next = StoryScopeKeyboardSelection.apply(command,
                                                          to: coordinator.selection.wrappedValue)
            coordinator.selection.wrappedValue = next
            control.selectedSegment = StoryScope.allCases.firstIndex(of: next) ?? 0
            control.setAccessibilityValue(StoryScopeKeyboardSelection.accessibilityValue(for: next))
        }
        configure(control, coordinator: context.coordinator)
        return control
    }

    func updateNSView(_ control: StoryScopeNSSegmentedControl, context: Context) {
        configure(control, coordinator: context.coordinator)
    }

    private func configure(_ control: StoryScopeNSSegmentedControl, coordinator: Coordinator) {
        coordinator.selection = $selection
        control.selectedSegment = StoryScope.allCases.firstIndex(of: selection) ?? 0
        control.setAccessibilityValue(StoryScopeKeyboardSelection.accessibilityValue(for: selection))
        control.setAccessibilityHelp("Use Left, Right, Home or End to choose Day, Week or Month")
        control.updateIntegratedFocusCue()
    }
}
