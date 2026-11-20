import Foundation

/// One answer the model gave for a record, and what the person then chose for that record (Phase C, C14).
/// Ids only: no name, note or title.
struct TallyEntry: Codable, Equatable {
    let recordID: UUID
    let answerID: String
    var chosen: String?
}

/// Shadow mode's score: how often the model's answer matched what the person chose.
extension AILabelBook {
    /// An answer was given for this record. One entry per record, the newest `tallyKeep` kept. A none names
    /// nothing to match, so it is not counted for or against the model.
    mutating func tallyAnswer(_ answer: AIAnswer, recordID: UUID) {
        guard let answerID = answer.id else { return }
        tally.removeAll { $0.recordID == recordID }
        tally.append(TallyEntry(recordID: recordID, answerID: answerID, chosen: nil))
        if tally.count > AILabelConstants.tallyKeep { tally.removeFirst(tally.count - AILabelConstants.tallyKeep) }
    }

    /// The answer this record's entry is compared with is now `answerID`, chosen too: Use took what the record's
    /// own answer comes to now. In place, so the entry keeps its age; a record never asked about is ignored.
    mutating func retallyAnswer(_ answerID: String, recordID: UUID) {
        guard let index = tally.firstIndex(where: { $0.recordID == recordID }) else { return }
        tally[index] = TallyEntry(recordID: recordID, answerID: answerID, chosen: answerID)
    }

    /// The person set this record's category (by any path), as `chosen`, a category or label id. A later
    /// choice replaces an earlier one; a record the model was never asked about is ignored.
    mutating func recordChoice(recordID: UUID, chosen: String) {
        guard let index = tally.firstIndex(where: { $0.recordID == recordID }) else { return }
        tally[index].chosen = chosen
    }

    /// "AI matched 17 of your last 20 choices", over the newest `tallyWindow` entries that hold a choice.
    func tallyText() -> String {
        let choices = tally.filter { $0.chosen != nil }.suffix(AILabelConstants.tallyWindow)
        guard !choices.isEmpty else { return "No choices to compare yet" }
        let matched = choices.filter { $0.chosen == $0.answerID }.count
        if choices.count == 1 { return matched == 1 ? "AI matched your last choice" : "AI did not match your last choice" }
        return "AI matched \(matched) of your last \(choices.count) choices"
    }
}
