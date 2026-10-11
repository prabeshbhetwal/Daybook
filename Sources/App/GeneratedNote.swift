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
/// them by time spent.
@available(macOS 26, *)
@Generable struct GeneratedPeriodNote {
    @Guide(description: "At most two sentences naming the two or three sessions that took the most time, each with its duration exactly as the facts write it, such as 11h or 6h 36m. Quote session names exactly as written. They are listed by time spent, so do not say they happened in order, and do not add durations together.")
    var story: String
    @Guide(description: "One sentence on the first listed observation, quoting its figures exactly as listed.")
    var pattern: String
}
