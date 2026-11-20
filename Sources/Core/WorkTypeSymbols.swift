import Foundation

/// The SF Symbols a category may wear. Curated and grouped so the grid and
/// the browse menu stay legible and every name here exists on macOS 13; a
/// name typed by hand is checked by the editor against the symbol library
/// before it is kept.
enum WorkTypeSymbols {
    static let fallback = "tag.fill"

    static let groups: [(title: String, symbols: [String])] = [
        ("Built in", ["brain.head.profile", "person.2.fill", "tray.full.fill", "book.fill",
                      "cup.and.saucer.fill"]),
        ("Making", ["hammer.fill", "chevron.left.forwardslash.chevron.right", "paintbrush.pointed.fill",
                    "pencil.and.outline", "doc.text.fill", "text.book.closed.fill", "camera.fill",
                    "music.note", "film.fill", "waveform", "wand.and.stars", "sparkles"]),
        ("Talking", ["phone.fill", "video.fill", "bubble.left.and.bubble.right.fill", "envelope.fill",
                     "megaphone.fill", "person.3.fill"]),
        ("Thinking and study", ["lightbulb.fill", "graduationcap.fill", "magnifyingglass", "chart.bar.fill",
                                "chart.line.uptrend.xyaxis", "function", "globe", "map.fill"]),
        ("Running things", ["briefcase.fill", "calendar", "checklist", "list.bullet.clipboard.fill",
                            "banknote.fill", "cart.fill", "folder.fill", "gearshape.fill",
                            "wrench.and.screwdriver.fill"]),
        ("Body and rest", ["figure.run", "figure.mind.and.body", "heart.fill", "leaf.fill", "moon.fill",
                           "fork.knife", "house.fill", "gamecontroller.fill"]),
        ("Plain marks", ["tag.fill", "star.fill", "flag.fill", "bolt.fill", "flame.fill", "circle.fill",
                         "square.fill", "diamond.fill", "seal.fill", "target"])
    ]

    /// Every grouped symbol in one list, for the grid.
    static let curated: [String] = groups.flatMap(\.symbols)

    /// A readable title for a symbol name: "chart.line.uptrend.xyaxis" reads
    /// as "Chart line uptrend xyaxis". Good enough for a menu row that also
    /// shows the symbol itself.
    static func title(for symbol: String) -> String {
        let words = symbol.split(separator: ".").map(String.init).filter { $0 != "fill" }
        guard let first = words.first else { return symbol }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    // MARK: Letters and numbers

    /// The shape a letter or number sits in. Both exist for a–z and 0–50.
    enum GlyphStyle: String, CaseIterable, Codable {
        case circle, square

        var displayName: String { self == .circle ? "Circle" : "Square" }
        var suffix: String { self == .circle ? ".circle.fill" : ".square.fill" }
    }

    static let glyphNumberLimit = 50

    /// The characters offered as one-tap glyphs: A–Z, then 0–9.
    static let glyphChoices: [String] = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .compactMap { UnicodeScalar($0).map { String(Character($0)) } } + (0...9).map(String.init)

    /// The symbol for a typed letter or number, or nil when there is none: a
    /// single ASCII letter, or a whole number from 0 to 50.
    static func glyph(for text: String, style: GlyphStyle) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first,
           scalar.value >= UnicodeScalar("a").value, scalar.value <= UnicodeScalar("z").value {
            return trimmed + style.suffix
        }
        if trimmed.allSatisfy(\.isNumber), trimmed.count <= 2, let number = Int(trimmed),
           (0...glyphNumberLimit).contains(number) {
            return String(number) + style.suffix
        }
        return nil
    }

    /// The letter or number a glyph symbol stands for, when it is one.
    static func glyphText(of symbol: String) -> (text: String, style: GlyphStyle)? {
        for style in GlyphStyle.allCases where symbol.hasSuffix(style.suffix) {
            let text = String(symbol.dropLast(style.suffix.count))
            guard glyph(for: text, style: style) == symbol else { continue }
            return (text.uppercased(), style)
        }
        return nil
    }
}
