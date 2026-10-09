import Foundation

/// The checks' in-memory preferences behave as real ones do where the app
/// relies on it: suites of one name share values, numbers and Booleans come
/// back as the real class returns them, and emptying a suite empties it.
enum MemoryDefaultsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Checks' in-memory preferences behave as real ones where the app relies on it", behavesLikeDefaults),
    ]

    private static func behavesLikeDefaults() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-memory-\(UUID().uuidString)"
        defer { MemoryDefaults.remove(named: name) }
        guard let first = MemoryDefaults.suite(named: name),
              let reopened = MemoryDefaults.suite(named: name),
              let other = MemoryDefaults.suite(named: name + "-other") else { return ["no suite"] }

        first.set(7, forKey: "fc.count")
        first.set(true, forKey: "fc.flag")
        first.set("12.5", forKey: "fc.text")
        expect(reopened.integer(forKey: "fc.count") == 7, "a suite opened again sees what was written", &problems)
        expect(other.object(forKey: "fc.count") == nil, "a suite of another name sees nothing", &problems)
        expect((first.object(forKey: "fc.count") as? Double) == 7, "an Int reads back as a Double, as a real one does", &problems)
        let flag = first.object(forKey: "fc.flag") as? NSNumber
        expect(flag.map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true, "a Bool is stored as a CFBoolean", &problems)
        expect(first.double(forKey: "fc.text") == 12.5 && first.bool(forKey: "fc.text"),
               "a number written as text reads as a number", &problems)
        expect(Set(first.dictionaryRepresentation().keys) == ["fc.count", "fc.flag", "fc.text"],
               "the suite lists only its own keys", &problems)

        let store = PersistenceStore(defaults: first)
        store.dailyGoal = 5_400
        expect(PersistenceStore(defaults: reopened).dailyGoal == 5_400, "a store reads what another store wrote", &problems)

        reopened.removePersistentDomain(forName: name)
        expect(first.object(forKey: "fc.count") == nil && first.dictionaryRepresentation().isEmpty,
               "emptying the suite empties it for every handle", &problems)
        return problems
    }
}
