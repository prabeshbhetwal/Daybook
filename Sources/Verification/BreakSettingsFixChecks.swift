import Foundation

/// Fix round 1 of the Breaks page: a rhythm changed mid-run reminds on its
/// own schedule at once, a damaged Custom setting cannot give Settings a range
/// that does not exist, the rows follow the clock when it jumps, the Dates
/// setters keep From before To, and the notes read right.
enum BreakSettingsFixChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A new rhythm reminds on its own schedule straight away", rhythmSwitchRemindsAtOnce),
        ("A notice raised under another rhythm does not hold back the new one", noticeUnderAnotherRhythm),
        ("A damaged Custom setting reads back inside its ranges", customReadsClamped),
        ("A new time zone or day republishes the break rows", clockChangesRepublish),
        ("Moving From past To takes To along, and the reverse", rangeSettersFollow),
        ("The Long break and Overrides notes read right", notesReadRight),
    ]

    private static func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        cal.locale = Locale(identifier: "en_AU")
        cal.firstWeekday = 2
        return cal
    }

    private static func date(_ day: Int, _ hour: Int = 10, _ minute: Int = 0, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    /// A model over its own in-memory preferences, removed after `body`.
    private static func withModel(clock: TestClock, calendar: @escaping () -> Calendar,
                                  _ body: (SettingsModel, PersistenceStore, inout [String]) -> Void) -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-breakfix-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        let store = PersistenceStore(defaults: defaults)
        let model = SettingsModel(store: store, isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in },
                                  now: { clock.value }, calendar: calendar)
        body(model, store, &problems)
        return problems
    }

    // MARK: - The rhythm changed mid-run

    /// Main prompts shown after the rhythm is switched mid-run, as minutes of
    /// work. Eyes and the guard are off so the last thing said is the main
    /// prompt: an Eyes glance in between would overwrite it and hide the bug.
    @MainActor
    private static func promptsAfterSwitch(from: BreakPreset, promptedAt: Double, switchAt: Double,
                                           to: BreakPreset, until: Double) -> [Double]? {
        guard let f = BreakStoreChecks.make() else { return nil }
        defer { f.close() }
        let model = SettingsModel(store: f.persistence, isTrackingEnabled: true,
                                  onChange: { f.store.refresh() }, onTrackingChanged: { _ in })
        var shown: [Double] = []
        f.store.onBreakDue = { prompt in
            if prompt.tier == .cognitive { shown.append(f.clock.value.timeIntervalSince(SelfTest.base) / 60) }
            return true
        }
        model.breakEyes = false
        model.breakGuardEnabled = false
        model.breakRhythm = from
        f.work(0, promptedAt)
        f.go(toMinute: promptedAt)
        f.store.refresh()
        f.work(promptedAt, switchAt)
        f.go(toMinute: switchAt)
        shown.removeAll()
        model.breakRhythm = to
        var minute = switchAt
        while minute < until {
            minute += 1
            f.work(minute - 1, minute)
            f.go(toMinute: minute)
            f.store.refresh()
        }
        return shown
    }

    private static func rhythmSwitchRemindsAtOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let cases: [(from: BreakPreset, promptedAt: Double, switchAt: Double, to: BreakPreset, due: Double)] = [
                (.steady, 52, 55, .deepWork, 90),
                (.pomodoro, 27, 30, .steady, 50),
                (.pomodoro, 27, 30, .deepWork, 90),
            ]
            for item in cases {
                let label = "\(item.from.title) at \(Int(item.promptedAt)), \(item.to.title) from \(Int(item.switchAt))"
                guard let shown = promptsAfterSwitch(from: item.from, promptedAt: item.promptedAt,
                                                     switchAt: item.switchAt, to: item.to, until: item.due + 5) else {
                    return ["could not create isolated preferences"]
                }
                expect(shown.first == item.due,
                       "\(label): the new rhythm reminds at \(Int(item.due)), got \(shown)", &problems)
            }
            return problems
        }
    }

    private static func noticeUnderAnotherRhythm() -> [String] {
        var problems: [String] = []
        let deep = BreakPlan(rhythm: BreakRhythm(.deepWork), eyes: false, guardLength: nil, override: nil)
        func prompt(_ notice: BreakNotice?) -> BreakPrompt? {
            let run = [AppUsageSession(bundleID: "com.a", appName: "Alpha", start: at(0), end: at(90))]
            return BreakReminder.evaluate(run, now: at(90), last: notice, plan: deep, clock: BreakClock()).prompt
        }
        expect(prompt(BreakNotice(tier: .cognitive, at: at(52), work: 3_000)) != nil,
               "a notice raised at Steady's 50 does not hold back Deep work's 90", &problems)
        expect(prompt(BreakNotice(tier: .cognitive, at: at(52))) == nil,
               "a notice with no length (an older build's) is taken as the rhythm's own, as before", &problems)
        expect(prompt(BreakNotice(tier: .cognitive, at: at(52), work: 5_400)) == nil,
               "a notice raised under Deep work still holds back its own repeat", &problems)
        expect(prompt(BreakNotice(tier: .cognitive, at: at(90).addingTimeInterval(-30), work: 3_000)) == nil,
               "the minimum spacing holds whatever rhythm said it", &problems)

        // The length travels with the notice through preferences, and a notice
        // written without one reads as unknown.
        let name = "fc-selftest-breakfix-notice-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: name) else { return problems + ["no isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        let store = PersistenceStore(defaults: defaults)
        store.lastBreakNotice = BreakNotice(tier: .cognitive, at: at(52), work: 3_000)
        expect(PersistenceStore(defaults: defaults).lastBreakNotice
               == BreakNotice(tier: .cognitive, at: at(52), work: 3_000), "the length is kept", &problems)
        store.lastBreakNotice = BreakNotice(tier: .micro, at: at(60))
        expect(PersistenceStore(defaults: defaults).lastBreakNotice?.work == nil,
               "a notice without one does not inherit the last one's", &problems)
        defaults.removeObject(forKey: "fc.lastBreakWork")
        defaults.set(at(52).timeIntervalSince1970, forKey: "fc.lastBreakNotice")
        expect(store.lastBreakNotice?.work == nil, "a notice from an older build reads as unknown", &problems)
        store.lastBreakNotice = BreakNotice(tier: .cognitive, at: at(52), work: 3_000)
        store.removeAll()
        expect(defaults.object(forKey: "fc.lastBreakWork") == nil, "erasing everything clears it", &problems)
        return problems
    }

    // MARK: - Damaged Custom, the clock, the range

    private static func customReadsClamped() -> [String] {
        let cal = calendar()
        return withModel(clock: TestClock(date(21, in: cal)), calendar: { cal }) { model, store, problems in
            var schedule = BreakSchedule()
            schedule.custom = CustomRhythm(workMinutes: 999, breakMinutes: 100, longEvery: 12, longMinutes: 1)
            store.breakSchedule = schedule
            let custom = model.customRhythm
            expect(custom == CustomRhythm(workMinutes: 180, breakMinutes: 30, longEvery: 8, longMinutes: 30),
                   "999, 100, 12 and 1 read as 180, 30, 8 and 30, got \(custom)", &problems)
            // The Long break length row spans max(5, break)...60: never upside down.
            expect(max(5, custom.breakMinutes) <= 60 && (1...30).contains(custom.breakMinutes)
                   && (10...180).contains(custom.workMinutes),
                   "the rows' ranges can be built from what the model reads", &problems)
        }
    }

    private static func clockChangesRepublish() -> [String] {
        let berlin = calendar(), kiritimati = calendar("Pacific/Kiritimati")
        var current = berlin
        return withModel(clock: TestClock(date(21, in: berlin)), calendar: { current }) { model, store, problems in
            var published = 0
            let token = model.objectWillChange.sink { published += 1 }
            defer { token.cancel() }
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
            expect(published == 1, "a new time zone republishes once, got \(published)", &problems)
            NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
            expect(published == 2, "a new day republishes once more, got \(published)", &problems)

            // 07:30 in Berlin is stored as the minute 450; under another zone the
            // picker shows 07:30 there, and its calendar is that zone's.
            model.workingHoursEnabled = true
            model.workingHoursFrom = date(21, 7, 30, in: berlin)
            current = kiritimati
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
            let shown = kiritimati.dateComponents([.hour, .minute], from: model.workingHoursFrom)
            expect(store.breakSchedule.workingHours?.fromMinute == 450 && shown.hour == 7 && shown.minute == 30
                   && model.pickerCalendar.timeZone == kiritimati.timeZone,
                   "the stored minute is unchanged and shown in the new zone, got \(shown)", &problems)
        }
    }

    private static func rangeSettersFollow() -> [String] {
        let cal = calendar()
        return withModel(clock: TestClock(date(21, in: cal)), calendar: { cal }) { model, store, problems in
            func day(_ d: Int) -> CalendarDay { CalendarDay(date(d, in: cal), calendar: cal) }
            func range() -> (CalendarDay, CalendarDay)? {
                store.breakSchedule.overrides.first { $0.kind == .range }.map { ($0.first, $0.last) }
            }
            model.setBreakOverride(.range, plan: .preset(.deepWork), from: date(22, in: cal), to: date(24, in: cal))
            model.breakRangeFrom = date(26, in: cal)
            expect(range()?.0 == day(26) && range()?.1 == day(26),
                   "From past To drags To along, got \(String(describing: range()))", &problems)
            model.breakRangeTo = date(23, in: cal)
            expect(range()?.0 == day(23) && range()?.1 == day(23),
                   "To before From drags From back, got \(String(describing: range()))", &problems)
            model.breakRangeTo = date(28, in: cal)
            model.breakRangeFrom = date(25, in: cal)
            expect(range()?.0 == day(25) && range()?.1 == day(28),
                   "inside the range each end moves alone, got \(String(describing: range()))", &problems)
            expect(model.breakOverridePlan(.range) == .preset(.deepWork)
                   && cal.isDate(model.breakRangeFrom, inSameDayAs: date(25, in: cal))
                   && cal.isDate(model.breakRangeTo, inSameDayAs: date(28, in: cal)),
                   "the plan is kept and the pickers read the stored days", &problems)
        }
    }

    private static func notesReadRight() -> [String] {
        var problems: [String] = []
        for (every, text) in [(2, "Every 2nd break is the long one."), (3, "Every 3rd break is the long one."),
                              (4, "Every 4th break is the long one."), (8, "Every 8th break is the long one.")] {
            expect(SettingsGroups.longBreakDetail(every: every) == text,
                   "\(every) reads \"\(text)\", got \"\(SettingsGroups.longBreakDetail(every: every))\"", &problems)
        }
        expect(SettingsGroups.longBreakDetail(every: nil) == "Off, every break is the same length.",
               "no long break says so", &problems)
        expect(SettingsGroups.overridesFootnote.hasSuffix("Where more than one covers a day, the one covering "
                                                          + "the fewest days wins."),
               "the footnote names what wins, got \"\(SettingsGroups.overridesFootnote)\"", &problems)
        return problems
    }
}
