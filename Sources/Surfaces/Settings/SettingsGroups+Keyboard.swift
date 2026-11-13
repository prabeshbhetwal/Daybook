import SwiftUI

/// Settings → General → Keyboard: the keys, in one place that stays. The app
/// has no menu bar to list them in, and the welcome names them once and moves on.
extension SettingsGroups {
    var keyboard: some View {
        SurfacePanel(title: "Keyboard", layout: layout) {
            globalShortcutRow
            rowDivider
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                ForEach(Self.windowKeys, id: \.keys) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                        Text(entry.keys)
                            .font(Tokens.Typography.label.monospacedDigit())
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: Self.keyColumnWidth.zoomed, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(entry.action)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.action), \(entry.spoken)")
                }
                explanation(Self.pauseOrAwayNote)
                    .padding(.top, Tokens.Space.xs)
            }
            .padding(.vertical, Tokens.Space.s)
        }
    }

    /// The chord, a button that records a new one, and the way back to the
    /// standard chord or to none. The line under it says whether it is held.
    private var globalShortcutRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                Text("Start or end a session from any app")
                    .font(Tokens.Typography.rowTitle)
                    .foregroundStyle(StoryStyle.supportingInk)
                Spacer(minLength: Tokens.Space.m)
                ShortcutRecorder(shortcut: model.globalShortcut) { model.setGlobalShortcut($0) }
                if model.globalShortcut != .standard {
                    Button("Reset") { model.setGlobalShortcut(.standard) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset the shortcut to Control-Option-Space")
                }
                if model.globalShortcut != nil {
                    Button("Turn Off") { model.setGlobalShortcut(nil) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Turn Off")
                        .accessibilityHint("Turns the global shortcut off")
                }
            }
            explanation(Self.globalShortcutDetail(model.globalShortcutStatus, shortcut: model.globalShortcut))
            if let message = model.globalShortcutMessage {
                Text(message)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Colour.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: layout.rowHeight)
        .announcesChanges(to: model.globalShortcutMessage)
    }

    static func globalShortcutDetail(_ status: HotKeyMonitor.Status,
                                     shortcut: GlobalShortcut? = .standard) -> String {
        let chord = shortcut?.spoken ?? "The shortcut"
        switch status {
        case .registered:
            return "\(chord) works in any app and opens a waiting away card."
        case .yieldedToVoiceOver:
            return "Off while VoiceOver is on. Record a chord without Control-Option to use it now."
        case .unavailable:
            return "Another app is using \(chord). Record a different one."
        case .off:
            return "Off. Record a shortcut to turn it on."
        }
    }

    /// Pause and Away sit side by side on the bar and read as one thing
    /// until pressed; the keyboard list is where the difference is written down.
    static let pauseOrAwayNote = "Pause: you're at the Mac, apps still recorded. "
        + "Away: you've left, nothing recorded."

    /// The key column's width in points at 100%. It holds the widest chord, ⌥⌘
    /// and an arrow, at any zoom, because the label font and the column scale
    /// together; a check measures the chords against it.
    static let keyColumnWidth = 64

    /// The window's own keys, named as the menu names them. The session keys
    /// come from `SessionShortcut`, so this list cannot drift from what the
    /// Session commands answer to.
    static let windowKeys: [KeyEntry] = [
        KeyEntry(keys: SessionShortcut.start.glyphs, spoken: "Option-Command-N", action: "Start Focus"),
        KeyEntry(keys: SessionShortcut.pauseOrResume.glyphs, spoken: "Option-Command-P",
                 action: "Pause or Resume"),
        KeyEntry(keys: SessionShortcut.stepAway.glyphs, spoken: "Option-Command-A", action: "Step Away"),
        KeyEntry(keys: SessionShortcut.takeBreak.glyphs, spoken: "Option-Command-B",
                 action: "Take a Break, or End It"),
        KeyEntry(keys: SessionShortcut.stop.glyphs, spoken: "Option-Command-S", action: "Stop"),
        KeyEntry(keys: "⌘1", spoken: "Command-1", action: "Story"),
        KeyEntry(keys: "⌘2", spoken: "Command-2", action: "History"),
        KeyEntry(keys: "⌘F", spoken: "Command-F", action: "Find in History"),
        KeyEntry(keys: "⌘J", spoken: "Command-J", action: "Go to Date…"),
        KeyEntry(keys: "⌘K", spoken: "Command-K", action: "Ask Daybook"),
        KeyEntry(keys: "⌥⌘←", spoken: "Option-Command-Left Arrow", action: "Previous Day"),
        KeyEntry(keys: "⌥⌘→", spoken: "Option-Command-Right Arrow", action: "Next Day"),
        KeyEntry(keys: "⌘6", spoken: "Command-6", action: "Awards"),
        KeyEntry(keys: "⌘7", spoken: "Command-7", action: "Session Controls"),
        KeyEntry(keys: "⌘,", spoken: "Command-comma", action: "Settings"),
        KeyEntry(keys: "⌘+", spoken: "Command-plus", action: "Zoom In"),
        KeyEntry(keys: "⌘−", spoken: "Command-minus", action: "Zoom Out"),
        KeyEntry(keys: "⌘0", spoken: "Command-0", action: "Actual Size")
    ]

    struct KeyEntry: Hashable {
        let keys: String
        /// How VoiceOver should say the keys; it reads the glyphs poorly.
        let spoken: String
        let action: String
    }
}
