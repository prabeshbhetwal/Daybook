import Foundation
/// Guards the Yesterday card's figures: rows sorted by time with the rest
/// counted, the comparison with a typical day, and the peak part of the day.
enum DayRecapChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The recap sorts rows longest first, keeps three and counts the rest", rows),
        ("The recap compares the day with a typical one, and says nothing for under a minute", delta),
        ("The recap names the peak part only when it holds a fair share", peak),
    ]
    private static func session(_ name: String, _ worked: TimeInterval) -> DaySession {
        let span = DateInterval(start: SelfTest.base, duration: worked)
        return DaySession(id: UUID(), threadID: UUID(), name: name, workType: .deepWork, start: span.start,
                          end: span.end, worked: worked, stretches: 1, spans: [span], isRunning: false)
    }
    private static func input(_ sessions: [DaySession], apps: [(String, TimeInterval)] = [], focused: TimeInterval = 0,
                              typical: TimeInterval = 0, parts: [NoteDayPart: TimeInterval] = [:]) -> NoteDayInput {
        NoteDayInput(date: SelfTest.base, isCurrent: false, sessions: sessions, sessionCount: sessions.count,
                     apps: apps.map { AppRank(bundleID: $0.0, appName: $0.0, total: $0.1, share: 0, longest: $0.1) },
                     focused: focused, goal: 0, goalCredit: 0, typicalFocused: typical, typicalStretch: 0,
                     typicalDays: 13, longestStretch: nil, focusByPart: parts)
    }
    private static func rows() -> [String] {
        var problems: [String] = []
        let recap = DayRecap(input([session("A", 60), session("B", 7_200), session("C", 600), session("D", 60)],
                                   apps: [("Dia", 7_440), ("Claude", 16_020), ("Idle", 0), ("Zed", 180), ("Arc", 180)]))
        expect(recap.sessions.map(\.name) == ["B", "C", "A"] && recap.moreSessions == 1,
               "sessions are \(recap.sessions.map(\.name)) +\(recap.moreSessions)", &problems)
        expect(recap.apps.map(\.name) == ["Claude", "Dia", "Arc"] && recap.moreApps == 1,
               "apps are \(recap.apps.map(\.name)) +\(recap.moreApps), an idle app counts for nothing", &problems)
        return problems
    }
    private static func delta() -> [String] {
        var problems: [String] = []
        let above = DayRecap(input([], focused: 37_140, typical: 33_960)).delta
        expect(above?.isAbove == true && above?.text == "53m above your typical 9h 26m"
               && above?.detail == "The median of 13 days with focus in your last 14.", "delta is \(String(describing: above))", &problems)
        let below = DayRecap(input([], focused: 3_600, typical: 7_200)).delta
        expect(below?.isAbove == false && below?.text == "1h below your typical 2h", "below is \(String(describing: below))", &problems)
        expect(DayRecap(input([], focused: 7_230, typical: 7_200)).delta == nil, "a 30s difference is left out", &problems)
        expect(DayRecap(input([], focused: 7_200, typical: 0)).delta == nil, "no typical day, no comparison", &problems)
        return problems
    }
    private static func peak() -> [String] {
        var problems: [String] = []
        let afternoon = DayRecap(input([], parts: [.morning: 3_600, .afternoon: 17_340])).peak
        expect((afternoon?.label ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ") == "Afternoon, noon–5 pm" && afternoon?.focused == 17_340, "peak is \(String(describing: afternoon))", &problems)
        expect(DayRecap(input([], parts: [.morning: 3_000, .afternoon: 3_100, .evening: 3_000, .night: 3_000])).peak == nil,
               "a part under 40% of the day is no peak", &problems)
        expect(DayRecap(input([], parts: [.morning: 30])).peak == nil, "under a minute is no peak", &problems)
        return problems
    }
}
