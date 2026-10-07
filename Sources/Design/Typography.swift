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

        /// One case per text role, so a check can read a role's size without
        /// reading a `Font`. `Size` stays the base points; the zoom is applied
        /// once, in `pointSize(of:)`.
        enum Role: CaseIterable {
            case display, title, headline, figure, clock, heading, rowTitle
            case control, body, label, caption, eyebrow, ring, microFigure, micro
            /// The away prompt's answers and reason field: roomy, and compact.
            case answer, answerCompact

            /// The size at 100%.
            var baseSize: CGFloat {
                switch self {
                case .display: return Size.display
                case .title: return Size.title
                case .headline, .clock: return Size.headline
                case .figure: return Size.figure
                case .heading: return Size.heading
                case .rowTitle: return Size.row
                case .control, .answer: return Size.control
                case .body, .label, .answerCompact: return Size.body
                case .caption, .eyebrow, .microFigure: return Size.caption
                case .ring: return Size.ring
                case .micro: return Size.micro
                }
            }
        }

        /// A role's size at the current zoom. Read it while a view draws, so
        /// the view is drawn again when the zoom changes.
        static func pointSize(of role: Role) -> CGFloat { role.baseSize * ZoomModel.shared.scale }

        /// The live timer: the one figure a page is about.
        static var display: Font {
            Font.system(size: pointSize(of: .display), weight: .semibold, design: .rounded).monospacedDigit()
        }
        /// A page naming itself: a Settings page, Awards, a session report.
        static var title: Font { Font.system(size: pointSize(of: .title), weight: .semibold) }
        /// The story's sentence at the head of a day, a period or an app.
        static var headline: Font { Font.system(size: pointSize(of: .headline), weight: .semibold) }
        /// The number a tile exists to show.
        static var figure: Font {
            Font.system(size: pointSize(of: .figure), weight: .semibold, design: .rounded).monospacedDigit()
        }
        /// The live clock in a one-row strip, where `display` would set the
        /// row's height on its own.
        static var clock: Font {
            Font.system(size: pointSize(of: .clock), weight: .semibold, design: .rounded).monospacedDigit()
        }
        /// A section, a sheet, a rail heading, a day heading search results,
        /// and a figure set beside one.
        static var heading: Font { Font.system(size: pointSize(of: .heading), weight: .semibold) }
        /// The name of a thing in a list or on a card — a session, a setting,
        /// a category, a History month — and the figure beside it. A month
        /// card at 19pt bold read a step larger than every card around it.
        static var rowTitle: Font { Font.system(size: pointSize(of: .rowTitle), weight: .medium) }
        /// The size AppKit gives its own controls, at the weight a field's own
        /// text is set in, and a paragraph set for reading. Editable text is
        /// not a label and must not be styled like one.
        static var control: Font { Font.system(size: pointSize(of: .control), weight: .regular) }
        /// Supporting text: facts, times, notes, a row's duration.
        static var body: Font { Font.system(size: pointSize(of: .body), weight: .regular) }
        /// A word that labels or acts: a card's label, a text button, a small
        /// heading, a date heading a group of rows.
        static var label: Font { Font.system(size: pointSize(of: .label), weight: .semibold) }
        /// The smallest text a reader is expected to read: chips, badges,
        /// chart labels.
        static var caption: Font { Font.system(size: pointSize(of: .caption), weight: .semibold) }
        /// The spaced capitals above a headline.
        static var eyebrow: Font { Font.system(size: pointSize(of: .eyebrow), weight: .bold) }
        /// A goal ring's label.
        static var ring: Font { Font.system(size: pointSize(of: .ring), weight: .semibold, design: .rounded) }
        /// Small figures in a grid, in the rounded face the larger figures use.
        static var microFigure: Font {
            Font.system(size: pointSize(of: .microFigure), weight: .medium, design: .rounded).monospacedDigit()
        }
        /// Marks too small to read as words: a tick, a cross, a chevron.
        static var micro: Font { Font.system(size: pointSize(of: .micro), weight: .bold) }
        /// The menu bar item is not scaled: macOS fixes the menu bar's height.
        static let menuBar = Font.system(size: NSFont.systemFontSize).monospacedDigit()
        /// The label role for a symbol AppKit draws itself, where no SwiftUI
        /// font reaches: on macOS 26 a bordered menu reads only its image.
        static var labelSymbol: NSImage.SymbolConfiguration {
            NSImage.SymbolConfiguration(pointSize: pointSize(of: .label), weight: .semibold)
        }

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
            Font.system(size: pointSize(of: compact ? .answerCompact : .answer),
                        weight: field ? .regular : .semibold, design: .rounded)
        }
    }
}
