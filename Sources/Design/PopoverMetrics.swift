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
    var scrollCap: CGFloat { max(200, maxHeight - 200) }

    /// Leaves a margin below the panel rather than filling the screen edge to
    /// edge, which reads as a window that failed to size itself. Close to the
    /// full height because the panel only ever reaches it with Settings open,
    /// and scrolling a settings list you deliberately expanded is worse than a
    /// tall panel.
    private static let heightShare: CGFloat = 0.94
    /// Below these the panel would be too cramped to be worth splitting. Set so
    /// a 13" MacBook Pro (1440pt wide) qualifies: it is the machine that needs
    /// two panes most, because a single column there is twice as tall as the
    /// screen can hold.
    private static let twoColumnMinimumHeight: CGFloat = 640
    private static let twoColumnMinimumWidth: CGFloat = 1_200
    private static let twoColumnWidth: CGFloat = 560

    /// - Parameter visible: the screen's usable area, menu bar and Dock excluded.
    static func fitting(_ visible: CGSize) -> PopoverMetrics {
        let twoColumn = visible.width >= twoColumnMinimumWidth
            && visible.height >= twoColumnMinimumHeight
        return PopoverMetrics(
            width: twoColumn ? twoColumnWidth : Tokens.popoverWidth,
            // Floored so a very small or misreported screen still yields a
            // usable panel rather than a sliver.
            maxHeight: max(480, visible.height * heightShare),
            twoColumn: twoColumn,
            // A 14" has room to breathe; a 13" does not, and the panel should
            // tighten rather than scroll.
            dense: visible.height < 950)
    }
}
