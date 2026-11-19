import Foundation

/// Kept in the sidecar entry of a split's tail (plan ruling B13): what the pair was when it was cut, so
/// Merge Back is offered only while it still is. It is read, never trusted: the records are the truth.
struct SplitLink: Codable, Equatable {
    let head: UUID
    let at: Date
    let headName: String
    let headWorkType: WorkType
    let tailName: String
    let tailWorkType: WorkType

    init(head: SessionRecord, tail: SessionRecord) {
        self.head = head.id
        at = tail.start
        headName = head.name
        headWorkType = head.workType
        tailName = tail.name
        tailWorkType = tail.workType
    }

    /// True while the pair is the one that was cut: still touching at the cut, and neither renamed nor
    /// filed under another category since.
    func holds(head current: SessionRecord, tail: SessionRecord) -> Bool {
        current.id == head && current.end == at && tail.start == at
            && current.name == headName && current.workType == headWorkType
            && tail.name == tailName && tail.workType == tailWorkType
    }
}
