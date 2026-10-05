import Foundation

/// The rail's printed figures add up: the goal's line joins it to the
/// headline, and the Mac tile's rows make its total.
enum StoryRailFiguresChecks {
    static let tests: [(String, () -> [String])] = [
        ("The goal tile shows how its figure comes from the headline's, and the Mac tile's rows add up to its total",
         figuresAddUp)
    ]

    static func figuresAddUp() -> [String] {
        var problems: [String] = []
        // Today's case: 5h 16m logged, 4h 43m counted, seconds that rounded apart.
        let logged: TimeInterval = 5 * 3_600 + 16 * 60 + 40
        let counted: TimeInterval = 4 * 3_600 + 43 * 60 + 50
        let equation = StoryRailFigures.goalEquation(logged: logged, counted: counted)
        if equation != "5h 16m logged − 33m with no app use recorded" {
            problems.append("the goal line read \(equation ?? "nothing")")
        }
        if StoryRailFigures.goalEquation(logged: 3_600, counted: 3_600 + 30) != nil {
            problems.append("a goal with nothing taken away still drew a line")
        }
        let rows = StoryRailFigures.macRows(tracked: 4 * 3_600 + 59 * 60 + 40,
                                            insideSessions: 4 * 3_600 + 44 * 60 + 30,
                                            countedFocus: counted)
        if rows.duringFocus != StoryRailFigures.minutes(counted) {
            problems.append("During focus (\(rows.duringFocus)m) was not the goal's figure")
        }
        if rows.duringPauses != 0 || rows.outside != 15 {
            problems.append("pauses \(rows.duringPauses)m and outside \(rows.outside)m, not 0m and 15m")
        }
        if rows.total != rows.duringFocus + rows.duringPauses + rows.outside {
            problems.append("the Mac tile's total was not the sum of its rows")
        }
        // Credit can never exceed the app use it came from.
        let capped = StoryRailFigures.macRows(tracked: 600, insideSessions: 300, countedFocus: 900)
        if capped.duringFocus != 5 || capped.duringPauses != 0 || capped.outside != 5 {
            problems.append("focus beyond the app use inside sessions was not capped: \(capped)")
        }
        return problems
    }
}
