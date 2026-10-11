import FoundationModels

/// What the model fills in for a day. The audit reads the figures in all three.
@available(macOS 26, *)
@Generable struct GeneratedNote {
    @Guide(description: "At most two sentences on what the person worked on and in what order. Quote session names exactly as written.")
    var story: String
    @Guide(description: "One sentence building on exactly one of the observations or context lines.")
    var pattern: String
    // Tone is wording, not facts, so this is one place the guide carries a rule the facts cannot: the probe found
    // five tips in thirteen turning a drop in focus into a mild reprimand, though the instructions say not to scold.
    @Guide(description: "One concrete action for the next day, built on one of the observations. Never comment on less focus or a missed goal.")
    var tip: String
}

/// What the model fills in for a week or month, which has no tip. The probe
/// found these notes dropping their figures ("Thesis for hours"), spelling
/// them out, and listing sessions "then" as if in order though the facts list
/// them by time spent. This form is for a period whose facts name three
/// sessions; `PeriodForm` picks the form for fewer.
@available(macOS 26, *)
@Generable struct GeneratedPeriodNote {
    @Guide(description: "At most two sentences naming up to three of the sessions that took the most time, as many as the facts name, each with its duration written in digits exactly as the facts write it, such as 11h or 6h 36m. Quote session names exactly as written. They are listed by time spent, so do not say they happened in order, and do not add durations together.")
    var story: String
    @Guide(description: "One sentence on the first listed observation, quoting its figures exactly as listed.")
    var pattern: String
}

/// A period whose facts name one session. Told "as many as the facts name", the
/// model still padded a one-session week: "You spent 1h on Reading on Wednesday
/// 29 July 2026 and 1h on Reading on Wednesday 29 July 2026." Wording the guide
/// every way short of a sentence to copy did not stop it; this one gives the form.
@available(macOS 26, *)
@Generable struct GeneratedSoloPeriodNote {
    @Guide(description: "A sentence of the form You spent DURATION on NAME. with the name and duration of the one session listed under Most time went to, exactly as listed. Write only that sentence.")
    var story: String
    @Guide(description: "One sentence on the first listed observation, quoting its figures exactly as listed.")
    var pattern: String
}

/// A period whose facts name two sessions, which the three-session guide padded
/// with a third ("and 11h on Thesis again").
@available(macOS 26, *)
@Generable struct GeneratedPairPeriodNote {
    @Guide(description: "A sentence of the form You spent DURATION on NAME and DURATION on NAME. with the two sessions listed under Most time went to, each once, with its name and duration exactly as listed. Write only that sentence.")
    var story: String
    @Guide(description: "One sentence on the first listed observation, quoting its figures exactly as listed.")
    var pattern: String
}

/// Which form a week's or month's note is asked for: one by the number of
/// sessions its facts name.
@available(macOS 26, *)
enum PeriodForm: Equatable {
    case solo, pair, trio

    static func form(for facts: NoteFacts) -> PeriodForm {
        facts.namedSessions == 1 ? .solo : facts.namedSessions == 2 ? .pair : .trio
    }

    func write(_ facts: NoteFacts, in session: LanguageModelSession, options: GenerationOptions) async throws -> WrittenNote {
        switch self {
        case .solo:
            let note = try await session.respond(to: facts.text, generating: GeneratedSoloPeriodNote.self, options: options).content
            return WrittenNote(story: note.story, pattern: note.pattern, tip: nil)
        case .pair:
            let note = try await session.respond(to: facts.text, generating: GeneratedPairPeriodNote.self, options: options).content
            return WrittenNote(story: note.story, pattern: note.pattern, tip: nil)
        case .trio:
            let note = try await session.respond(to: facts.text, generating: GeneratedPeriodNote.self, options: options).content
            return WrittenNote(story: note.story, pattern: note.pattern, tip: nil)
        }
    }
}
