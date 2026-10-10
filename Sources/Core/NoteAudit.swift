import Foundation

/// Rejects a note that states a figure its facts do not hold.
enum NoteAudit {
    /// The maximal runs of ASCII digits in `text`, leading zeros trimmed
    /// ("05" is "5"; "0" stays), so "09:13" and "9:13" name the same figures.
    static func digitRuns(in text: String) -> Set<String> {
        var runs: Set<String> = []
        var run = ""
        func close() {
            guard !run.isEmpty else { return }
            let trimmed = run.drop { $0 == "0" }
            runs.insert(trimmed.isEmpty ? "0" : String(trimmed))
            run = ""
        }
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x30, scalar.value <= 0x39 {
                run.unicodeScalars.append(scalar)
            } else {
                close()
            }
        }
        close()
        return runs
    }

    /// Whether every figure in the note's story, pattern and tip is also in the facts.
    static func passes(_ note: WrittenNote, facts: NoteFacts) -> Bool {
        // ponytail: digits only; numbers written as words pass unchecked, widen if the note probe finds any.
        let written = note.story + " " + note.pattern + " " + (note.tip ?? "")
        return digitRuns(in: written).isSubset(of: digitRuns(in: facts.text))
    }
}
