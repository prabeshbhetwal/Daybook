import Foundation

/// The global chord can be changed: it is written and said right, refused
/// where it could not be global, stored, and kept when macOS refuses the new one.
enum GlobalShortcutChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The global shortcut is named, guarded, stored and kept when a new chord is refused",
         namedGuardedStoredKept),
    ]

    private static func namedGuardedStoredKept() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let standard = GlobalShortcut.standard
            expect(standard.glyphs == "⌃⌥Space" && standard.spoken == "Control-Option-Space",
                   "the standard chord reads as ⌃⌥Space", &problems)
            let optionCommandA = GlobalShortcut(keyCode: 0, modifiers: GlobalShortcut.option | GlobalShortcut.command,
                                                keyLabel: "A")
            expect(optionCommandA.glyphs == "⌥⌘A" && optionCommandA.spoken == "Option-Command-A",
                   "modifiers are written in Control, Option, Shift, Command order", &problems)
            expect(GlobalShortcut.label(keyCode: 49, typed: " ") == "Space"
                   && GlobalShortcut.label(keyCode: 0, typed: "a") == "A",
                   "keys that type nothing are named; the rest are the typed character", &problems)

            expect(GlobalShortcut.refusal(modifiers: 0) != nil, "a bare key is refused", &problems)
            expect(GlobalShortcut.refusal(modifiers: GlobalShortcut.command) != nil,
                   "Command alone is refused", &problems)
            expect(GlobalShortcut.refusal(modifiers: GlobalShortcut.option | GlobalShortcut.command) == nil,
                   "Option-Command is allowed", &problems)
            expect(standard.isVoiceOverChord && !optionCommandA.isVoiceOverChord,
                   "only Control-Option chords are let go for VoiceOver", &problems)

            let suite = "fc-selftest-shortcut-\(UUID().uuidString)"
            let persistence = PersistenceStore(defaults: MemoryDefaults.suite(named: suite) ?? .standard)
            persistence.removeAll()
            expect(persistence.globalShortcut == standard, "no preference means the standard chord", &problems)
            persistence.globalShortcut = optionCommandA
            expect(persistence.globalShortcut == optionCommandA, "a recorded chord is stored", &problems)
            persistence.globalShortcut = nil
            expect(persistence.globalShortcut == nil, "turning the shortcut off is stored", &problems)
            persistence.removeAll()
            expect(persistence.globalShortcut == standard, "reset brings the standard chord back", &problems)

            let model = SettingsModel(store: persistence, isTrackingEnabled: true,
                                      onChange: {}, onTrackingChanged: { _ in })
            model.applyGlobalShortcut = { _ in false }
            model.setGlobalShortcut(optionCommandA)
            expect(model.globalShortcut == standard && model.globalShortcutMessage?.contains("⌥⌘A") == true,
                   "a chord macOS refuses is not stored, and the refusal names it", &problems)
            model.applyGlobalShortcut = { _ in true }
            model.setGlobalShortcut(optionCommandA)
            expect(model.globalShortcut == optionCommandA && model.globalShortcutMessage == nil,
                   "a chord macOS takes is stored and the message clears", &problems)
            model.setGlobalShortcut(GlobalShortcut(keyCode: 1, modifiers: GlobalShortcut.command, keyLabel: "S"))
            expect(model.globalShortcut == optionCommandA && model.globalShortcutMessage != nil,
                   "Command-S is refused before it reaches macOS", &problems)

            let monitor = HotKeyMonitor()
            expect(monitor.apply(optionCommandA) && monitor.shortcut == optionCommandA,
                   "an unregistered monitor still records the chord it will hold", &problems)

            MemoryDefaults.remove(named: suite)
            return problems
        }
    }
}
