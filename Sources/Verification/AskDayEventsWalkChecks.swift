import Foundation

/// Ask Daybook v2 part 2, after the final review: which days `dayEvents`
/// reads and how it counts them. A break still going is told so far on every
/// day it touches, a cut walk counts only the days that have something to
/// tell, and the Mac log's search reads what a scan of it would.
enum AskDayEventsWalkChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A break still going is told so far, and the days it touched are listed", runningBreakIsToldSoFar),
        ("A break going since last night ended at midnight on yesterday", runningBreakEndedAtMidnight),
        ("A cut walk counts only the days that have something to tell", cutWalkCountsDaysWithSomething),
        ("The Mac log's search finds what a scan of every event finds", logSearchReadsWhatAScanReads),
    ]

    private static let dot = "\u{00B7}"

    private static func runningBreakIsToldSoFar() -> [String] {
        AskDataFixture.with { f, problems in
            f.engine.start(workType: .breakTime, intent: "Lunch")
            f.clock.advance(20 * 60)
            f.store.catchUpWithEngine()
            let today = f.store.askLookup(.dayEvents(.today))
            expect(today.hasPrefix("Wed 15 Nov:\nfrom 9:13am, 20m so far \(dot) break \u{201C}Lunch\u{201D}\n"),
                   "a running break reads: \(today)", &problems)
            expect(!today.contains("to 9:33am"), "a running break has an end: \(today)", &problems)
            // Its day is a day with something to tell, though the archive does not hold the break yet.
            let week = f.store.askLookup(.dayEvents(.thisWeek))
            expect(week.hasPrefix("Wed 15 Nov \(dot) 1 break, 20m\n"), "this week lacks the running break: \(week)", &problems)
        }
    }

    private static func runningBreakEndedAtMidnight() -> [String] {
        AskDataFixture.with { f, problems in
            let (night, small) = (f.moment(1, 23), f.moment(0, 1))
            f.clock.value = night
            f.engine.start(workType: .breakTime, intent: "Nap")
            f.clock.value = small
            f.store.catchUpWithEngine()
            let yesterday = f.store.askLookup(.dayEvents(.yesterday))
            expect(yesterday.contains("from 11:00pm until midnight \(dot) break \u{201C}Nap\u{201D} \(dot) 1h"),
                   "yesterday's slice reads: \(yesterday)", &problems)
            let today = f.store.askLookup(.dayEvents(.today))
            expect(today.contains("from midnight, 1h so far \(dot) break \u{201C}Nap\u{201D}"),
                   "today's slice reads: \(today)", &problems)
            let week = f.store.askLookup(.dayEvents(.thisWeek))
            expect(week.contains("Wed 15 Nov \(dot) 1 break, 1h") && week.contains("Tue 14 Nov \(dot) 1 break, 1h"),
                   "this week lacks one of the two days: \(week)", &problems)
        }
    }

    /// Eighty breaks on every second day, 40 to 198 days back: the walk is cut
    /// by the text's size long before it reaches them all, and the days it
    /// did not read are counted from what the archive holds. A day between
    /// two breaks has nothing to tell and is not one of them.
    private static func cutWalkCountsDaysWithSomething() -> [String] {
        AskDataFixture.with { f, problems in
            for index in 0..<80 {
                let back = 40 + 2 * index
                let record = SessionRecord(name: "", workType: .breakTime, start: f.moment(back, 15, 40),
                                           end: f.moment(back, 15, 55), workSeconds: 900)
                guard f.engine.archive.append(record) == nil else { problems.append("a break was not saved"); return }
            }
            let own = (0..<40).filter { back in
                let day = f.moment(back, 12)
                let projection = f.store.storyDayProjection(on: day, calendar: f.calendar)
                let rests = projection.sessions.contains { if case .rest = $0 { return true } else { return false } }
                let answers = projection.chronology.contains {
                    switch $0 {
                    case .decision, .pending: return true
                    default: return false
                    }
                }
                return rests || answers || f.store.macAccount(on: day) != nil
            }.count
            let text = f.store.askLookup(.dayEvents(.allTime))
            guard let tail = text.split(separator: "\n").last,
                  let match = tail.wholeMatch(of: #/Newest (\d+) of (\d+) days\./#),
                  let shown = Int(match.1), let total = Int(match.2) else {
                problems.append("the text does not end with its count: \(text.suffix(60))"); return
            }
            let lines = text.split(separator: "\n").filter { $0.contains(" \(dot) ") }.count
            expect(shown == lines && shown < total, "it says \(shown) of \(total) days with \(lines) lines", &problems)
            expect(total == 80 + own, "it counts \(total) days, not \(80 + own)", &problems)
        }
    }

    /// Events appended out of order, with a crash found days later whose
    /// window reaches far past its time, asked about by intervals of every
    /// length from a point to a week, from before the first to after the last.
    private static func logSearchReadsWhatAScanReads() -> [String] {
        var problems: [String] = []
        let folder = SelfTest.scratchDirectory()
        let log = MachineEventLog(directory: folder)
        func at(_ hours: Double) -> Date { SelfTest.base.addingTimeInterval(hours * 3_600) }
        var events = (0..<200).map { MachineEvent(kind: $0 % 2 == 0 ? .lock : .unlock, at: at(Double($0) * 3)) }
        events += [MachineEvent(kind: .crashed, at: at(10), latest: at(130)), MachineEvent(kind: .wake, at: at(5))]
        guard log.append(Array(events.reversed())) else { return ["could not log the events"] }
        var asked = 0
        for start in stride(from: -5.0, through: 620.0, by: 7.0) {
            for hours in [0.0, 1, 24, 200] {
                let interval = DateInterval(start: at(start), duration: hours * 3_600)
                let want = log.events.filter { $0.at < interval.end && $0.end >= interval.start }
                let got = log.events(in: interval)
                asked += 1
                if got != want {
                    problems.append("\(hours) h from \(start) h: \(got.count) events, not \(want.count)")
                    break
                }
            }
        }
        expect(asked > 300, "only \(asked) intervals were asked", &problems)
        return problems
    }
}
