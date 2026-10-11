import Foundation
import FoundationModels

/// Ask Daybook v2 part 2: the daily goal, the streak and the awards. The
/// `goals` lookup reads the goal setting, today's goal credit (focus during
/// recorded app use, the Story goal tile's figure), the days a period met the
/// goal as the notes count them, the streak on the store's clock and the
/// awards the Awards sheet shows. In the shared fixture the goal is 4h and a
/// day counts toward the streak at 1h; Mon 13 Nov met the goal, Tue 14 Nov
/// did not, and Thu 5 Oct has 5h of focus but only 1h of goal credit.
enum AskGoalsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Goals read the goal, today's progress, the streak and awards", readsGoalStreakAwards),
        ("Days met are counted on goal credit against today's goal", daysMetOnGoalCredit),
        ("The streak follows the store's clock", streakFollowsStoreClock),
        ("A streak counts today once today has reached the minimum", streakCountsToday),
        ("Goals list the period and Awards", linksListPeriodAndAwards),
        ("Goals worded from figures: met today, one day, no award, 1 KB", wordedFromFigures),
        ("Goals for a period still to come say so", stillToCome),
        ("The catalogue holds eight lookups, the eighth goals, with an optional period", catalogueEntry),
    ]

    private static func awardLine(_ award: Award) -> String {
        award.detail.isEmpty ? award.title : "\(award.title) (\(award.detail))"
    }

    private static let streakLine = "Current streak: 5 days with at least 1h of focus, since Fri 10 Nov. Longest: 12 days."

    // MARK: - The facts

    private static func readsGoalStreakAwards() -> [String] {
        AskDataFixture.with { f, problems in
            // The lookup brings History's index up to date first, as opening the Awards sheet does,
            // and the awards are read from that index: read them after it.
            let got = f.store.askLookup(.goals(nil))
            let awards = f.store.awards
            let earned = awards.filter(\.isEarned).map(awardLine)
            let toEarn = awards.filter { !$0.isEarned }.map(awardLine)
            expect(!toEarn.isEmpty, "the fixture has no award still to earn", &problems)
            var last = earned.isEmpty ? "No awards earned yet." : "Awards earned: \(earned.joined(separator: "; "))."
            if !toEarn.isEmpty { last += " Still to earn: \(toEarn.joined(separator: "; "))." }
            let want = "Daily goal: 4h of focus during recorded app use. Today so far: 0m, 0%, not met yet.\n"
                + streakLine + "\n" + last
            expect(got == want, "goals read “\(got)”, not “\(want)”", &problems)
            expect(got.utf8.count <= AskFacts.maximumBytes, "goals are \(got.utf8.count) bytes", &problems)
        }
    }

    private static func daysMetOnGoalCredit() -> [String] {
        AskDataFixture.with { f, problems in
            let week = f.store.askLookup(.goals(.thisWeek))
            expect(week.contains("This week (13 Nov \u{2013} 19 Nov): met on 1 of 3 days, against today's goal.\n"),
                   "this week reads “\(week)”", &problems)
            // 5h of focus but 1h of goal credit: judged on focus it would read 1 of 1.
            let october = f.store.askLookup(.goals(.day(year: 2023, month: 10, day: 5)))
            expect(october.contains("Thu 5 Oct 2023: met on 0 of 1 days, against today's goal."),
                   "Thu 5 Oct reads “\(october)”", &problems)
            let monday = f.store.askLookup(.goals(.day(year: 2023, month: 11, day: 13)))
            expect(monday.contains("Mon 13 Nov 2023: met on 1 of 1 days"), "Mon 13 Nov reads “\(monday)”", &problems)
            // Days before the first recorded one are not counted.
            let all = f.store.askLookup(.goals(.allTime))
            expect(all.contains("All time: met on 1 of 46 days, against today's goal."), "all time reads “\(all)”", &problems)
            let year = f.store.askLookup(.goals(.thisYear))
            expect(year.contains("This year (2023): met on 1 of 46 days"), "this year reads “\(year)”", &problems)
        }
    }

    private static func streakFollowsStoreClock() -> [String] {
        AskDataFixture.with { f, problems in
            expect(f.store.askLookup(.goals(nil)).contains(streakLine), "the streak is not as at Wed 15 Nov", &problems)
            f.clock.advance(3 * 86_400)  // Sat 18 Nov, no focus since Tue 14.
            let got = f.store.askLookup(.goals(nil))
            expect(got.contains("\nNo current streak: a day counts at 1h of focus. Longest: 12 days.\n"),
                   "three days on, goals read “\(got)”", &problems)
        }
    }

    private static func streakCountsToday() -> [String] {
        AskDataFixture.with { f, problems in
            f.engine.start(workType: .deepWork, intent: "Review")
            f.clock.advance(30 * 60)
            let before = f.store.askLookup(.goals(nil))
            expect(before.contains(streakLine), "half an hour in, goals read “\(before)”", &problems)
            f.clock.advance(30 * 60)
            let got = f.store.askLookup(.goals(nil))
            expect(got.contains("Current streak: 6 days with at least 1h of focus, since Fri 10 Nov. Longest: 12 days."),
                   "an hour in, goals read “\(got)”", &problems)
        }
    }

    private static func wordedFromFigures() -> [String] {
        var problems: [String] = []
        let line = AskAwardLine(title: "Goal", detail: "10 days")
        let none = AskGoals(goal: 14_400, today: 1_800, todayPercent: "13%", period: nil, streakDays: 1,
                            streakSince: "Wed 15 Nov", streakMinimum: 3_600, bestStreak: 1, earned: [],
                            toEarn: [line])
        let text = AskFacts.goals(none)
        expect(text.contains("Today so far: 30m, 13%, not met yet."), "today reads “\(text)”", &problems)
        expect(text.contains("Current streak: 1 day with at least 1h of focus, since Wed 15 Nov. Longest: 1 day."),
               "one day reads “\(text)”", &problems)
        expect(text.hasSuffix("\nNo awards earned yet. Still to earn: Goal (10 days)."), "no award reads “\(text)”", &problems)
        let met = AskGoals(goal: 14_400, today: 14_700, todayPercent: "102%",
                           period: AskGoalPeriod(label: "September 2026", met: 14, days: 30), streakDays: 0,
                           streakSince: nil, streakMinimum: 3_600, bestStreak: 12, earned: [line], toEarn: [])
        let said = AskFacts.goals(met)
        expect(said.contains("Today: 4h 5m, met.\nSeptember 2026: met on 14 of 30 days, against today's goal.\n"),
               "met reads “\(said)”", &problems)
        expect(said.hasSuffix("\nAwards earned: Goal (10 days)."), "all earned reads “\(said)”", &problems)
        let many = (0..<80).map { AskAwardLine(title: "Award number \($0)", detail: "\($0) days") }
        let long = AskFacts.goals(AskGoals(goal: 14_400, today: 0, todayPercent: "0%", period: nil, streakDays: 0,
                                           streakSince: nil, streakMinimum: 3_600, bestStreak: 0,
                                           earned: many, toEarn: many))
        expect(long.utf8.count <= AskFacts.maximumBytes, "a long list is \(long.utf8.count) bytes", &problems)
        expect(long.hasPrefix("Daily goal: 4h of focus during recorded app use."), "a long list loses its head", &problems)
        return problems
    }

    // MARK: - Sources

    private static func linksListPeriodAndAwards() -> [String] {
        AskDataFixture.with { f, problems in
            let today = f.calendar.startOfDay(for: f.moment(0, 12))
            let names = ["streak", "streaks", "award", "awards"] + f.store.awards.map(\.title)
            let awards = AskLink(target: .awards, label: "Awards", role: .streakAndAwards, names: names)
            let bare = f.store.askLookupResult(.goals(nil)).links
            expect(bare == [AskLink(target: .day(today), label: "Wed 15 Nov", role: .dailyGoal), awards],
                   "goals list \(bare)", &problems)
            let week = f.store.askLookupResult(.goals(.thisWeek)).links
            expect(week.count == 2 && week[0].label == "13 Nov \u{2013} 19 Nov" && week[0].role == .dailyGoal
                   && week[1] == awards, "this week lists \(week)", &problems)
            expect(AskRequest.goals(.thisMonth).provenance == "goals (this month)", "provenance with a period differs", &problems)
            expect(AskRequest.goals(.month(year: 2026, month: 9)).provenance == "goals (September 2026)",
                   "provenance with a month differs", &problems)
            expect(AskRequest.goals(nil).provenance == "goals", "provenance without a period differs", &problems)
        }
    }

    private static func stillToCome() -> [String] {
        AskDataFixture.with { f, problems in
            let next = f.store.askLookupResult(.goals(.day(year: 2023, month: 11, day: 20)))
            expect(next.text == "Mon 20 Nov 2023 is still to come." && next.links.isEmpty,
                   "next Monday reads “\(next.text)”", &problems)
        }
    }

    // MARK: - Catalogue

    private static func catalogueEntry() -> [String] {
        var problems: [String] = []
        let names = AskLookups.all.map(\.spec.name)
        let order = ["focusTotals", "compareFocus", "bestHours", "findSessions", "appTime", "dayEvents",
                     "sessionDetail", "goals"]
        expect(names == order, "the catalogue lists \(names), not \(order)", &problems)
        let description = "Returns the daily goal, progress towards it today, the days a period met it, the current "
            + "and longest streak, and the awards earned and still to earn."
        let guide = AskLookups.all[0].spec.parameters[0].description + "; leave out for all time"
        let want = AskLookupSpec(name: "goals", description: description,
                                 parameters: [AskParameter(name: "range", description: guide, required: false)])
        expect(AskLookups.all.count >= 8 && AskLookups.all[7].spec == want,
               "the eighth entry is \(String(describing: AskLookups.all.dropFirst(7).first?.spec))", &problems)
        expect(AskLookups.named("goals")?.spec == want, "named(goals) is not that entry", &problems)
        guard let entry = AskLookups.named("goals") else { return problems }
        let asked = entry.read(["range": " this week "]) { AskRange(rawValue: $0) }
        expect(asked == .request(.goals(.thisWeek)), "a period read as \(asked)", &problems)
        let bare = entry.read([:]) { AskRange(rawValue: $0) }
        expect(bare == .request(.goals(nil)), "no period read as \(bare)", &problems)
        let blank = entry.read(["range": "  "]) { AskRange(rawValue: $0) }
        expect(blank == .request(.goals(nil)), "a blank period read as \(blank)", &problems)
        let refused = entry.read(["range": "31 february"]) { AskRange(rawValue: $0) }
        expect(refused == .refusal(AskFacts.noSuchPeriod("31 february")), "a bad date reads as \(refused)", &problems)
        if #available(macOS 26, *) {
            guard let schema = try? AskOnDeviceTool.schema(for: entry.spec),
                  let expected = try? AskOnDeviceTool.schema(for: want) else {
                problems.append("the schema could not be built"); return problems
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let got = (try? encoder.encode(schema)).flatMap { String(data: $0, encoding: .utf8) }
            let wanted = (try? encoder.encode(expected)).flatMap { String(data: $0, encoding: .utf8) }
            expect(got != nil && got == wanted, "the schema is \(got ?? "unencodable"), not \(wanted ?? "?")", &problems)
        }
        return problems
    }
}
