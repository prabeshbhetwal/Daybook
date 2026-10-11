import Foundation

/// Ask Daybook v2 part 2: what the lookups say beyond part 1's facts. A
/// session list says when each session began with “from”, so the model
/// cannot read `2:00pm · Parser · 4h` as 2h 00m, and shows each session's
/// note, not only a note that matched the words. App time names the hours of
/// the day an app was in front, from History's per-app lens, and the busiest
/// hours of a day when no app is named.
enum AskFactsExtensionChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session line says when it began with “from”", sessionLineSaysFrom),
        ("Every listed session shows its note", everyListedSessionShowsItsNote),
        ("A note line that matches the words wins over the first line", matchingNoteLineWins),
        ("Hours are worded top three, most first, earlier first on a tie", hoursPhraseWording),
        ("App time names the hours an app was in front", appTimeNamesHours),
        ("App hours are History's lens figures", appHoursAreTheLensFigures),
        ("The shared Ask fixture holds the figures later checks pin", fixtureHoldsPinnedFigures),
        ("Totals give the time in each work type, as History does", totalsGiveWorkTypes),
        ("Words that name a work type give that type's total", wordsNameWorkType),
        ("All-time totals name the current streak", allTimeNamesStreak),
        ("Words that name an app bring its hours", wordsNameAppHours),
        ("Words found in a note bring the note's line", wordsFindNoteLine),
        ("Totals stay within 1 KB with the new parts", totalsStayWithinCap),
    ]

    private static func sessionLineSaysFrom() -> [String] {
        var problems: [String] = []
        let timed = AskFacts.sessions(.allTime, words: "", lines: [
            AskSessionLine(day: "Tue 15 Sep", time: "2:00pm", name: "Parser", worked: 14_400)])
        expect(timed == "Tue 15 Sep · Parser · from 2:00pm · 4h", "a timed session says “\(timed)”", &problems)
        let untimed = AskFacts.sessions(.allTime, words: "", lines: [
            AskSessionLine(day: "Tue 15 Sep", time: "", name: "Parser", worked: 14_400)])
        expect(untimed == "Tue 15 Sep · Parser · 4h", "a session with no time says “\(untimed)”", &problems)
        return problems
    }

    private static func everyListedSessionShowsItsNote() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let text = f.store.askLookup(.findSessions(words: "", .allTime))
            expect(text.contains("Thesis · from 9:00am · 1h · note: chapter two outline"),
                   "Mon 13 Nov's Thesis is listed as “\(text)”", &problems)
            // The other sessions have no note, so none is invented for them.
            expect(text.contains("Parser · from 2:00pm · 1h 30m"), "Parser is listed as “\(text)”", &problems)
            expect(!text.contains("Parser · from 2:00pm · 1h 30m · note"),
                   "Parser, which has no note, is listed with one: “\(text)”", &problems)
        }
    }

    private static func matchingNoteLineWins() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            guard let thesis = f.store.metadataArchive.allMetadata.first(where: { $0.note == "chapter two outline" }),
                  case .saved = f.store.metadataArchive.saveNote("first line\nchapter two outline", for: thesis.recordID)
            else { problems.append("could not save the two-line note"); return }
            let matched = f.store.askLookup(.findSessions(words: "outline", .allTime))
            expect(matched.contains("note: chapter two outline") && !matched.contains("note: first line"),
                   "a search for “outline” says “\(matched)”", &problems)
            let all = f.store.askLookup(.findSessions(words: "", .allTime))
            expect(all.contains("note: first line") && !all.contains("note: chapter two outline"),
                   "a search with no words says “\(all)”", &problems)
        }
    }

    private static func hoursPhraseWording() -> [String] {
        var problems: [String] = []
        var hours = Array(repeating: TimeInterval(0), count: 24)
        expect(AskFacts.hoursPhrase(hours) == nil, "no hours said “\(AskFacts.hoursPhrase(hours) ?? "nil")”", &problems)
        hours[9] = 59
        expect(AskFacts.hoursPhrase(hours) == nil, "59 s counted as an hour", &problems)
        hours[14] = 3_600
        expect(AskFacts.hoursPhrase(hours) == "from 2pm to 3pm (1h)", "one hour says “\(AskFacts.hoursPhrase(hours) ?? "nil")”", &problems)
        hours[15] = 86_700
        hours[10] = 24_000
        hours[14] = 112_800
        hours[11] = 60
        let three = "from 2pm to 3pm (31h 20m), then from 3pm to 4pm (24h 5m) and from 10am to 11am (6h 40m)"
        expect(AskFacts.hoursPhrase(hours) == three, "three hours say “\(AskFacts.hoursPhrase(hours) ?? "nil")”", &problems)
        var ties = Array(repeating: TimeInterval(0), count: 24)
        ties[23] = 600
        ties[0] = 600
        ties[5] = 600
        let tied = AskFacts.hoursPhrase(ties) ?? "nil"
        expect(tied == "from midnight to 1am (10m), then from 5am to 6am (10m) and from 11pm to midnight (10m)",
               "tied hours say “\(tied)”", &problems)
        return problems
    }

    private static func appTimeNamesHours() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let named = f.store.askLookup(.appTime(.allTime, app: "safari"))
            expect(named.contains("; most in front from 2pm to 3pm (1h)"), "Safari's app time says “\(named)”", &problems)
            let day = f.store.askLookup(.appTime(.yesterday, app: nil))
            expect(day.contains("Busiest hours: from 2pm to 3pm (1h)."), "yesterday's app use says “\(day)”", &problems)
            let month = f.store.askLookup(.appTime(.thisMonth, app: nil))
            expect(!month.contains("Busiest hours"), "a month's app use names busiest hours: “\(month)”", &problems)
        }
    }

    private static func appHoursAreTheLensFigures() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let filter = f.store.historyFilter
            let everything = DateInterval(start: Date(timeIntervalSince1970: 0),
                                          end: f.clock.value.addingTimeInterval(86_400 * 365))
            let hours = f.store.askAppHours(bundleID: "com.apple.Safari", in: everything)
            let lens = HistoryAppLens.build(bundleID: "com.apple.Safari", records: f.engine.archive.records,
                                            usage: f.store.historySortedUsage(), calendar: .current,
                                            accurateFrom: f.store.effectiveUsageSnapshot?.accurateFrom)
            expect(hours.count == 24, "\(hours.count) hours, not 24", &problems)
            for hour in 0..<min(24, hours.count) {
                let want = lens.hoursInSession[hour] + lens.hoursOutside[hour]
                expect(hours[hour] == want, "hour \(hour) is \(hours[hour]) s, History's lens says \(want) s", &problems)
            }
            expect(hours.reduce(0, +) == 3_600, "Safari's hours add up to \(hours.reduce(0, +)) s, not 3600", &problems)
            // A narrower period clips the stretch.
            let recent = f.store.askAppHours(bundleID: "com.apple.Safari",
                                           in: DateInterval(start: f.clock.value.addingTimeInterval(-86_400 * 3),
                                                            end: everything.end))
            expect(recent == hours, "a period holding the stretch gave different hours", &problems)
            let none = f.store.askAppHours(bundleID: "com.apple.Safari",
                                           in: DateInterval(start: f.clock.value.addingTimeInterval(-3_600),
                                                            end: f.clock.value))
            expect(none.reduce(0, +) == 0, "a period before the stretch holds \(none.reduce(0, +)) s", &problems)
            expect(f.store.historyFilter == filter, "a lookup changed History's filter", &problems)
            _ = f.store.askLookup(.appTime(.allTime, app: "safari"))
            expect(f.store.historyFilter == filter, "an app time lookup changed History's filter", &problems)
        }
    }

    // MARK: - Focus totals

    private static func fixtureHoldsPinnedFigures() -> [String] {
        AskDataFixture.with { f, problems in
            let archive = f.engine.archive
            expect(archive.currentStreak() == 5 && archive.bestStreak() == 12,
                   "the streak is \(archive.currentStreak()) days, the best \(archive.bestStreak())", &problems)
            let monday = f.store.storyDayProjection(on: f.moment(2, 12), calendar: f.calendar)
            expect(monday.focused == 16_920 && monday.goalCredit == 16_920,
                   "Mon 13 Nov is \(monday.focused) s with \(monday.goalCredit) s of goal credit", &problems)
            let tuesday = f.store.storyDayProjection(on: f.moment(1, 12), calendar: f.calendar)
            expect(tuesday.focused == 3_600 && tuesday.goalCredit == 3_600,
                   "Tue 14 Nov is \(tuesday.focused) s with \(tuesday.goalCredit) s of goal credit", &problems)
            let october = f.store.storyDayProjection(on: f.octFifth.start, calendar: f.calendar)
            expect(october.focused == 18_000 && october.goalCredit == 3_600,
                   "Oct 5 is \(october.focused) s with \(october.goalCredit) s of goal credit", &problems)
            let items = f.store.storyTimelineItems(on: f.moment(2, 12))
            let decisions = items.compactMap { item -> String? in
                if case let .decision(receipt, _) = item { return receipt.name }
                return nil
            }
            // The sessions the engine was asked about them in: the receipt never holds the user's words.
            expect(Set(decisions) == ["Thesis", "Email"] && decisions.count == 2,
                   "Mon 13 Nov shows the answers \(decisions)", &problems)
            let kinds = f.machineEvents.events.map(\.kind)
            expect(kinds == [.wake, .lock, .unlock, .systemSleep, .wake, .crashed], "the event log holds \(kinds)", &problems)
            let power = (f.metadata.metadata(for: f.thesisA.id)?.power.count ?? 0)
                + (f.metadata.metadata(for: f.thesisB.id)?.power.count ?? 0)
            expect(power == 4, "the Thesis records hold \(power) battery readings, not 4", &problems)
            expect(f.engine.store.dailyGoal == 14_400 && f.engine.store.streakMinimum == 3_600,
                   "the goal and the streak minimum are not set", &problems)
        }
    }

    private static func totalsGiveWorkTypes() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.focusTotals(.thisMonth, words: nil))
            expect(text.contains("By work type: Deep work 8h 12m, Admin 30m."), "this month says “\(text)”", &problems)
            let place = HistoryPlace(level: .month, span: f.store.askInterval(.thisMonth))
            let history = f.store.historyCategories(for: place)
            let shares = f.store.askWorkTypes(.thisMonth)
            expect(shares.map(\.name) == history.map(\.workType.displayName)
                   && shares.map(\.seconds) == history.map(\.seconds) && shares.count == 2,
                   "Ask's work types \(shares) differ from History's \(history)", &problems)
        }
    }

    private static func wordsNameWorkType() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.focusTotals(.thisMonth, words: "admin"))
            expect(text.hasPrefix("Sessions matching “admin” this month (November 2023)"), "the answer says “\(text)”", &problems)
            expect(text.contains("30m over 1 session"), "the admin total is not given: “\(text)”", &problems)
        }
    }

    private static func allTimeNamesStreak() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.focusTotals(.allTime, words: nil))
            expect(text.contains("The current streak is 5 days, since Fri 10 Nov."), "all time says “\(text)”", &problems)
            let month = f.store.askLookup(.focusTotals(.thisMonth, words: nil))
            expect(!month.contains("streak"), "a month names the streak: “\(month)”", &problems)
            f.clock.value = f.moment(-3, 9)
            let later = f.store.askLookup(.focusTotals(.allTime, words: nil))
            expect(!later.contains("streak"), "days after the streak ended, all time says “\(later)”", &problems)
        }
    }

    private static func wordsNameAppHours() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.focusTotals(.allTime, words: "safari"))
            let hours = "Most in front from 7am to 8am (4h), then from 9am to 10am (1h) and from 11am to 12pm (55m)."
            expect(text.contains(hours), "Safari's totals say “\(text)”", &problems)
            // No session is named Safari, yet the app's hours are still given.
            let month = f.store.askLookup(.focusTotals(.lastMonth, words: "safari"))
            expect(month.hasPrefix("No sessions match “safari” last month"), "last month says “\(month)”", &problems)
        }
    }

    private static func wordsFindNoteLine() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.focusTotals(.allTime, words: "tokenizer"))
            expect(text.contains("A matching note: “tokenizer rewrite”."), "the totals say “\(text)”", &problems)
            let none = f.store.askLookup(.focusTotals(.allTime, words: "thesis"))
            expect(!none.contains("A matching note"), "a name that no note line holds brought a note: “\(none)”", &problems)
        }
    }

    private static func totalsStayWithinCap() -> [String] {
        var problems = AskLookupChecks.withFixture(extraThesisDays: 1_000) { f, problems in
            for range in AskRange.allCases {
                let text = f.store.askLookup(.focusTotals(range, words: nil))
                expect(text.utf8.count <= AskFacts.maximumBytes, "\(range.title) is \(text.utf8.count) bytes", &problems)
            }
        }
        problems += AskDataFixture.with { f, problems in
            for range in AskRange.allCases {
                for words in [nil, "safari", "tokenizer"] {
                    let text = f.store.askLookup(.focusTotals(range, words: words))
                    expect(text.utf8.count <= AskFacts.maximumBytes,
                           "\(range.title) with \(words ?? "no words") is \(text.utf8.count) bytes", &problems)
                }
            }
        }
        return problems
    }
}
