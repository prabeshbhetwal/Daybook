import AppKit

/// The break-over sound: the "Break's over" prompt and the Play button in
/// Settings both play it by name, and `NSSound(named:)` gives nil, so
/// silence, for a name the system does not have.
enum BreakSoundChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The break-over sound names a sound the system has", breakOverSoundExists),
    ]

    private static func breakOverSoundExists() -> [String] {
        var problems: [String] = []
        let name = FocusConstants.breakOverSoundName
        expect(NSSound(named: name) != nil, "NSSound(named: \"\(name)\") should find a sound, got nil", &problems)
        return problems
    }
}
