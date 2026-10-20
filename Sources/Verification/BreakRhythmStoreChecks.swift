import Foundation

/// The store follows the rhythm in force on each break refresh: today's
/// weekday plan or override, Eyes, the guard and the working hours. It writes
/// the day's rhythm to the log whatever else the refresh finds, and Start break
/// begins at the length that rhythm suggests. Every date comes from the Berlin
/// calendar handed to the store, so the checks hold in any zone.
enum BreakRhythmStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The day's rhythm is logged even with reminders off or on a break", rhythmLoggedWhateverTheState),
        ("A settings change rewrites today's rhythm", settingsChangeRewritesToday),
        ("The plan follows midnight without a relaunch", planFollowsMidnight),
        ("A No reminders weekday has no main prompt, and Eyes and the guard still run", noRemindersWeekday),
        ("Today's override prompts at its own rhythm", todayOverridePrompts),
        ("Outside working hours nothing prompts, and the label says why", outsideWorkingHoursIsQuiet),
        ("Start break begins at the rhythm's length", startBreakUsesRhythmLength),
        ("A long Pomodoro prompt is logged as the long kind", longPromptLogged),
    ]

    // MARK: - Fixtures

    private static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// A moment in October 2026, Berlin time. The 21st is a Wednesday.
    private static func oct(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private static func minutes(_ count: Double) -> TimeInterval { count * 60 }

    /// A store working in Berlin whose clock stands at `moment`.
    @MainActor
    private static func make(at moment: Date) -> BreakStoreChecks.Fixture? {
        guard let f = BreakStoreChecks.make(calendar: berlin) else { return nil }
        f.clock.value = moment
        return f
    }

    /// The schedule as a settings change would leave it.
    @MainActor
    private static func save(_ f: BreakStoreChecks.Fixture, _ change: (inout BreakSchedule) -> Void) {
        var schedule = f.persistence.breakSchedule
        change(&schedule)
        f.persistence.breakSchedule = schedule
    }

    /// One unbroken stretch of use.
    @MainActor
    private static func use(_ f: BreakStoreChecks.Fixture, from start: Date, to end: Date) {
        f.usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha", start: start, end: end))
    }

    /// The prompts the store raises, which all reach the screen.
    @MainActor
    private static func collect(_ f: BreakStoreChecks.Fixture) -> BreakStoreChecks.Box<[BreakPrompt]> {
        let shown = BreakStoreChecks.Box<[BreakPrompt]>([])
        f.store.onBreakDue = { shown.value.append($0); return true }
        return shown
    }

    /// The preset the log holds for the latest day.
    @MainActor
    private static func preset(_ f: BreakStoreChecks.Fixture) -> String? {
        f.store.breakLog.days.last?.rhythm.preset
    }

    // MARK: - Checks

    private static func rhythmLoggedWhateverTheState() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let noon = oct(21, 12, 0)
            guard let off = make(at: noon), let rest = make(at: noon), let blind = make(at: noon),
                  let paused = make(at: noon) else { return ["could not create isolated preferences"] }
            defer { [off, rest, blind, paused].forEach { $0.close() } }

            off.persistence.remindersEnabled = false
            off.store.refresh()
            expect(off.store.breakLog.days.count == 1 && off.store.breakLog.days.last?.rhythm == BreakRhythmSnapshot.off,
                   "with reminders off the day is logged as off, got \(String(describing: off.store.breakLog.days))",
                   &problems)

            rest.store.startBreak(length: 300)
            rest.store.refresh()
            expect(rest.store.isOnBreak && preset(rest) == "steady",
                   "on a break the day is logged all the same, got \(String(describing: preset(rest)))", &problems)

            blind.store.usage = nil
            blind.store.refresh()
            expect(preset(blind) == "steady",
                   "with no usage to read the day is logged, got \(String(describing: preset(blind)))", &problems)

            paused.engine.start(workType: .meetings, intent: "Standup")
            paused.store.refresh()
            expect(paused.store.remindersPausedByCategory != nil && preset(paused) == "steady",
                   "and so is a day whose running category asked for quiet, got \(String(describing: preset(paused)))",
                   &problems)
            return problems
        }
    }

    private static func settingsChangeRewritesToday() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(at: oct(21, 10, 0)) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            f.store.refresh()
            expect(preset(f) == "steady", "Steady is logged first, got \(String(describing: preset(f)))", &problems)
            save(f) { $0.rhythm = .pomodoro }
            f.store.refresh()
            let days = f.store.breakLog.days
            expect(days.count == 1 && days.last?.rhythm.preset == "pomodoro" && days.last?.rhythm.workMinutes == 25,
                   "the same day now holds Pomodoro, got \(days.map { $0.rhythm.preset ?? "-" })", &problems)
            return problems
        }
    }

    private static func planFollowsMidnight() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            expect(berlin.component(.weekday, from: oct(21, 12, 0)) == 4, "the 21st is a Wednesday", &problems)
            guard let f = make(at: oct(21, 23, 50)) else { return problems + ["could not create isolated preferences"] }
            defer { f.close() }
            // Wednesday is a No reminders day; Thursday follows the usual rhythm.
            save(f) { $0.weekdays[3] = .off }
            let shown = collect(f)
            use(f, from: oct(21, 22, 55), to: oct(21, 23, 50))
            f.store.refresh()
            expect(!shown.value.contains { $0.tier == .cognitive },
                   "no main prompt on the No reminders day, got \(shown.value.map(\.tier))", &problems)

            // The same store, work going on across 00:00.
            f.clock.value = oct(22, 0, 0, 5)
            use(f, from: oct(21, 23, 50), to: oct(22, 0, 0, 5))
            f.store.refresh()
            expect(shown.value.last?.tier == .cognitive,
                   "Thursday's Steady prompts after midnight, got \(shown.value.map(\.tier))", &problems)
            let days = f.store.breakLog.days
            expect(days.map(\.day) == [berlin.startOfDay(for: oct(21, 12, 0)), berlin.startOfDay(for: oct(22, 12, 0))]
                   && days.map { $0.rhythm.preset } == ["off", "steady"],
                   "both days are logged, each with its own rhythm, got \(days.map { $0.rhythm.preset ?? "-" })",
                   &problems)
            return problems
        }
    }

    private static func noRemindersWeekday() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(at: oct(21, 10, 16)) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            save(f) { $0.weekdays[3] = .off }
            let shown = collect(f)
            use(f, from: oct(21, 9, 25), to: oct(21, 10, 16))
            f.store.refresh()
            expect(!shown.value.contains { $0.tier == .cognitive } && shown.value.last?.tier == .micro,
                   "51 minutes in: no main prompt, Eyes still speaks, got \(shown.value.map(\.tier))", &problems)

            f.clock.value = oct(21, 11, 0)
            use(f, from: oct(21, 10, 16), to: oct(21, 11, 0))
            f.store.refresh()
            expect(shown.value.last?.tier == .ultradian && shown.value.last?.kind == .stretchGuard,
                   "95 minutes in: the guard prompts, got \(shown.value.map(\.tier))", &problems)
            return problems
        }
    }

    private static func todayOverridePrompts() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let now = oct(21, 10, 30)
            guard let f = make(at: now) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            save(f) { $0.setOverride(.today, plan: .preset(.pomodoro), covering: now, calendar: berlin) }
            let shown = collect(f)
            use(f, from: now.addingTimeInterval(-minutes(26)), to: now)
            f.store.refresh()
            let main = shown.value.first { $0.tier == .cognitive }
            expect(main != nil && main?.breakLength == 300,
                   "26 minutes in, Pomodoro's 25 are up, got \(shown.value.map(\.tier))", &problems)
            let rhythm = f.store.breakLog.days.last?.rhythm
            expect(rhythm?.preset == "pomodoro" && rhythm?.override == "today",
                   "the log names the override, got \(String(describing: rhythm))", &problems)
            return problems
        }
    }

    private static func outsideWorkingHoursIsQuiet() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let evening = oct(21, 19, 0)
            guard let f = make(at: evening), let eyes = make(at: evening) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close(); eyes.close() }
            let hours = WorkingHours(fromMinute: 8 * 60, toMinute: 18 * 60)
            for store in [f, eyes] { save(store) { $0.workingHours = hours } }
            let shown = collect(f)
            let glances = collect(eyes)
            use(f, from: evening.addingTimeInterval(-minutes(60)), to: evening)
            f.store.refresh()
            expect(shown.value.isEmpty, "an hour in, after 18:00: nothing prompts, got \(shown.value.map(\.tier))",
                   &problems)
            expect(f.store.isOutsideWorkingHours && !f.store.isBreakDue && f.store.nextBreakTier == nil
                   && f.store.breakCountdown == 0 && f.store.breakLabel == "Outside working hours",
                   "and the label says why, got \(f.store.breakLabel)", &problems)
            expect(preset(f) == "steady", "the day's rhythm is still logged", &problems)
            use(eyes, from: evening.addingTimeInterval(-minutes(21)), to: evening)
            eyes.store.refresh()
            expect(glances.value.isEmpty, "Eyes is quiet too, got \(glances.value.map(\.tier))", &problems)

            // The clocks kept counting: the stretch begun at 07:00 is due as the window opens.
            f.clock.value = oct(22, 8, 0)
            use(f, from: oct(22, 7, 0), to: oct(22, 8, 0))
            f.store.refresh()
            expect(shown.value.last?.tier == .cognitive && !f.store.isOutsideWorkingHours,
                   "at 08:00 the break is due, got \(shown.value.map(\.tier))", &problems)
            return problems
        }
    }

    private static func startBreakUsesRhythmLength() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            /// What Start break plans after a refresh under `change`, in seconds.
            @MainActor func planned(_ change: (inout BreakSchedule) -> Void, work: Double = 0,
                                    minimumSession: TimeInterval? = nil, length: TimeInterval? = nil) -> TimeInterval? {
                guard let f = make(at: oct(21, 10, 0)) else { return nil }
                defer { f.close() }
                save(f, change)
                if let minimumSession { f.persistence.minimumRecordedSession = minimumSession }
                if work > 0 { use(f, from: oct(21, 10, 0).addingTimeInterval(-minutes(work)), to: oct(21, 10, 0)) }
                f.store.refresh()
                f.store.startBreak(length: length)
                return f.store.activeBreak?.plannedLength
            }
            let deep = planned({ $0.rhythm = .deepWork })
            expect(deep == 900, "Deep work begins 15 minutes, got \(String(describing: deep))", &problems)
            let flow = planned({ $0.rhythm = .flow }, work: 40)
            expect(flow == 480, "Flow after 40 minutes begins its 8, got \(String(describing: flow))", &problems)
            let quiet = planned({ $0.weekdays = Array(repeating: .off, count: 7) })
            expect(quiet == 300, "a No reminders day begins the standard 5, got \(String(describing: quiet))", &problems)
            let chosen = planned({ $0.rhythm = .deepWork }, length: 600)
            expect(chosen == 600, "a length chosen by hand wins, got \(String(describing: chosen))", &problems)
            // A break shorter than the shortest recorded session would be neither recorded nor credited.
            let tiny = planned({ $0.rhythm = .custom; $0.custom.breakMinutes = 1 }, minimumSession: 120)
            expect(tiny == 120, "a minute's break runs the shortest recorded session, got \(String(describing: tiny))",
                   &problems)
            return problems
        }
    }

    private static func longPromptLogged() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let start = oct(21, 9, 0)
            guard let f = make(at: start.addingTimeInterval(minutes(115))) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            save(f) { $0.rhythm = .pomodoro }
            // Three finished 25-minute blocks, each followed by 5 minutes off, and a fourth that is due.
            for block in 0..<4 {
                let from = start.addingTimeInterval(minutes(Double(block) * 30))
                use(f, from: from, to: from.addingTimeInterval(minutes(25)))
            }
            let shown = collect(f)
            f.store.refresh()
            expect(shown.value.last?.isLong == true && f.store.breakLog.prompts.last?.kind == .long,
                   "the fourth block's prompt is the long break, got \(String(describing: f.store.breakLog.prompts.last?.kind))",
                   &problems)
            expect(f.store.suggestedBreakLength == 900, "and Start break offers it, got \(f.store.suggestedBreakLength)",
                   &problems)
            return problems
        }
    }
}
