import Foundation

/// "Don't ask again" on the questions Undo can reverse: the tick turns a
/// question off only together with the confirming button, Settings turns it
/// back on, and the choice is kept like any other preference.
enum ConfirmationChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("\"Don't ask again\" turns a question off only with its confirming button", tickNeedsConfirm),
        ("A question turned off stays off until Settings turns it back on", skippedPersists),
    ]

    private static func tickNeedsConfirm() -> [String] {
        var problems: [String] = []
        var stopped: [Confirmation] = []
        let policy = ConfirmationPolicy(asks: { _ in true }, stopAsking: { stopped.append($0) })
        let tick = DontAskAgain(.removeSession)

        tick.tick(policy).wrappedValue = true
        expect(stopped.isEmpty, "a tick alone keeps asking, got \(stopped)", &problems)
        tick.reset()
        tick.confirm(policy)
        expect(stopped.isEmpty, "a tick followed by Cancel keeps asking, got \(stopped)", &problems)

        tick.reset()
        tick.tick(policy).wrappedValue = true
        tick.confirm(policy)
        expect(stopped == [.removeSession], "tick then confirm stops asking, got \(stopped)", &problems)

        stopped = []
        tick.reset()
        tick.confirm(policy)
        tick.tick(policy).wrappedValue = true
        expect(stopped == [.removeSession],
               "confirm reported before the tick still stops asking, got \(stopped)", &problems)

        stopped = []
        tick.reset()
        tick.tick(policy).wrappedValue = true
        tick.tick(policy).wrappedValue = false
        tick.confirm(policy)
        expect(stopped.isEmpty, "a tick taken back keeps asking, got \(stopped)", &problems)
        expect(ConfirmationPolicy().asks(.changeBreak),
               "outside a window every question asks", &problems)
        return problems
    }

    private static func skippedPersists() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-confirmations-\(UUID().uuidString)"
        defer { MemoryDefaults.remove(named: suite) }
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not open \(suite)"] }
        let store = PersistenceStore(defaults: defaults)
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        let policy = settings.confirmationPolicy
        expect(Confirmation.allCases.allSatisfy(policy.asks), "every question asks at first", &problems)

        policy.stopAsking(.changeBreak)
        expect(!policy.asks(.changeBreak) && policy.asks(.removeSession),
               "Don't ask again turns off only its own question", &problems)
        let reloaded = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        expect(reloaded.skippedConfirmations == [.changeBreak],
               "the choice survives a relaunch, got \(reloaded.skippedConfirmations)", &problems)

        reloaded.skippedConfirmations = []
        expect(policy.asks(.changeBreak),
               "Settings turning it back on reaches a policy handed out earlier", &problems)

        defaults.set(["removeSession", "fromANewerBuild"], forKey: "fc.skippedConfirmations")
        expect(store.skippedConfirmations == [.removeSession],
               "a name this build does not know is ignored, got \(store.skippedConfirmations)", &problems)

        // The windows hand this to every row; a value that differed byte for
        // byte on each read would redraw them, and an open menu would lose
        // the item under the pointer.
        // Both reads are held, so a freed one cannot lend the other its address.
        let first = settings.confirmationPolicy, second = settings.confirmationPolicy
        expect(withUnsafeBytes(of: first) { Data($0) } == withUnsafeBytes(of: second) { Data($0) },
               "the policy is the same value on every read", &problems)

        store.removeAll()
        expect(store.skippedConfirmations.isEmpty, "erasing preferences asks every question again", &problems)
        return problems
    }
}
