import CoreGraphics

/// How large the menu-bar panel may be on the screen it is opening on.
///
/// It was a fixed 320pt wide with no height limit and no scroll region, so on a
/// 14" display the lower half — Settings, and the Quit button — simply ran off
/// the bottom with no way to reach it.
struct PopoverMetrics: Equatable {
    let width: CGFloat
    let maxHeight: CGFloat
    let twoColumn: Bool
    /// Tightens row heights and group spacing. Turned on where the screen is
    /// short enough that the difference decides whether the panel fits.
    let dense: Bool

    /// Row height for a settings row.
    var rowHeight: CGFloat { dense ? 22 : 26 }
    /// Space above a settings group heading.
    var groupSpacing: CGFloat { dense ? 3 : Tokens.Space.s }
    /// How many apps the Top Apps list shows.
    var topAppCount: Int { dense ? 3 : 4 }
    /// Padding around the whole panel.
    var outerPadding: CGFloat { dense ? 12 : Tokens.Space.l }
    /// Space between the panel's stacked blocks.
    var stackSpacing: CGFloat { dense ? 8 : Tokens.Space.m }

    /// How tall the scrolling middle may be, once the pinned header, hero and
    /// footer have taken their share.
    ///
    /// Measured from the rendered states rather than estimated: header, goal
    /// row, timer, subtitle and footer come to about 193pt on the tallest one.
    /// The previous 320 was a guess and 127pt too generous, which capped the
    /// middle — and produced a scrollbar — on screens with room to spare.
    var scrollCap: CGFloat { max(1, maxHeight - 200) }

    /// Leaves a margin below the panel rather than filling the screen edge to
    /// edge, which reads as a window that failed to size itself.
    private static let heightShare: CGFloat = 0.94
    /// Only invalid or nonsensical screen reports use a known safe geometry;
    /// every valid usable size remains a hard bound, however small.
    private static let fallbackVisible = CGSize(width: 1_440, height: 900)

    /// - Parameter visible: the screen's usable area, menu bar and Dock excluded.
    static func fitting(_ visible: CGSize) -> PopoverMetrics {
        let usable = visible.width.isFinite && visible.height.isFinite
            && visible.width > 0 && visible.height > 0 ? visible : fallbackVisible
        return PopoverMetrics(
            width: min(Tokens.popoverWidth, usable.width),
            maxHeight: min(usable.height, usable.height * heightShare),
            twoColumn: false,
            dense: usable.height < 950)
    }
}
