import Foundation

/// The Apple Intelligence switch and the day the Yesterday notice was dismissed:
/// both live in preferences, so a relaunch (a second store on the same suite)
/// must read what the first one wrote.
enum ReviewNoteGateChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Apple Intelligence notes are on until the switch is turned off", switchDefaultsOn),
        ("The Yesterday notice remembers the day it was dismissed", dismissedDayPersists),
    ]

    /// Two stores over one in-memory suite, the second standing for a relaunch.
    private static func withStores(_ body: (PersistenceStore, PersistenceStore) -> [String]) -> [String] {
        let name = "fc-selftest-notes-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: name) else {
            return ["could not create the in-memory preferences suite"]
        }
        defer { MemoryDefaults.remove(named: name) }
        return body(PersistenceStore(defaults: defaults), PersistenceStore(defaults: defaults))
    }

    private static func switchDefaultsOn() -> [String] {
        withStores { store, relaunched in
            var problems: [String] = []
            expect(store.useAppleIntelligence, "a fresh store should have the switch on", &problems)
            store.useAppleIntelligence = false
            expect(!relaunched.useAppleIntelligence,
                   "a relaunch should read the switch off after it was turned off", &problems)
            store.useAppleIntelligence = true
            expect(relaunched.useAppleIntelligence,
                   "turning the switch back on should read on after a relaunch", &problems)
            return problems
        }
    }

    private static func dismissedDayPersists() -> [String] {
        withStores { store, relaunched in
            var problems: [String] = []
            expect(store.yesterdayNoteDismissedDay == nil,
                   "a fresh store should have no dismissed day, got \(String(describing: store.yesterdayNoteDismissedDay))",
                   &problems)
            store.yesterdayNoteDismissedDay = SelfTest.base
            expect(relaunched.yesterdayNoteDismissedDay == SelfTest.base,
                   "a relaunch should read the dismissed day back, got \(String(describing: relaunched.yesterdayNoteDismissedDay))",
                   &problems)
            store.yesterdayNoteDismissedDay = nil
            expect(relaunched.yesterdayNoteDismissedDay == nil,
                   "clearing the dismissed day should read nil after a relaunch", &problems)
            return problems
        }
    }
}
