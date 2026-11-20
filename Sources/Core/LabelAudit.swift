import Foundation

/// What an AI-made label may be, and when two names are the same (Phase C, rulings C6 and C28). The model
/// never sees addresses, titles or content, so a label cannot carry them; this keeps what it returns to a
/// short plain name all the same.
enum LabelAudit {
    static let maxWords = 3

    /// The label as it will be kept: ends trimmed, runs of spaces and tabs one space, or nil. One to
    /// `maxWords` words, at most `WorkTypeDefinition.nameLimit` characters, each a letter in any script or the
    /// single space between words. A newline inside is prose rather than a name, so it is refused.
    static func clean(_ proposal: String) -> String? {
        let trimmed = proposal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let label = words.joined(separator: " ")
        guard (1...maxWords).contains(words.count), label.count <= WorkTypeDefinition.nameLimit,
              label.allSatisfy({ $0.isLetter || $0 == " " }), formatCharactersAreJoins(label) else { return nil }
        return label
    }

    /// The zero-width non-joiner and joiner.
    private static let joiners: Set<Unicode.Scalar> = ["\u{200C}", "\u{200D}"]

    /// A letter can carry an invisible format character. Only a joiner or non-joiner straight after a letter or
    /// its mark may stay (Persian, Sinhala and some Indic words need them; Sinhala's comes after a virama).
    /// `matches` ignores them, so a lookalike is the same name.
    private static func formatCharactersAreJoins(_ label: String) -> Bool {
        var previous: Unicode.Scalar?
        for scalar in label.unicodeScalars {
            if scalar.properties.generalCategory == .format {
                guard joiners.contains(scalar), let previous, isLetterOrMark(previous) else { return false }
            }
            previous = scalar
        }
        return true
    }

    private static func isLetterOrMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// The name without invisible format characters, for comparing names.
    static func visible(_ name: String) -> String {
        var visible = String.UnicodeScalarView()
        visible.append(contentsOf: name.unicodeScalars.filter { $0.properties.generalCategory != .format })
        return String(visible)
    }

    /// The same name ignoring case, invisible format characters and a final "s" or "es": film and Films, Class
    /// and Classes, Bus and Buses, Fi\u{200D}lms and Films.
    static func matches(_ first: String, _ second: String) -> Bool {
        !forms(first).isDisjoint(with: forms(second))
    }

    private static func forms(_ name: String) -> Set<String> {
        let lower = visible(name).lowercased()
        var forms: Set<String> = [lower]
        if lower.hasSuffix("s") { forms.insert(String(lower.dropLast())) }
        if lower.hasSuffix("es") { forms.insert(String(lower.dropLast(2))) }
        return forms
    }
}
