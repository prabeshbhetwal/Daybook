import Foundation
import FoundationModels

/// What the model fills in for one finished stretch (Phase C, ruling C6): the number of the category that
/// fits, `new` with a label of its own, or `none`. Constrained to those, so nothing else can be said; what
/// the answer then means is `AIAnswerResolver`'s to decide.
@available(macOS 26, *)
@Generable struct CategoryAnswer {
    @Guide(description: "The number of the category that fits, new when none fits and the activities say clearly what the time was, none when the time was mixed or unclear.",
           .anyOf(["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20",
                   "new", "none"]))
    var choice: String
    @Guide(description: "The label, one to three words, when choice is new. Otherwise empty.")
    var label: String
}

/// The model's reply as the assistant takes it, or a test's stand-in for it.
struct CategoryAnswerChoice: Equatable {
    let choice: String
    let label: String
}

/// The one question: a fresh session each time, so nothing from one stretch leaks into the next, answered
/// greedily so the same facts give the same answer.
enum CategoryModel {
    /// The prompt (C23), changed only with a ruling.
    static let instructions = "You file one finished stretch of time for the person who spent it. You get what the time was spent on, "
        + "measured by the app, and a numbered list of the person's categories. Answer with the number of the category that fits. "
        + "Answer new, with a label of one to three words, only when no category fits and the activities say clearly what the "
        + "time was. Answer none when the time was mixed or unclear. Never put times, numbers or app names in a label."

    @MainActor @available(macOS 26, *)
    static func ask(_ question: CategoryQuestion) async throws -> CategoryAnswerChoice {
        let session = LanguageModelSession(instructions: instructions)
        let reply = try await session.respond(to: question.text, generating: CategoryAnswer.self,
                                              options: NameSuggester.options).content
        return CategoryAnswerChoice(choice: reply.choice.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                    label: reply.label)
    }
}
