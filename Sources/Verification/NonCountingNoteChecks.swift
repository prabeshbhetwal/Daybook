import Foundation

/// A review note on screen is checked again only when the evidence it was written from moves. Setting a category
/// not to count toward focus changes that period's focus with no record written, so the evidence has to carry the
/// category catalogue too; it had left it out, and an open note kept the old focus figures.
enum NonCountingNoteChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The evidence a note is checked against moves when a category is set not to count toward focus",
         evidenceMovesWithCountsTowardFocus),
    ]

    private static func evidenceMovesWithCountsTowardFocus() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.engine.store.workTypeDefinitions = [FocusPropertyFixture.readingDefinition()]
            defer { f.engine.store.workTypeDefinitions = [] }
            let before = f.store.noteEvidence
            f.engine.store.workTypeDefinitions = [FocusPropertyFixture.readingDefinition { $0.countsTowardFocus = false }]
            expect(f.store.noteEvidence != before,
                   "turning off counts toward focus left the evidence as it was: \(f.store.noteEvidence)", &problems)
        }
    }
}
