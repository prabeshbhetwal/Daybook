import Foundation

/// The "Change not saved" notices offer Retry only when one can land, and let
/// a refusal with nothing to retry be dismissed instead of staying for good.
enum CorrectionNoticeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A refused stale answer offers Dismiss, not a Retry that does nothing", staleRefusalDismisses),
        ("Dismiss leaves an error that can still be retried in place", retryableErrorStays),
    ]

    private static func staleRefusalDismisses() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .needsResolution)
            defer { FixtureFactory.cleanUp() }
            var problems: [String] = []
            // An answer carrying an interval ID the engine no longer has.
            let saved = store.resolve(.tookBreak, expectedID: UUID())
            expect(!saved && store.correctionError != nil,
                   "a stale answer should be refused with an error, got saved=\(saved) error=\(store.correctionError ?? "nil")",
                   &problems)
            expect(!store.canRetryCorrection,
                   "a stale refusal has nothing to retry, got canRetryCorrection=true", &problems)
            expect(StoryCorrectionNotice.visibleError(in: store) != nil || store.focusOperationFailure != nil,
                   "the refusal should still be shown somewhere", &problems)
            store.dismissCorrectionError()
            expect(store.correctionError == nil,
                   "Dismiss should clear the refusal, got \(store.correctionError ?? "nil")", &problems)
            return problems
        }
    }

    private static func retryableErrorStays() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            var problems: [String] = []
            store.publishCorrectionError("The original Stop could not be saved.")
            store.correctionRetry = .ending(threadID: store.engine.activeThreadID,
                                            sessionStart: store.engine.sessionStartDate)
            expect(store.canRetryCorrection, "a failed Stop should offer Retry, got false", &problems)
            store.dismissCorrectionError()
            expect(store.correctionError != nil && store.correctionRetry != nil,
                   "Dismiss must not drop a retry that can still land, got error=\(store.correctionError ?? "nil")",
                   &problems)
            return problems
        }
    }
}
