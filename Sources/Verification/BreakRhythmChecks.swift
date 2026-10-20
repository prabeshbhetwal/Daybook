import Foundation

/// The break rhythms: presets, Custom, Flow's suggestion, the weekday plan,
/// overrides and working hours. Every date comes from an explicit calendar
/// handed to the code under test, so the checks hold in any process zone.
enum BreakRhythmChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Each preset has the spec's numbers and evidence note", presetsHaveTheirNumbers),
        ("Custom numbers stay inside their ranges", customIsClamped),
        ("Flow suggests a fifth of the stretch, between 5 and 20 minutes", flowSuggestsAFifth),
        ("The weekday plan picks each day's rhythm", weekdayPlanPicksTheDay),
        ("The narrowest override covering a day wins", narrowestOverrideWins),
        ("Working hours hold overnight and in any zone", workingHoursHold),
        ("Working hours hold on a daylight-saving day", workingHoursOnDaylightSavingDay),
        ("A schedule from another build still reads", scheduleDecodesLeniently),
    ]

    private static func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        cal.firstWeekday = 2
        return cal
    }

    /// A moment in October 2026 (Wednesday the 21st is a Wednesday).
    private static func day(_ d: Int, _ hour: Int = 10, _ minute: Int = 0,
                            in cal: Calendar, month: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour, minute: minute))!
    }

    private static func presetsHaveTheirNumbers() -> [String] {
        var problems: [String] = []
        let steady = BreakRhythm(.steady)
        expect(steady.work == 3_000 && steady.breakLength == 300 && steady.longEvery == nil
               && steady.longLength == nil, "Steady is 50 and 5, no long break", &problems)
        let pomodoro = BreakRhythm(.pomodoro)
        expect(pomodoro.work == 1_500 && pomodoro.breakLength == 300 && pomodoro.longEvery == 4
               && pomodoro.longLength == 900, "Pomodoro is 25 and 5, 15 after 4", &problems)
        let deep = BreakRhythm(.deepWork)
        expect(deep.work == 5_400 && deep.breakLength == 900 && deep.longEvery == nil,
               "Deep work is 90 and 15", &problems)
        let flow = BreakRhythm(.flow)
        expect(flow.work == nil && flow.breakLength == nil && flow.longEvery == nil,
               "Flow has no fixed numbers", &problems)
        let custom = BreakRhythm(.custom)
        expect(custom.work == 3_000 && custom.breakLength == 300 && custom.longEvery == nil,
               "Custom starts at 50 and 5", &problems)

        expect(BreakPreset.steady.evidenceNote
               == "Close to HSE and OSHA guidance: 5 to 10 minutes an hour.", "Steady note", &problems)
        expect(BreakPreset.pomodoro.evidenceNote
               == "A popular fixed cadence. Studies find it about as good as choosing your own breaks.",
               "Pomodoro note", &problems)
        expect(BreakPreset.deepWork.evidenceNote
               == "Longer blocks for focused work, with a proper reset.", "Deep work note", &problems)
        expect(BreakPreset.flow.evidenceNote
               == "You decide when to stop; Daybook suggests a break length.", "Flow note", &problems)
        expect(BreakPreset.custom.evidenceNote == nil, "Custom has no note", &problems)
        expect(BreakPreset.allCases.map(\.title) == ["Steady", "Pomodoro", "Deep work", "Flow", "Custom"],
               "titles", &problems)
        return problems
    }

    private static func customIsClamped() -> [String] {
        var problems: [String] = []
        let c = CustomRhythm(workMinutes: 5, breakMinutes: 45, longEvery: 12, longMinutes: 2).clamped()
        expect(c == CustomRhythm(workMinutes: 10, breakMinutes: 30, longEvery: 8, longMinutes: 30),
               "out-of-range values land on the nearest limit", &problems)
        let high = CustomRhythm(workMinutes: 500, breakMinutes: 0, longEvery: 2, longMinutes: 90).clamped()
        expect(high == CustomRhythm(workMinutes: 180, breakMinutes: 1, longEvery: 2, longMinutes: 60),
               "the other end of each range", &problems)
        expect(CustomRhythm(longEvery: 1).clamped().longEvery == 2
               && CustomRhythm().clamped().longEvery == nil, "longEvery is nil or 2 to 8", &problems)
        let long = BreakRhythm(.custom, custom: CustomRhythm(workMinutes: 40, breakMinutes: 8,
                                                             longEvery: 3, longMinutes: 20))
        expect(long.longLength == 1_200 && long.longEvery == 3 && long.work == 2_400
               && long.breakLength == 480, "Custom's numbers reach the rhythm", &problems)
        let wild = BreakRhythm(.custom, custom: CustomRhythm(workMinutes: 1, breakMinutes: 99))
        expect(wild.work == 600 && wild.breakLength == 1_800, "the rhythm clamps Custom too", &problems)
        return problems
    }

    private static func flowSuggestsAFifth() -> [String] {
        var problems: [String] = []
        expect(BreakRhythm.flowSuggestion(after: 1_800) == 360, "30 minutes suggests 6", &problems)
        expect(BreakRhythm.flowSuggestion(after: 600) == 300, "a short stretch still gets 5", &problems)
        expect(BreakRhythm.flowSuggestion(after: 9_000) == 1_200, "a long stretch stops at 20", &problems)
        expect(BreakRhythm.flowSuggestion(after: 3_600) == 720, "an hour suggests 12", &problems)
        expect(BreakRhythm.flowSuggestion(after: 0) == 300 && BreakRhythm.flowSuggestion(after: -50) == 300,
               "nothing worked suggests the shortest", &problems)
        return problems
    }

    private static func weekdayPlanPicksTheDay() -> [String] {
        var problems: [String] = []
        let cal = calendar()
        var s = BreakSchedule()
        s.rhythm = .deepWork
        s.weekdays[3] = .off
        s.weekdays[4] = .preset(.pomodoro)
        expect(s.preset(on: day(21, in: cal), calendar: cal).preset == nil,
               "Wednesday is No reminders", &problems)
        expect(s.preset(on: day(22, in: cal), calendar: cal).preset == .pomodoro,
               "Thursday is Pomodoro", &problems)
        expect(s.preset(on: day(23, in: cal), calendar: cal).preset == .deepWork,
               "usual follows the rhythm", &problems)
        expect(s.preset(on: day(22, in: cal), calendar: cal).override == nil,
               "a weekday plan is not an override", &problems)
        expect(BreakSchedule().preset(on: day(24, in: cal), calendar: cal).preset == .steady,
               "every day is Steady by default", &problems)
        // Sunday is index 0.
        var sunday = BreakSchedule()
        sunday.weekdays[0] = .off
        expect(sunday.preset(on: day(25, in: cal), calendar: cal).preset == nil
               && sunday.preset(on: day(26, in: cal), calendar: cal).preset == .steady,
               "Sunday is the first entry", &problems)
        return problems
    }

    private static func narrowestOverrideWins() -> [String] {
        var problems: [String] = []
        let cal = calendar()
        var s = BreakSchedule()
        s.setOverride(.month, plan: .preset(.pomodoro), covering: day(21, in: cal), calendar: cal)
        s.setOverride(.week, plan: .preset(.deepWork), covering: day(21, in: cal), calendar: cal)
        s.setOverride(.range, plan: .preset(.flow), covering: day(20, in: cal),
                      through: day(22, in: cal), calendar: cal)
        s.setOverride(.today, plan: .off, covering: day(21, in: cal), calendar: cal)
        func look(_ d: Int, month: Int = 10) -> (BreakPreset?, BreakOverrideKind?) {
            let r = s.preset(on: day(d, in: cal, month: month), calendar: cal)
            return (r.preset, r.override)
        }
        expect(look(21).0 == nil && look(21).1 == .today, "today beats everything", &problems)
        expect(look(22).0 == .flow && look(22).1 == .range, "a three-day range beats the week", &problems)
        expect(look(24).0 == .deepWork && look(24).1 == .week, "the week beats the month", &problems)
        expect(look(28).0 == .pomodoro && look(28).1 == .month, "the month covers the rest", &problems)
        expect(look(2, month: 11).1 == nil && s.override(on: day(2, in: cal, month: 11), calendar: cal) == nil,
               "next month has no override", &problems)

        var tie = BreakSchedule()
        tie.setOverride(.range, plan: .preset(.flow), covering: day(19, in: cal),
                        through: day(25, in: cal), calendar: cal)
        tie.setOverride(.week, plan: .preset(.deepWork), covering: day(23, in: cal), calendar: cal)
        expect(tie.override(on: day(23, in: cal), calendar: cal)?.kind == .week,
               "equal spans go to the earlier kind", &problems)

        var wide = BreakSchedule()
        wide.setOverride(.range, plan: .preset(.flow), covering: day(1, in: cal),
                         through: day(30, in: cal, month: 11), calendar: cal)
        wide.setOverride(.month, plan: .preset(.pomodoro), covering: day(28, in: cal), calendar: cal)
        expect(wide.override(on: day(28, in: cal), calendar: cal)?.kind == .month,
               "a 61-day range loses to the month", &problems)

        // Sao Paulo skipped midnight on 4 November 2018 and started that day
        // at 01:00: a range beginning there is still seven days when it runs
        // to the 10th, so it ties the week and the earlier kind wins.
        let paulo = calendar("America/Sao_Paulo")
        func paulistano(_ d: Int) -> Date {
            paulo.date(from: DateComponents(year: 2018, month: 11, day: d, hour: 12))!
        }
        var skipped = BreakSchedule()
        skipped.setOverride(.range, plan: .preset(.flow), covering: paulistano(4),
                            through: paulistano(10), calendar: paulo)
        skipped.setOverride(.week, plan: .preset(.deepWork), covering: paulistano(7), calendar: paulo)
        expect(skipped.override(on: paulistano(7), calendar: paulo)?.kind == .week,
               "a range that starts on a day without a midnight counts that day", &problems)

        s.setOverride(.week, plan: .usual, covering: day(21, in: cal), calendar: cal)
        expect(!s.overrides.contains { $0.kind == .week } && look(24).1 == .month,
               "usual removes the kind's override", &problems)
        s.setOverride(.month, plan: .preset(.steady), covering: day(21, in: cal), calendar: cal)
        expect(s.overrides.filter { $0.kind == .month }.count == 1, "one override per kind", &problems)

        var reversed = BreakSchedule()
        reversed.setOverride(.range, plan: .off, covering: day(22, in: cal),
                             through: day(20, in: cal), calendar: cal)
        let stored = reversed.overrides.first
        expect(stored?.first == CalendarDay(day(20, in: cal), calendar: cal)
               && stored?.last == CalendarDay(day(22, in: cal), calendar: cal),
               "a reversed range is stored in order", &problems)
        reversed.setOverride(.range, plan: .off, covering: day(22, in: cal), calendar: cal)
        expect(reversed.overrides.first?.first == reversed.overrides.first?.last,
               "a range with no end is one day", &problems)
        return problems
    }

    private static func workingHoursHold() -> [String] {
        var problems: [String] = []
        let daytime = WorkingHours(fromMinute: 480, toMinute: 1_080)
        let night = WorkingHours(fromMinute: 1_320, toMinute: 360)
        for zone in ["Europe/Berlin", "Pacific/Kiritimati", "America/Los_Angeles"] {
            let cal = calendar(zone)
            expect(daytime.contains(day(21, 10, in: cal), calendar: cal)
                   && !daytime.contains(day(21, 7, 59, in: cal), calendar: cal)
                   && daytime.contains(day(21, 8, in: cal), calendar: cal)
                   && !daytime.contains(day(21, 18, in: cal), calendar: cal),
                   "08:00 to 18:00 in \(zone)", &problems)
            expect(night.contains(day(21, 23, 30, in: cal), calendar: cal)
                   && night.contains(day(21, 5, 59, in: cal), calendar: cal)
                   && !night.contains(day(21, 6, in: cal), calendar: cal)
                   && !night.contains(day(21, 12, in: cal), calendar: cal),
                   "22:00 to 06:00 in \(zone)", &problems)
        }
        let cal = calendar()
        let always = WorkingHours(fromMinute: 600, toMinute: 600)
        expect(always.contains(day(21, 3, in: cal), calendar: cal)
               && always.contains(day(21, 10, in: cal), calendar: cal), "equal ends mean all day", &problems)
        return problems
    }

    private static func workingHoursOnDaylightSavingDay() -> [String] {
        var problems: [String] = []
        let cal = calendar()
        let hours = WorkingHours(fromMinute: 480, toMinute: 1_080)
        expect(hours.contains(day(25, 10, in: cal), calendar: cal), "10:00 is inside", &problems)
        let first = day(25, 2, 30, in: cal)
        expect(!hours.contains(first, calendar: cal) && !hours.contains(first.addingTimeInterval(3_600), calendar: cal),
               "02:30 is outside, either time it happens", &problems)
        expect(hours.contains(day(25, 18, in: cal).addingTimeInterval(-60), calendar: cal)
               && !hours.contains(day(25, 18, in: cal), calendar: cal), "the evening edge holds", &problems)

        var s = BreakSchedule()
        s.setOverride(.week, plan: .off, covering: day(21, in: cal), calendar: cal)
        expect(s.override(on: day(25, 12, in: cal), calendar: cal)?.kind == .week
               && s.override(on: day(25, 23, 59, in: cal), calendar: cal)?.kind == .week
               && s.override(on: day(26, 0, 1, in: cal), calendar: cal) == nil,
               "the week covers the 25-hour Sunday and stops at Monday", &problems)
        return problems
    }

    private static func scheduleDecodesLeniently() -> [String] {
        var problems: [String] = []
        let odd = #"{"rhythm":"siesta","weekdays":["usual","nap","off","usual","usual","usual","usual"]}"#
        let decoder = JSONDecoder()
        if let d = try? decoder.decode(BreakSchedule.self, from: Data(odd.utf8)) {
            expect(d.rhythm == .steady && d.weekdays[1] == .usual && d.weekdays[2] == .off
                   && d.overrides.isEmpty, "an unknown rhythm and plan read as the defaults", &problems)
        } else {
            problems.append("a schedule with unknown strings did not decode")
        }
        expect((try? decoder.decode(BreakSchedule.self, from: Data("{}".utf8))) == BreakSchedule(),
               "an empty object reads as the defaults", &problems)
        let short = #"{"weekdays":["off","off"]}"#
        expect((try? decoder.decode(BreakSchedule.self, from: Data(short.utf8)))?.weekdays
               == Array(repeating: .usual, count: 7), "a short weekdays array reads as the default", &problems)
        let future = #"{"overrides":[{"kind":"decade","first":{"year":2026,"month":1,"day":1},"last":{"year":2026,"month":1,"day":2},"plan":"off"}]}"#
        expect((try? decoder.decode(BreakSchedule.self, from: Data(future.utf8)))?.overrides.isEmpty == true,
               "an override of an unknown kind is dropped, not fatal", &problems)

        let cal = calendar()
        var full = BreakSchedule()
        full.rhythm = .custom
        full.custom = CustomRhythm(workMinutes: 40, breakMinutes: 8, longEvery: 3, longMinutes: 20)
        full.weekdays = [.off, .usual, .preset(.pomodoro), .preset(.flow), .usual, .preset(.custom), .off]
        full.setOverride(.week, plan: .preset(.deepWork), covering: day(21, in: cal), calendar: cal)
        full.setOverride(.range, plan: .off, covering: day(20, in: cal), through: day(22, in: cal), calendar: cal)
        full.workingHours = WorkingHours(fromMinute: 1_320, toMinute: 360)
        let again = (try? JSONEncoder().encode(full)).flatMap { try? decoder.decode(BreakSchedule.self, from: $0) }
        expect(again == full, "a schedule with every field set round-trips", &problems)

        let plans: [BreakDayPlan] = [.usual, .off, .preset(.deepWork)]
        let text = (try? JSONEncoder().encode(plans)).flatMap { String(data: $0, encoding: .utf8) }
        expect(text == #"["usual","off","deepWork"]"#, "a plan is coded as one string", &problems)
        return problems
    }
}
