import Foundation

extension SelfTest {
    /// The activity-aware follow-ups deferred from Phase C (ruling C1), run after the AI category suites in this
    /// order. A check's position is its number, so a new suite goes at the end of this list.
    static var followUpTests: [(String, () -> [String])] {
        UnsortedStartChecks.tests
            + UnsortedTailChecks.tests
            + LeisureBlockChecks.tests
            + LeisureReviewChecks.tests
    }
}
