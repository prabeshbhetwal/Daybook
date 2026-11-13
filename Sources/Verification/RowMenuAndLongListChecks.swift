import Foundation
import SwiftUI

/// Guards the right-click menus and the long-list work. A menu offers what the
/// row's visible buttons offer, destructive last; a running session offers no
/// Remove. A report of hundreds of visits builds its rows once, measures each
/// column a handful of times and not once per row, and the 1 Hz ticker leaves
/// every session card but the running one alone.
enum RowMenuAndLongListChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session card's right-click menu mirrors its buttons, Remove last, none while running", sessionMenu),
        ("History, rule and category rows offer only what their buttons do", otherMenus),
        ("A report of 500 visits builds its rows fast and measures each column a few times, not per row",
         longReport),
        ("A tick redraws the running session card and no finished one", tickRedrawsOnlyTheRunningCard)
    ]

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private static func sessionMenu() -> [String] {
        var problems: [String] = []
        typealias Facts = SessionCardMenu.Facts
        func items(_ facts: Facts) -> [SessionCardMenu.Item] { SessionCardMenu.items(for: facts) }

        let finished = Facts(canRename: true, note: .absent, canContinue: true,
                             canSeeReport: true, canRemove: true)
        expect(items(finished) == [.continueSession, .rename, .addNote, .seeFullReport, .remove],
               "A finished session's menu was \(items(finished))", &problems)
        var again = finished
        again.canContinue = false
        again.canStartAgain = true
        again.note = .present
        expect(items(again) == [.startAgain, .rename, .editNote, .seeFullReport, .remove],
               "Start again, Edit note: \(items(again))", &problems)
        var both = again
        both.canContinue = true
        expect(items(both).first == .continueSession && !items(both).contains(.startAgain),
               "Continue and Start again were both offered: \(items(both))", &problems)

        var running = finished
        running.isRunning = true
        running.canContinue = false
        expect(!items(running).contains(.remove),
               "A running session offered Remove: \(items(running))", &problems)
        expect(items(running) == [.rename, .addNote, .seeFullReport],
               "A running session's menu was \(items(running))", &problems)

        // History drops what controls or removes a session.
        var history = finished
        history.canContinue = false
        history.canRemove = false
        expect(items(history) == [.rename, .addNote, .seeFullReport],
               "A History card's menu was \(items(history))", &problems)
        expect(items(Facts()).isEmpty, "A card with nothing to offer still had a menu", &problems)

        for facts in [finished, again, both, running, history] {
            expect(items(facts).keepsDestructiveLast, "Destructive item not last: \(items(facts))", &problems)
        }
        let removeTitle = SessionCardMenu.Item.remove
        expect(removeTitle.isDestructive && removeTitle.title == "Remove…",
               "Remove is not a destructive item that says a dialog follows", &problems)
        for item in [SessionCardMenu.Item.continueSession, .startAgain, .rename, .addNote, .editNote,
                     .seeFullReport, .remove] {
            let words = item.title.replacingOccurrences(of: "…", with: "").split(separator: " ")
            expect(words.allSatisfy { $0.first?.isUppercase == true },
                   "“\(item.title)” is not title case", &problems)
        }
        return problems
    }

    private static func otherMenus() -> [String] {
        var problems: [String] = []
        expect(HistoryRowMenu.items(isEmpty: false, isOpen: false) == [.open], "Closed row", &problems)
        expect(HistoryRowMenu.items(isEmpty: false, isOpen: true) == [.close], "Open row", &problems)
        expect(HistoryRowMenu.items(isEmpty: true, isOpen: false).isEmpty,
               "An empty period, whose header is disabled, offered a menu", &problems)

        let rules = ActivityRuleMenu.items()
        expect(rules == [.edit, .duplicate, .delete], "A rule's menu was \(rules)", &problems)
        expect(rules.keepsDestructiveLast && ActivityRuleMenu.Item.delete.title == "Delete…",
               "Delete is not last and marked as asking", &problems)

        typealias Categories = CategoryRowMenu
        expect(Categories.items(isRetired: false, isBreak: false, isLastStartable: false) == [.edit, .retire],
               "A category's menu", &problems)
        expect(Categories.items(isRetired: true, isBreak: false, isLastStartable: false) == [.edit, .restore],
               "A retired category's menu", &problems)
        expect(Categories.items(isRetired: false, isBreak: true, isLastStartable: false) == [.edit],
               "Break was offered Retire", &problems)
        expect(Categories.items(isRetired: false, isBreak: false, isLastStartable: true) == [.edit],
               "The last startable category was offered Retire", &problems)
        expect(Categories.items(isRetired: false, isBreak: false, isLastStartable: false).keepsDestructiveLast,
               "Retire is not last", &problems)
        return problems
    }

    private static func longReport() -> [String] {
        var problems: [String] = []
        let apps = (0..<12).map { ("com.example.app\($0)", "App \($0)") }
        let intervals: [RecordedActivity.Interval] = (0..<500).map { index in
            let start = base.addingTimeInterval(TimeInterval(index) * 190)
            let end = start.addingTimeInterval(TimeInterval(15 + (index * 37) % 170))
            return index % 25 == 24
                ? RecordedActivity.Interval(start: start, end: end.addingTimeInterval(120), bundleID: nil,
                                            appName: nil)
                : RecordedActivity.Interval(start: start, end: end, bundleID: apps[index % apps.count].0,
                                            appName: apps[index % apps.count].1)
        }
        let listed = SessionReport.listing(intervals)
        var measured = 0
        let width: (String) -> CGFloat = { measured += 1; return CGFloat($0.count) * 7 }

        let started = Date()
        let list = ReportActivityList.make(listed: listed, power: { _ in nil },
                                           gapTitle: { _ in "Not recorded" }, measure: width)
        let elapsed = Date().timeIntervalSince(started)

        expect(list.rows.count == listed.count && list.rows.count >= 480,
               "\(list.rows.count) rows for \(listed.count) listed visits", &problems)
        expect(list.rows.first?.interval == listed.last, "The latest visit is not first", &problems)
        expect(measured > 0 && measured <= 60,
               "Column widths were measured \(measured) times for \(list.rows.count) rows; "
               + "a handful is the most a list needs", &problems)
        expect(elapsed < 1.0, "Building 500 rows took \(elapsed) s", &problems)
        // The width is the widest row's, so no row is cut short of its text.
        let noMeasure: (String) -> CGFloat = { CGFloat($0.count) * 7 }
        expect(list.rows.allSatisfy { noMeasure($0.time) <= list.widths.time },
               "A time column narrower than one of its rows: \(list.widths.time)", &problems)
        expect(list.rows.allSatisfy { noMeasure($0.duration) <= list.widths.duration },
               "A duration column narrower than one of its rows: \(list.widths.duration)", &problems)
        expect(list.widths.level >= noMeasure("100%"), "The level column lost its floor", &problems)
        expect(list.rows.contains { $0.interval.isGap && $0.name == "Not recorded" },
               "A gap row lost its title", &problems)
        return problems
    }

    private static func tickRedrawsOnlyTheRunningCard() -> [String] {
        var problems: [String] = []
        func session(running: Bool, worked: TimeInterval) -> DaySession {
            DaySession(id: UUID(uuidString: running ? "00000000-0000-0000-0000-000000000001"
                                                    : "00000000-0000-0000-0000-000000000002")!,
                       threadID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
                       name: "Parser", workType: WorkType.startable.first ?? .breakTime,
                       start: base, end: base.addingTimeInterval(worked), worked: worked,
                       stretches: 1, spans: [], isRunning: running)
        }
        func card(_ session: DaySession) -> StableSessionCard {
            let signature = SessionCardSignature(
                session: session, apps: [], shape: nil, shapeCaption: nil, activity: nil,
                canContinue: false, canStartNewSession: false, isOpen: false,
                clock: session.isRunning ? "00:10" : nil, liveStatus: session.isRunning ? "running now" : nil,
                power: nil, recordIDs: [], notes: [], editorsOpen: [], metadataError: nil, isHistory: false,
                canRemove: !session.isRunning, removeBlockReason: nil, pauseTitle: "Pause",
                canControl: session.isRunning, minimumRecorded: 30)
            return StableSessionCard(signature: signature, card: { fatalError("a check does not draw") })
        }
        // One second on: the clock has moved for the running session only.
        expect(card(session(running: false, worked: 600)) == card(session(running: false, worked: 600)),
               "A finished card changed with nothing about it changed", &problems)
        expect(card(session(running: true, worked: 10)) != card(session(running: true, worked: 11)),
               "The running card did not change as its clock moved", &problems)
        return problems
    }
}
