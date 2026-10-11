import Foundation
import FoundationModels

extension NoteWriter {
    /// Whether asking again with the same facts would fail the same way: the
    /// model refused them, held them against its guardrails, did not read the
    /// language, or they do not fit its context. Anything else the model
    /// throws is the Mac's state and not the note's, so it is not remembered:
    /// the live probe was told "try again later" under memory pressure, and a
    /// model still downloading, a rate limit and a timeout say the same. Named
    /// as `AskModel.notice(for:)` names them: macOS 26 throws
    /// `GenerationError`, macOS 27 `LanguageModelError`.
    nonisolated static func repeats(_ error: Error) -> Bool {
        guard #available(macOS 26, *) else { return false }
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize, .guardrailViolation, .refusal, .unsupportedLanguageOrLocale: return true
            default: break
            }
        }
        #if compiler(>=6.4)
        if #available(macOS 27, *), let model = error as? LanguageModelError {
            switch model {
            case .contextSizeExceeded, .guardrailViolation, .refusal, .unsupportedLanguageOrLocale: return true
            default: break
            }
        }
        #endif
        return false
    }
}
