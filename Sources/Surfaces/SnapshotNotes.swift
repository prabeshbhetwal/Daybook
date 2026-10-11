import Foundation

extension Snapshotter {
    /// Gives a notes scenario's yesterday a written note without asking a
    /// model, and returns that day's place (nil when yesterday has no
    /// session). The responder is what makes the model usable; `present`
    /// caches the note against yesterday's facts, so it is never called. Each
    /// note's figures are its fixture's: Today's rail uses the week fixture
    /// (Standup for 2h 25m from 10:00 am), History the evidence fixture
    /// (Review evidence for 1h 25m from 9:00 am).
    @discardableResult
    static func presentNotes(for scenario: SnapshotScenario, on navigation: MainWindowModel,
                             store: SessionStore) -> HistoryPlace? {
        guard let writer = navigation.notes, let place = store.yesterdayNotePlace() else { return nil }
        writer.responder = { _ in throw CocoaError(.featureUnsupported) }
        let note = scenario == .reviewNotesHistory
            ? WrittenNote(story: "Review evidence was the whole day: one session of 1h 25m from 9:00 am.",
                          pattern: "The most focus came in the morning, between 5 am and noon: 1h 25m.")
            : WrittenNote(story: "Standup was the whole day: one session of 2h 25m from 10:00 am.",
                          pattern: "The most focus came in the morning, between 5 am and noon: 2h.")
        writer.present(note, for: place)
        return place
    }
}
