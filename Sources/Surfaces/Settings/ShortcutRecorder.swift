import AppKit
import SwiftUI

/// A button that shows the chord and, pressed, takes the next one typed.
/// Escape cancels. The keys are read by a local monitor and swallowed, so
/// the sheet's own shortcuts do not answer them while recording.
struct ShortcutRecorder: View {
    let shortcut: GlobalShortcut?
    let onRecord: (GlobalShortcut) -> Void
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Type the keys…" : (shortcut?.glyphs ?? "Record shortcut")) {
            isRecording ? stop() : start()
        }
        .buttonStyle(.bordered)
        .font(Tokens.Typography.metadata.monospacedDigit())
        .accessibilityLabel(isRecording
            ? "Recording. Type the keys; Escape cancels."
            : "Shortcut, \(shortcut?.spoken ?? "off"). Press to record a new one.")
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= GlobalShortcut.command }
            if flags.contains(.shift) { modifiers |= GlobalShortcut.shift }
            if flags.contains(.option) { modifiers |= GlobalShortcut.option }
            if flags.contains(.control) { modifiers |= GlobalShortcut.control }
            let code = UInt32(event.keyCode)
            let chord = GlobalShortcut(
                keyCode: code, modifiers: modifiers,
                keyLabel: GlobalShortcut.label(keyCode: code, typed: event.charactersIgnoringModifiers ?? ""))
            stop()
            onRecord(chord)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
