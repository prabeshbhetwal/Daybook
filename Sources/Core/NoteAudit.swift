import Foundation

/// Rejects a note that states a figure its facts do not hold.
///
/// Figures are compared by kind and value, not by their digits (`NoteFigure`):
/// a 9:13 start does not let "9h" through, a clock time is not a count, and a
/// duration the facts hold passes whether the note writes it "1h 30m", "90
/// minutes" or "one hour thirty minutes". A number that is no duration, time,
/// date, year, count or percentage is a bare one, and must be a bare number
/// the facts hold: a session name's digits ("Q4 plan v2") are such facts, as
/// long as the note quotes the name.
///
/// It fails closed. An amount worded with no number ("an hour", "half an hour",
/// "a couple of hours", "twice", "Thesis for hours") is a phrase no fact holds,
/// so the note fails; a weekday written beside a date must be the weekday the
/// facts give that date, or the note fails.
enum NoteAudit {
    /// The mentions in the note's story and pattern that no figure in
    /// the facts matches. Each is the readings it has (a time without am or
    /// pm has two).
    static func unmatched(_ note: WrittenNote, facts: NoteFacts) -> [Set<NoteFigure>] {
        let held = NoteFigure.held(in: facts.text)
        return [note.story, note.pattern]
            .flatMap(NoteFigure.read)
            .filter { $0.isDisjoint(with: held) }
    }

    /// Whether every figure in the note's story and pattern is also in the facts.
    static func passes(_ note: WrittenNote, facts: NoteFacts) -> Bool {
        unmatched(note, facts: facts).isEmpty
    }
}
