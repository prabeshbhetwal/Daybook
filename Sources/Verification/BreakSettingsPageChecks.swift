import Foundation

/// The Breaks page in Settings: it is its own page beside Away, every row on
/// it is backed by a setting and found by search, and the dates the rows
/// write (today, this week, the working hours) are worked out in the model,
/// from an explicit clock and calendar, never in a view.
enum BreakSettingsPageChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Breaks and Away are separate pages", pagesAreSplit),
        ("Every Breaks row is backed by a setting and found by search", breakRowsResolve),
        ("An override set in Settings covers today, this week or this month", overridesAnchorToToday),
        ("Working hours round-trip through the time pickers", workingHoursRoundTrip),
        ("Custom numbers are clamped when written", customWritesClamped),
        ("The weekday plan lists days from the calendar's first weekday", weekdayPlanFollowsTheCalendar),
    ]

    private static func calendar(_ zone: String = "Europe/Berlin", firstWeekday: Int = 2) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        cal.locale = Locale(identifier: "en_AU")
        cal.firstWeekday = firstWeekday
        return cal
    }

    private static func date(_ day: Int, _ hour: Int = 10, _ minute: Int = 0, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// A model over its own in-memory preferences, with the clock and calendar
    /// handed in; the preferences are removed after `body`.
    private static func withModel(clock: TestClock, calendar: @escaping () -> Calendar,
                                  _ body: (SettingsModel, PersistenceStore, inout [String]) -> Void) -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-breakpage-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        let store = PersistenceStore(defaults: defaults)
        let model = SettingsModel(store: store, isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in },
                                  now: { clock.value }, calendar: calendar)
        body(model, store, &problems)
        return problems
    }

    private static func pagesAreSplit() -> [String] {
        var problems: [String] = []
        expect(SettingsPage.breaks.sections == [.breaks] && SettingsPage.away.sections == [.away],
               "Breaks and Away each own one section, got \(SettingsPage.breaks.sections) and \(SettingsPage.away.sections)",
               &problems)
        expect(SettingsPage.breaks.title == "Breaks" && SettingsPage.breaks.symbol == "cup.and.saucer"
               && SettingsPage.away.title == "Away" && SettingsPage.away.symbol == "moon.zzz",
               "the pages are named Breaks and Away with their own symbols", &problems)
        expect(SettingsPage(section: .breaks) == .breaks && SettingsPage(section: .away) == .away,
               "each section opens its own page", &problems)
        expect(!SettingsPage.allCases.map(\.title).contains("Away & Breaks"),
               "no page is still called Away & Breaks", &problems)
        expect(Set(SettingsSection.breaks.mutableControlKeys).isDisjoint(with: SettingsSection.away.mutableControlKeys),
               "no control sits on both pages", &problems)
        expect(SettingsSection.away.controlLabels.contains("Pause after no input for")
               && !SettingsSection.away.controlLabels.contains("Remind me to take breaks"),
               "Away keeps the absence rows and lost the break rows", &problems)
        expect(SettingsSection.breaks.controlLabels.contains("Remind me to take breaks")
               && !SettingsSection.breaks.controlLabels.contains("Pause after no input for"),
               "Breaks has the break rows and none of the absence rows", &problems)
        return problems
    }

    private static func breakRowsResolve() -> [String] {
        var problems: [String] = []
        let listed = SettingsSection.allCases.flatMap(\.mutableControlKeys)
        expect(Set(listed) == Set(SettingsControlKey.allCases) && listed.count == Set(listed).count,
               "every setting appears in exactly one section", &problems)
        let keys = SettingsSection.breaks.mutableControlKeys
        expect(keys == [.reminders, .breakRhythm, .breakWeekdays, .breakOverrides, .workingHours, .breakEyes,
                        .breakGuard, .breakOverSound, .menuBarShowsBreakCountdown],
               "the Breaks rows run top to bottom as designed, got \(keys)", &problems)
        expect(Set(keys.map(\.modelKeyPath)).count == keys.count,
               "each Breaks row names its own SettingsModel property", &problems)
        expect(SettingsSection.matching("Pomodoro") == [.breaks],
               "Pomodoro finds only Breaks, got \(SettingsSection.matching("Pomodoro"))", &problems)
        expect(SettingsSection.matching("Working hours").contains(.breaks),
               "Working hours finds Breaks", &problems)
        expect(SettingsSection.matching("End session after") == [.away],
               "End session after finds only Away, got \(SettingsSection.matching("End session after"))", &problems)
        for term in ["Eyes", "Long-stretch guard", "Weekday plan", "Overrides"] {
            expect(SettingsSection.matching(term).contains(.breaks), "\(term) finds Breaks", &problems)
        }
        return problems
    }

    private static func overridesAnchorToToday() -> [String] {
        let cal = calendar()
        let clock = TestClock(date(21, in: cal))
        return withModel(clock: clock, calendar: { cal }) { model, store, problems in
            func stored(_ kind: BreakOverrideKind) -> BreakOverride? {
                store.breakSchedule.overrides.first { $0.kind == kind }
            }
            func day(_ d: Int) -> CalendarDay { CalendarDay(date(d, in: cal), calendar: cal) }

            model.setBreakOverride(.today, plan: .off)
            expect(stored(.today)?.first == day(21) && stored(.today)?.last == day(21) && stored(.today)?.plan == .off,
                   "Today covers Wednesday 21 Oct only, got \(String(describing: stored(.today)))", &problems)
            model.setBreakOverride(.week, plan: .preset(.flow))
            expect(stored(.week)?.first == day(19) && stored(.week)?.last == day(25),
                   "This week runs Monday 19 to Sunday 25 Oct, got \(String(describing: stored(.week)))", &problems)
            model.setBreakOverride(.month, plan: .preset(.pomodoro))
            expect(stored(.month)?.first == day(1) && stored(.month)?.last == day(31),
                   "This month is all of October, got \(String(describing: stored(.month)))", &problems)
            expect(model.breakOverridePlan(.today) == .off && model.breakOverridePlan(.week) == .preset(.flow)
                   && model.breakOverridePlan(.range) == .usual,
                   "the rows read back what was set, and Dates is the weekday plan", &problems)

            clock.value = date(22, in: cal)
            expect(model.breakOverridePlan(.today) == .usual,
                   "yesterday's Today no longer shows, got \(model.breakOverridePlan(.today))", &problems)
            expect(model.breakOverridePlan(.week) == .preset(.flow),
                   "the week still shows the next day, got \(model.breakOverridePlan(.week))", &problems)

            model.setBreakOverride(.range, plan: .preset(.deepWork), from: date(24, in: cal), to: date(22, in: cal))
            expect(stored(.range)?.first == day(22) && stored(.range)?.last == day(24),
                   "Dates run either way round, got \(String(describing: stored(.range)))", &problems)
            expect(cal.isDate(model.breakRangeFrom, inSameDayAs: date(22, in: cal))
                   && cal.isDate(model.breakRangeTo, inSameDayAs: date(24, in: cal)),
                   "From and To read back the stored days", &problems)
            clock.value = date(23, in: cal)
            expect(model.breakOverridePlan(.range) == .preset(.deepWork),
                   "a range shows through its days", &problems)
            clock.value = date(20, in: cal)
            expect(model.breakOverridePlan(.range) == .preset(.deepWork),
                   "a range not yet begun still shows, so it can be seen and changed", &problems)
            clock.value = date(25, in: cal)
            expect(model.breakOverridePlan(.range) == .usual
                   && cal.isDate(model.breakRangeFrom, inSameDayAs: date(25, in: cal)),
                   "a range that has ended shows the weekday plan and offers today", &problems)

            clock.value = date(21, in: cal)
            model.setBreakOverride(.month, plan: .usual)
            expect(stored(.month) == nil && stored(.week) != nil,
                   "the weekday plan removes only that kind's override", &problems)
        }
    }

    private static func workingHoursRoundTrip() -> [String] {
        var problems: [String] = []
        for zone in ["Europe/Berlin", "Pacific/Kiritimati"] {
            let cal = calendar(zone)
            let now = date(21, 10, 0, in: cal)
            problems += withModel(clock: TestClock(now), calendar: { cal }) { model, store, problems in
                expect(!model.workingHoursEnabled, "\(zone): working hours start off", &problems)
                model.workingHoursEnabled = true
                expect(store.breakSchedule.workingHours == WorkingHours(fromMinute: 480, toMinute: 1_080),
                       "\(zone): turning them on gives 08:00 to 18:00, got \(String(describing: store.breakSchedule.workingHours))",
                       &problems)
                model.workingHoursFrom = date(21, 7, 30, in: cal)
                model.workingHoursTo = date(21, 19, 15, in: cal)
                expect(store.breakSchedule.workingHours == WorkingHours(fromMinute: 450, toMinute: 1_155),
                       "\(zone): 07:30 and 19:15 are 450 and 1155, got \(String(describing: store.breakSchedule.workingHours))",
                       &problems)
                let from = cal.dateComponents([.hour, .minute], from: model.workingHoursFrom)
                let to = cal.dateComponents([.hour, .minute], from: model.workingHoursTo)
                expect(from.hour == 7 && from.minute == 30 && to.hour == 19 && to.minute == 15
                       && cal.isDate(model.workingHoursFrom, inSameDayAs: now),
                       "\(zone): the pickers read the minutes back as today's times", &problems)
                model.workingHoursEnabled = false
                expect(store.breakSchedule.workingHours == nil && !model.workingHoursEnabled,
                       "\(zone): turning them off clears the window", &problems)
            }
        }
        return problems
    }

    private static func customWritesClamped() -> [String] {
        let cal = calendar()
        return withModel(clock: TestClock(date(21, in: cal)), calendar: { cal }) { model, store, problems in
            model.customRhythm = CustomRhythm(workMinutes: 500, breakMinutes: 0)
            expect(store.breakSchedule.custom.workMinutes == 180 && store.breakSchedule.custom.breakMinutes == 1,
                   "500 and 0 are stored as 180 and 1, got \(store.breakSchedule.custom)", &problems)
            model.customRhythm = CustomRhythm(workMinutes: 50, breakMinutes: 20, longEvery: 20, longMinutes: 1)
            expect(store.breakSchedule.custom == CustomRhythm(workMinutes: 50, breakMinutes: 20, longEvery: 8,
                                                              longMinutes: 20),
                   "long every is at most 8 and the long break at least the break, got \(store.breakSchedule.custom)",
                   &problems)
            expect(model.customRhythm == store.breakSchedule.custom, "the model reads what was stored", &problems)
        }
    }

    private static func weekdayPlanFollowsTheCalendar() -> [String] {
        var problems: [String] = []
        let monday = calendar(firstWeekday: 2), sunday = calendar(firstWeekday: 1)
        problems += withModel(clock: TestClock(date(21, in: monday)), calendar: { monday }) { model, store, problems in
            expect(model.weekdayOrder == [1, 2, 3, 4, 5, 6, 0],
                   "weeks from Monday list Monday first, got \(model.weekdayOrder)", &problems)
            expect(model.weekdayName(0) == "Sunday" && model.weekdayName(3) == "Wednesday",
                   "index 0 is Sunday and 3 is Wednesday, got \(model.weekdayName(0)) and \(model.weekdayName(3))",
                   &problems)
            model.breakWeekdayPlans[0] = .off
            model.breakWeekdayPlans[3] = .preset(.deepWork)
            expect(store.breakSchedule.weekdays[0] == .off && store.breakSchedule.weekdays[3] == .preset(.deepWork)
                   && store.breakSchedule.weekdays[1] == .usual,
                   "a plan lands on its Sunday-first slot, got \(store.breakSchedule.weekdays)", &problems)
        }
        problems += withModel(clock: TestClock(date(21, in: sunday)), calendar: { sunday }) { model, _, problems in
            expect(model.weekdayOrder == [0, 1, 2, 3, 4, 5, 6],
                   "weeks from Sunday list Sunday first, got \(model.weekdayOrder)", &problems)
        }
        return problems
    }
}
