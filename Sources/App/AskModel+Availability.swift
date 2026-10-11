import FoundationModels

/// Whether Ask can run on this Mac, for the places that offer it before the
/// sheet opens: the bar's button and Settings.
extension AskModel {
    /// macOS 26 and a Mac that can run Apple's model. Apple Intelligence
    /// merely switched off still counts, since the sheet says how to turn it
    /// on; a Mac that can never run Ask is not shown a way into it. Read once:
    /// neither changes while the app runs.
    nonisolated static let isOffered: Bool = {
        guard #available(macOS 26, *) else { return false }
        if case .unavailable(.deviceNotEligible) = SystemLanguageModel.default.availability { return false }
        return true
    }()

    /// What Settings says about Ask on this Mac now: ready, or the sheet's
    /// own line for what is missing.
    nonisolated static var status: String {
        guard #available(macOS 26, *) else { return needsNewerMacOS.text }
        return notice(for: SystemLanguageModel.default.availability)?.text ?? readyStatus
    }

    nonisolated static let readyStatus = "Ready. Apple Intelligence answers on this Mac, and nothing leaves it."

    /// What the empty sheet offers to ask: one of each kind of answer the
    /// tools give, each one the probe of 2026-10-10 answered rightly.
    nonisolated static let examples = [
        "When was my most focused day?",
        "What did I work on yesterday?",
        "When do I focus best?",
        "Did I focus more this week than last week?",
    ]
}
