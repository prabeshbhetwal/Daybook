import Foundation

/// What starts the name suggestion notice: a key a body can read every tick
/// that moves only when what could be offered has moved.
enum NameSuggestionNoticeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The suggestion key holds through the day's ticks and moves on Keep as is, a rename and midnight", keyMoves),
    ]

    private typealias Checks = NameSuggestionStoreChecks

    private static func keyMoves() -> [String] {
        let (kept, named) = (UUID(), UUID())
        return Checks.withFixture(records: { days in [
            Checks.record(days.at(0, 6), days.at(0, 6, 30), thread: kept),
            Checks.record(days.at(0, 7), days.at(0, 7, 30), thread: named),
        ] }, usage: { days in [
            Checks.app("Xcode", days.at(0, 6), 25 * 60), Checks.app("Xcode", days.at(0, 7), 25 * 60),
        ] }) { f, _, problems in
            let first = f.store.nameSuggestionKey
            for seconds in [1.0, 59, 3_600] {
                f.clock.advance(seconds)
                expect(f.store.nameSuggestionKey == first, "the key moved after \(seconds) s of the same day", &problems)
            }
            guard let session = Checks.target(f, kept), let other = Checks.target(f, named) else {
                return problems.append("the sessions are not offered")
            }
            f.store.keepSessionUnnamed(session)
            let afterKeep = f.store.nameSuggestionKey
            expect(afterKeep != first, "Keep as is did not move the key", &problems)
            expect(f.store.acceptNameSuggestion("Daybook", for: other), "Name it failed", &problems)
            let afterRename = f.store.nameSuggestionKey
            expect(afterRename != afterKeep, "a rename did not move the key", &problems)
            f.clock.advance(86_400)
            expect(f.store.nameSuggestionKey != afterRename, "midnight did not move the key", &problems)
        }
    }
}
