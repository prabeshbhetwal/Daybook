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
            // The ticker flushes the tracker every minute and every refresh
            // does too: app use arriving moves the usage revisions, not the key.
            _ = f.store.usage?.record(AppUsageSession(bundleID: "com.example.safari", appName: "Safari",
                                                      start: f.clock.value, end: f.clock.value.addingTimeInterval(300)))
            f.store.refresh()
            expect(f.store.nameSuggestionKey == first, "the key moved with app use and a refresh", &problems)
            guard let session = Checks.target(f, kept), let other = Checks.target(f, named) else {
                return problems.append("the sessions are not offered")
            }
            // A note changes the facts, so it must ask again: the key moves with the notes.
            _ = f.metadata.saveNote("planned the week", for: session.recordIDs[0])
            expect(f.store.nameSuggestionKey != first, "a note saved on an offered session did not move the key", &problems)
            let afterNote = f.store.nameSuggestionKey
            f.store.keepSessionUnnamed(session)
            let afterKeep = f.store.nameSuggestionKey
            expect(afterKeep != afterNote, "Keep as is did not move the key", &problems)
            expect(f.store.acceptNameSuggestion("Daybook", for: other), "Name it failed", &problems)
            let afterRename = f.store.nameSuggestionKey
            expect(afterRename != afterKeep, "a rename did not move the key", &problems)
            f.clock.advance(86_400)
            expect(f.store.nameSuggestionKey != afterRename, "midnight did not move the key", &problems)
        }
    }
}
