import AppKit
import Foundation

/// The main window's name follows its workspace, the chrome gives up the
/// traffic lights' room in full screen, and the chrome's toolbar-only actions
/// (a day's calendar, the day before and after) have commands behind them.
enum WindowChromeNavChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The window is titled for its workspace, with the date as subtitle where the page shows one",
         windowTitleFollowsWorkspace),
        ("The chrome gives up the traffic lights' room in full screen and takes it back on leaving",
         fullScreenClearance),
        ("Previous Day and Next Day stay between the first recorded day and today, across a daylight-saving day",
         dayStepRange),
        ("Previous Day, Next Day and Go to Date open History on the day, from the story or from History",
         dayCommandsRoute),
    ]

    private static func windowTitleFollowsWorkspace() -> [String] {
        var problems: [String] = []
        let calendar = SelfTest.gregorian
        let now = SelfTest.base
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        func title(_ workspace: MainReadingWorkspace, story: Date,
                   history: Date?) -> MainWindowChrome.WindowTitle {
            MainWindowChrome.windowTitle(workspace: workspace, storyDay: story, historyDay: history,
                                         now: now, calendar: calendar)
        }
        func date(_ day: Date) -> String { DateFormats.fullDay(day, now: now, calendar: calendar) }

        let today = title(.story, story: now, history: nil)
        expect(today.title == "Today" && today.subtitle == date(now),
               "the story on today's date is Today with that date, got \(today)", &problems)
        let past = title(.story, story: yesterday, history: nil)
        expect(past.title == "Story" && past.subtitle == date(yesterday),
               "a story on another date keeps the workspace's name, got \(past)", &problems)
        let list = title(.history, story: now, history: nil)
        expect(list.title == "History" && list.subtitle.isEmpty,
               "History with no day open is History with no subtitle, got \(list)", &problems)
        let open = title(.history, story: now, history: yesterday)
        expect(open.title == "History" && open.subtitle == date(yesterday) && open.subtitle != today.subtitle,
               "History with a day open dates itself by that day, got \(open)", &problems)
        for shown in [today, past, list, open] {
            expect(!(shown.title + shown.subtitle).contains("\u{2014}"),
                   "a window title without an em dash, got \(shown)", &problems)
        }
        return problems
    }

    private static func fullScreenClearance() -> [String] {
        var problems: [String] = []
        expect(MainWindowChrome.clearance(fullScreen: false) == MainWindowChrome.trafficLightClearance,
               "windowed, the chrome keeps the traffic lights' room", &problems)
        expect(MainWindowChrome.clearance(fullScreen: true) == 0,
               "in full screen the traffic lights are gone, so their room is too", &problems)

        // The anchor that feeds it, driven by the notifications AppKit posts.
        MainActor.assumeIsolated {
            final class Seen { var values: [Bool] = [] }
            let seen = Seen()
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 200, height: 100),
                                  styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let other = NSWindow(contentRect: window.frame, styleMask: [.borderless],
                                 backing: .buffered, defer: true)
            other.isReleasedWhenClosed = false
            let anchor = FullScreenAnchor()
            anchor.onChange = { seen.values.append($0) }
            window.contentView?.addSubview(anchor)
            func settle() { for _ in 0..<2 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) } }
            func post(_ name: Notification.Name, from source: NSWindow) {
                NotificationCenter.default.post(name: name, object: source)
                settle()
            }

            settle()
            expect(seen.values == [false], "a windowed window reports not full screen, got \(seen.values)", &problems)
            post(NSWindow.didEnterFullScreenNotification, from: other)
            expect(seen.values == [false], "another window entering full screen was heard, got \(seen.values)",
                   &problems)
            post(NSWindow.didEnterFullScreenNotification, from: window)
            expect(seen.values.last == true, "entering full screen was not reported, got \(seen.values)", &problems)
            post(NSWindow.willExitFullScreenNotification, from: window)
            expect(seen.values.last == false, "leaving full screen was not reported, got \(seen.values)", &problems)
        }
        return problems
    }

    private static func dayStepRange() -> [String] {
        var problems: [String] = []
        let calendar = SelfTest.gregorian
        let today = calendar.startOfDay(for: SelfTest.base)
        func day(_ offset: Int) -> Date {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: today)!)
        }
        func step(_ from: Int, _ delta: Int, earliest: Date?) -> Date? {
            HistoryDayStep.target(from: day(from), by: delta, earliest: earliest, today: today, calendar: calendar)
        }
        let first = day(-5)
        expect(step(0, -1, earliest: first) == day(-1), "Previous Day from today is yesterday", &problems)
        expect(step(-1, 1, earliest: first) == day(0), "Next Day from yesterday is today", &problems)
        expect(step(0, 1, earliest: first) == nil, "Next Day from today has no day to open", &problems)
        expect(step(-4, -1, earliest: first) == first, "Previous Day reaches the first recorded day", &problems)
        expect(step(-5, -1, earliest: first) == nil, "Previous Day from the first recorded day has none", &problems)
        expect(step(0, -1, earliest: nil) == nil && step(0, 1, earliest: nil) == nil,
               "with nothing recorded neither command has a day", &problems)
        expect(HistoryDayStep.target(from: SelfTest.base, by: -1, earliest: first, today: today,
                                     calendar: calendar) == day(-1),
               "a moment in the day is read as its day", &problems)

        // Sydney's clocks went forward on 1 October 2023, a day of 23 hours;
        // stepping back by 24 hours from the 2nd would land on 30 September.
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
        func sydneyDay(_ month: Int, _ dayOfMonth: Int) -> Date {
            sydney.date(from: DateComponents(year: 2023, month: month, day: dayOfMonth))!
        }
        let second = sydneyDay(10, 2)
        let back = HistoryDayStep.target(from: second, by: -1, earliest: sydneyDay(9, 1), today: second,
                                         calendar: sydney)
        expect(back == sydneyDay(10, 1), "the day before 2 October 2023 in Sydney is 1 October, got \(String(describing: back))",
               &problems)
        let forward = HistoryDayStep.target(from: sydneyDay(9, 30), by: 1, earliest: sydneyDay(9, 1),
                                            today: second, calendar: sydney)
        expect(forward == sydneyDay(10, 1), "the day after 30 September 2023 in Sydney is 1 October, got \(String(describing: forward))",
               &problems)
        return problems
    }

    private static func dayCommandsRoute() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            let calendar = SessionStore.historyCalendar
            let today = calendar.startOfDay(for: store.now())
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let navigation = MainWindowModel(store: store)

            expect(navigation.historyDayTarget(by: 1) == nil, "Next Day is off on today's story", &problems)
            expect(navigation.historyDayTarget(by: -1) == yesterday,
                   "Previous Day on today's story is yesterday, got \(String(describing: navigation.historyDayTarget(by: -1)))",
                   &problems)
            navigation.stepHistoryDay(by: 1)
            expect(navigation.workspace == .story, "a Next Day with nowhere to go moved the window", &problems)

            navigation.stepHistoryDay(by: -1)
            expect(navigation.workspace == .history && navigation.reviewSelectedDate == yesterday,
                   "Previous Day from the story did not open History on yesterday, got "
                   + "\(navigation.workspace) \(String(describing: navigation.reviewSelectedDate))", &problems)
            expect(navigation.historyDayTarget(by: 1) == today, "Next Day from yesterday is today", &problems)
            navigation.stepHistoryDay(by: 1)
            expect(navigation.reviewSelectedDate == today,
                   "Next Day did not open today, got \(String(describing: navigation.reviewSelectedDate))", &problems)

            navigation.returnToStory()
            expect(navigation.historyDayTarget(by: -1) == yesterday,
                   "from the story the step starts at today, whatever History has open", &problems)

            let asked = navigation.historyCalendarRequest
            navigation.goToDate()
            expect(navigation.workspace == .history && navigation.historyCalendarRequest == asked &+ 1,
                   "Go to Date did not show History and ask for its calendar", &problems)
            expect(MainWindowModel().historyDayTarget(by: -1) == nil,
                   "a window with no store offered a day to step to", &problems)
            return problems
        }
    }
}
