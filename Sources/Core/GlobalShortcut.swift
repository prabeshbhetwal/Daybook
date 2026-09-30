import Foundation

/// The one key that reaches the app from any other: which key, which
/// modifiers, and how it is written and said. Carbon's modifier bits are kept
/// as plain integers so Core stays free of Carbon.
struct GlobalShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    /// The key as the keyboard that recorded it names it: "A", "5", "Space".
    let keyLabel: String

    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    /// Control-Option-Space, the chord since the first release.
    static let standard = GlobalShortcut(keyCode: 49, modifiers: control | option, keyLabel: "Space")

    /// Nil when the chord can be held from any app; otherwise why not. A
    /// Command chord belongs to every app's own menus, and a bare key to
    /// typing, so a global one needs Control or Option in it.
    static func refusal(modifiers: UInt32) -> String? {
        modifiers & (control | option) == 0
            ? "Add Control or Option. Command alone belongs to every app's menus." : nil
    }

    /// Control-Option is VoiceOver's own modifier, so every such chord is a
    /// VoiceOver command while it runs and has to be let go for that long.
    var isVoiceOverChord: Bool {
        modifiers & Self.command == 0 && modifiers & (Self.control | Self.option) == Self.control | Self.option
    }

    /// As the menu bar would draw it: ⌃⌥Space.
    var glyphs: String { modifierParts.map(\.glyph).joined() + keyLabel }
    /// As VoiceOver should say it: Control-Option-Space.
    var spoken: String { (modifierParts.map(\.word) + [keyLabel]).joined(separator: "-") }

    private var modifierParts: [(glyph: String, word: String)] {
        [(Self.control, "⌃", "Control"), (Self.option, "⌥", "Option"),
         (Self.shift, "⇧", "Shift"), (Self.command, "⌘", "Command")]
            .filter { modifiers & $0.0 != 0 }
            .map { (glyph: $0.1, word: $0.2) }
    }

    /// The label for a recorded key: a name for keys that type nothing, the
    /// typed character for the rest.
    static func label(keyCode: UInt32, typed: String) -> String {
        if let named = namedKeys[keyCode] { return named }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Key \(keyCode)" : trimmed.uppercased()
    }

    private static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 53: "Escape", 51: "Delete",
        117: "Forward Delete", 123: "Left", 124: "Right", 125: "Down", 126: "Up",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

/// What is stored: the chord, or none once the shortcut is turned off. A
/// missing preference means the standard chord.
struct GlobalShortcutPreference: Codable, Equatable {
    var shortcut: GlobalShortcut?
}
