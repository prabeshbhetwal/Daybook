import Foundation

extension SessionMetadataArchive {
    /// Keeps a record's phases beside its note and power readings. It is the one record of them once
    /// the beats they came from have expired, so a note saved or cleared leaves it be, and an entry
    /// that holds nothing else is not dropped.
    @discardableResult
    func saveActivityShape(_ shape: SessionActivityShape, for recordID: UUID) -> SessionMetadataWriteResult {
        update(recordID) { $0.activityShape = shape }
    }
}
