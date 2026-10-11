import Foundation

/// Why Ask has no answer to show, in a line the sheet can print. `opensSettings`
/// adds the button that opens the pane that fixes it.
struct AskNotice: Equatable {
    let text: String
    let opensSettings: Bool
}

/// Where one question in the chat stands.
enum AskTurnState: Equatable {
    /// Working it out. The text names the lookup being made; nil before the first.
    case lookingUp(String?)
    /// The answer is streaming in.
    case answering
    case answered
    /// Stop ended it; the turn keeps the text that had streamed.
    case stopped
    /// It could not be answered. The notice is the turn's own.
    case failed(AskNotice)

    var isInProgress: Bool {
        switch self {
        case .lookingUp, .answering: return true
        case .answered, .stopped, .failed: return false
        }
    }
}

/// One question and its answer. Only the chat's last turn is ever in progress;
/// the turns before it do not change.
struct AskTurn: Identifiable, Equatable {
    let id: UUID
    let question: String
    var answer: String
    var state: AskTurnState
    /// `AskRequest.provenance` of each lookup the answer made, in order.
    var provenance: [String]
    /// The places the answer rests on, picked when it finishes; none before then.
    var sources: [AskSource]

    init(id: UUID = UUID(), question: String, answer: String = "", state: AskTurnState = .lookingUp(nil),
         provenance: [String] = [], sources: [AskSource] = []) {
        self.id = id
        self.question = question
        self.answer = answer
        self.state = state
        self.provenance = provenance
        self.sources = sources
    }
}

/// Where the chat is shown.
enum AskPlacement: String, CaseIterable {
    case sheet, panel
}
