import FoundationModels

/// The lines Ask shows when it cannot answer, and the errors and availability
/// they come from.
extension AskModel {
    nonisolated static let needsNewerMacOS = AskNotice(text: "Ask needs macOS 26 or later.", opensSettings: false)
    /// A full context is retried once in a fresh session; this is for the second.
    nonisolated static let contextFull = AskNotice(
        text: "That question needs more room than Apple's on-device model has. Try a shorter question, or start a new chat.",
        opensSettings: false)
    /// The answer asked for an eighth lookup; see `AskGate`.
    nonisolated static let keptLooking = AskNotice(
        text: "Ask kept looking things up without answering. Try asking about one period or one thing.",
        opensSettings: false)
    private nonisolated static let cannotAnswer = AskNotice(text: "Can't answer that one.", opensSettings: false)
    private nonisolated static let unsupportedLanguage = AskNotice(text: "Ask doesn't understand this language yet.",
                                                                   opensSettings: false)

    @available(macOS 26, *)
    nonisolated static func notice(for availability: SystemLanguageModel.Availability) -> AskNotice? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return AskNotice(text: "This Mac can't run Apple's on-device model.", opensSettings: false)
        case .unavailable(.appleIntelligenceNotEnabled):
            // The switch is Apple's, so the line uses its name in System Settings.
            return AskNotice(text: "Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri.", // name: Apple's
                             opensSettings: true)
        case .unavailable(.modelNotReady):
            return AskNotice(text: "The on-device model is still downloading. Try again shortly.", opensSettings: false)
        case .unavailable:
            return AskNotice(text: "Ask isn't available on this Mac right now.", opensSettings: false)
        }
    }

    /// Whether the model ran out of room. macOS 26 throws `GenerationError`;
    /// macOS 27 throws `LanguageModelError` to an app built with its SDK
    /// (probed 2026-10-09), and only that SDK has the type.
    nonisolated static func isContextFull(_ error: Error) -> Bool {
        guard #available(macOS 26, *) else { return false }
        if let generation = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generation { return true }
        #if compiler(>=6.4)
        if #available(macOS 27, *), let model = error as? LanguageModelError,
           case .contextSizeExceeded = model { return true }
        #endif
        return false
    }

    /// Anything not listed is worded from the error itself.
    @available(macOS 26, *)
    nonisolated static func notice(for error: Error) -> AskNotice {
        if isContextFull(error) { return contextFull }
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .guardrailViolation, .refusal: return cannotAnswer
            case .unsupportedLanguageOrLocale: return unsupportedLanguage
            default: break
            }
        }
        #if compiler(>=6.4)
        if #available(macOS 27, *), let model = error as? LanguageModelError {
            switch model {
            case .guardrailViolation, .refusal: return cannotAnswer
            case .unsupportedLanguageOrLocale: return unsupportedLanguage
            default: break
            }
        }
        #endif
        return AskNotice(text: "Couldn't answer: \(error.localizedDescription)", opensSettings: false)
    }
}
