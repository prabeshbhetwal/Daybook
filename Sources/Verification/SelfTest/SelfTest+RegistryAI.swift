import Foundation

extension SelfTest {
    /// The on-device AI category suites (Phase C), run at the very end of `registeredTests` in this order. A check's
    /// position is its number, so a new suite goes at the end of this list.
    static var aiCategoryTests: [(String, () -> [String])] {
        FocusPropertyChecks.tests
            + AITriggerChecks.tests + AILabelBookChecks.tests + AIQuestionChecks.tests
            + NonCountingCoreChecks.tests + NonCountingStoreChecks.tests + HiddenCategoryChecks.tests
            + AILabelRulesChecks.tests + CatalogueCacheChecks.tests + AILabelStoreChecks.tests
            + CategoryAssistantChecks.tests + CategoryAssistantRaceChecks.tests + CategoryAssistantLabelChecks.tests
            + CategoryFactsChecks.tests + CategoryAssistantHeldChecks.tests + AILabelActionChecks.tests
            + AILabelRetireChecks.tests + AISettingsChecks.tests + AIReportChecks.tests + AISurfaceChecks.tests
            + AIReviewChecks.tests + AIOfferChecks.tests + AIOfferRecheckChecks.tests + AILabelGuardChecks.tests
            + AILateAnswerChecks.tests + AILaunchChecks.tests + AIUseScopeChecks.tests + AILabelUndoChecks.tests
            + NonCountingReviewChecks.tests + AILabelSafetyChecks.tests + AIFinalRoundChecks.tests
            + SearchedFocusChecks.tests
    }
}
