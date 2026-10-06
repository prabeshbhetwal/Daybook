import SwiftUI

extension Tokens {
    /// Type by role. A view names what its text is — a page title, a card's
    /// figure, a row's name — and the role fixes size, weight and face, so
    /// the same role reads the same in every area. Sizes had been tokens
    /// with each view picking its own weight, and one role ended up at five
    /// sizes and weights across the app.
    ///
    /// Rules: a weight changes only to show state (selected, current, live),
    /// never to restyle a role. A compact surface — the menu bar panel —
    /// steps each title down one role. Digits may be made monospaced. Only
    /// this file builds a font; `build.sh` fails a view that sets a size, a
    /// system text style or a weight of its own.
    enum Typography {
        /// Every text size the product may use. 13, 14 and 15 sit one point
        /// apart on purpose, as native macOS control, row and section text
        /// do. Only the roles below read these.
        enum Size {
            static let micro: CGFloat = 9
            static let caption: CGFloat = 10
            static let ring: CGFloat = 11
            static let body: CGFloat = 12
            static let control: CGFloat = 13
            static let row: CGFloat = 14
            static let heading: CGFloat = 15
            static let headline: CGFloat = 20
            static let title: CGFloat = 22
            static let figure: CGFloat = 24
            static let display: CGFloat = 36

            /// Ascending, for the checks that hold the scale to its shape.
            static let all: [CGFloat] = [micro, caption, ring, body, control,
                                         row, heading, headline, title, figure, display]
        }

        /// The live timer: the one figure a page is about.
        static let display = Font.system(size: Size.display, weight: .semibold, design: .rounded)
            .monospacedDigit()
        /// A page naming itself: a Settings page, Awards, a session report.
        static let title = Font.system(size: Size.title, weight: .semibold)
        /// The story's sentence at the head of a day, a period or an app.
        static let headline = Font.system(size: Size.headline, weight: .semibold)
        /// The number a tile exists to show.
        static let figure = Font.system(size: Size.figure, weight: .semibold, design: .rounded)
            .monospacedDigit()
        /// The live clock in a one-row strip, where `display` would set the
        /// row's height on its own.
        static let clock = Font.system(size: Size.headline, weight: .semibold, design: .rounded)
            .monospacedDigit()
        /// A section, a sheet, a rail heading, a day heading search results,
        /// and a figure set beside one.
        static let heading = Font.system(size: Size.heading, weight: .semibold)
        /// The name of a thing in a list or on a card — a session, a setting,
        /// a category, a History month — and the figure beside it. A month
        /// card at 19pt bold read a step larger than every card around it.
        static let rowTitle = Font.system(size: Size.row, weight: .medium)
        /// The size AppKit gives its own controls, at the weight a field's own
        /// text is set in, and a paragraph set for reading. Editable text is
        /// not a label and must not be styled like one.
        static let control = Font.system(size: Size.control, weight: .regular)
        /// Supporting text: facts, times, notes, a row's duration.
        static let body = Font.system(size: Size.body, weight: .regular)
        /// A word that labels or acts: a card's label, a text button, a small
        /// heading, a date heading a group of rows.
        static let label = Font.system(size: Size.body, weight: .semibold)
        /// The smallest text a reader is expected to read: chips, badges,
        /// chart labels.
        static let caption = Font.system(size: Size.caption, weight: .semibold)
        /// The spaced capitals above a headline.
        static let eyebrow = Font.system(size: Size.caption, weight: .bold)
        /// A goal ring's label.
        static let ring = Font.system(size: Size.ring, weight: .semibold, design: .rounded)
        /// Small figures in a grid, in the rounded face the larger figures use.
        static let microFigure = Font.system(size: Size.caption, weight: .medium, design: .rounded)
            .monospacedDigit()
        /// Marks too small to read as words: a tick, a cross, a chevron.
        static let micro = Font.system(size: Size.micro, weight: .bold)
        static let menuBar = Font.system(size: NSFont.systemFontSize).monospacedDigit()
        /// The label role for a symbol AppKit draws itself, where no SwiftUI
        /// font reaches: on macOS 26 a bordered menu reads only its image.
        static let labelSymbol = NSImage.SymbolConfiguration(pointSize: Size.body, weight: .semibold)

        /// A letter or symbol sized by the shape it fills — an app's
        /// monogram, a ring's tick, the menu bar glyph — rather than by the
        /// text around it.
        static func fitted(_ size: CGFloat, weight: Font.Weight) -> Font {
            Font.system(size: size, weight: weight)
        }

        /// The away prompt's answers and reason field are set in SF Rounded:
        /// at button size SF Pro's lowercase t reads as a chopped letter
        /// (verified against plain AppKit), and Rounded's terminals read whole.
        static func answer(compact: Bool, field: Bool = false) -> Font {
            Font.system(size: compact ? Size.body : Size.control,
                        weight: field ? .regular : .semibold, design: .rounded)
        }
    }
}
