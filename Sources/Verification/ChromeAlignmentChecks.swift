import Foundation

/// Two things that line up: the window buttons with the chrome row beside
/// them, and a period row's hover tint with the card it tints.
enum ChromeAlignmentChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The window buttons sit in the middle of the chrome row at any zoom", buttonsCentred),
        ("A period row's hover tint is its card's, not the whole button's", periodTintIsTheCards),
    ]

    private static func buttonsCentred() -> [String] {
        var problems: [String] = []
        let button: CGFloat = 16
        // The row at 80%, 100% and 160% zoom, and one of an odd height.
        for row in [CGFloat(42), 50, 75, 80] {
            let placed = TrafficLightCentreAnchor.placement(row: row, button: button)
            expect(placed.band == row, "a \(row)pt row is a band of \(placed.band)", &problems)
            let above = placed.band - button - placed.y
            expect(abs(above - placed.y) <= 1,
                   "in a \(row)pt row a button has \(placed.y) below it and \(above) above", &problems)
            expect(placed.y == placed.y.rounded(), "in a \(row)pt row a button sits at \(placed.y)", &problems)
        }
        // A row shorter than a button never cuts the button off.
        let short = TrafficLightCentreAnchor.placement(row: 10, button: button)
        expect(short.band == button && short.y == 0,
               "a 10pt row is a band of \(short.band) with the button at \(short.y)", &problems)
        return problems
    }

    private static func periodTintIsTheCards() -> [String] {
        var problems: [String] = []
        expect(!HistoryTreeRow.buttonTints(isEmpty: false, isPeriod: true),
               "a month's whole button tints under the pointer", &problems)
        expect(HistoryTreeRow.buttonTints(isEmpty: false, isPeriod: false),
               "a plain row's button does not tint under the pointer", &problems)
        expect(!HistoryTreeRow.buttonTints(isEmpty: true, isPeriod: false),
               "an empty row's button tints under the pointer", &problems)
        return problems
    }
}
