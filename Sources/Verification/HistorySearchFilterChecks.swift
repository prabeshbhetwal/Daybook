import Foundation

/// What History's search does with the periods, weekdays, lengths and names
/// typed into it, end to end through a real store: the text is kept as typed,
/// the filter follows it, the menus and the typed names agree, and the
/// session list and the day map read the same filter the same way. "Now" is
/// Wednesday 15 November 2023 (`AskLookupChecks.withFixture`), whose sessions
/// are Thesis on Mon 13 Nov 9–10, Parser on Tue 14 Nov 14:00–15:30 with Safari
/// in front, and Thesis on Tue 17 Oct 9–11.
enum HistorySearchFilterChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A period alone lists the sessions in it", periodOnly),
        ("The list and the map agree on span and weekdays", listMapAgree),
        ("Length counts focus without pauses, and breaks never pass it", lengthRule),
        ("A typed name and its menu set the same filter, and the menu wins its kind back", typedVersusMenu),
        ("Removing a chip removes its words from the text", removePhrase),
        ("Disjoint periods list nothing", noOverlapEmpty),
        ("Clearing the filters resets the text, the phrases, the menus and the filter", clearsEverything),
        ("A period or a length turns the app view off", phrasesTurnLensOff),
    ]

    private typealias Fixture = AskLookupChecks.Fixture
    private static let safari = "com.apple.Safari"

    private static func hits(_ f: Fixture, _ text: String) -> [HistorySearchHit] {
        f.store.setHistoryQuery(text)
        return f.store.historySearchHits(limit: .max)
    }

    private static func names(_ hits: [HistorySearchHit]) -> Set<String> { Set(hits.map(\.name)) }

    /// A record `back` days before the clock's day, starting at `hour`, that
    /// ran `minutes` on the clock and was worked for `worked` seconds.
    private static func add(_ f: Fixture, _ name: String, _ type: WorkType = .deepWork, back: Int, hour: Int,
                            minutes: Int, worked: TimeInterval, thread: UUID = UUID(),
                            _ problems: inout [String]) {
        let day = f.calendar.date(byAdding: .day, value: -back, to: f.calendar.startOfDay(for: f.clock.value))!
        let start = f.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let record = SessionRecord(name: name, workType: type, start: start,
                                   end: start.addingTimeInterval(Double(minutes) * 60), workSeconds: worked,
                                   threadID: thread)
        expect(f.engine.archive.append(record) == nil, "could not record \(name)", &problems)
    }

    private static func midnight(_ f: Fixture, _ month: Int, _ day: Int) -> Date {
        f.calendar.date(from: DateComponents(year: 2023, month: month, day: day))!
    }

    private static func periodOnly() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            add(f, "Review", back: 9, hour: 9, minutes: 60, worked: 3_600, &problems)
            let week = hits(f, "this week")
            let span = DateInterval(start: midnight(f, 11, 13), end: midnight(f, 11, 20))
            expect(f.store.historyParsedSearch.span == span, "this week reads \(String(describing: f.store.historyParsedSearch.span))", &problems)
            expect(names(week) == ["Thesis", "Parser"], "this week lists \(names(week))", &problems)
            expect(week.allSatisfy { span.holds($0.day) }, "a hit sits outside this week: \(week.map(\.day))", &problems)
            expect(f.store.historyFilter.query.isEmpty && f.store.historySearchText == "this week",
                   "the filter holds “\(f.store.historyFilter.query)”, the text “\(f.store.historySearchText)”", &problems)

            // Monday 13 Nov is the day last week ends at midnight: not in it.
            let last = hits(f, "last week")
            expect(names(last) == ["Review"], "last week lists \(names(last)), not Review alone", &problems)
            let month = hits(f, "last month")
            expect(month.map(\.name) == ["Thesis"] && month.first?.worked == 7_200,
                   "last month lists \(month.map(\.name)), not the October Thesis", &problems)
        }
    }

    private static func listMapAgree() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.refreshReview()
            let monday = midnight(f, 11, 13)
            let mondays = hits(f, "this week on Mondays")
            expect(Set(mondays.map(\.day)) == [monday], "this week on Mondays lists \(mondays.map(\.day))", &problems)
            for text in ["this week on Mondays", "Tuesdays", "this week", "last month", "last month Mondays",
                         "weekends", "Mondays and Tuesdays 2023", "this week Fridays"] {
                f.store.setHistoryQuery(text)
                let listed = Set(f.store.historySearchHits(limit: .max).map(\.day))
                let mapped = Set(f.store.filteredHistoryDays.filter { $0.sessions > 0 }.map(\.date))
                expect(listed == mapped, "“\(text)”: the list has \(listed.sorted()), the map \(mapped.sorted())", &problems)
            }
            f.store.setHistoryQuery("Tuesdays")
            expect(f.store.filteredHistoryDays.count == 2, "Tuesdays keeps \(f.store.filteredHistoryDays.count) days, not 2", &problems)
        }
    }

    private static func lengthRule() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // Last week: Drafting ran 2h on the clock but was worked for 30m; Long was worked for 2h; Split is
            // two 40m stretches of one session; Lunch is a 90m break.
            add(f, "Drafting", back: 9, hour: 9, minutes: 120, worked: 1_800, &problems)
            add(f, "Long", back: 8, hour: 9, minutes: 120, worked: 7_200, &problems)
            let thread = UUID()
            add(f, "Split", back: 6, hour: 9, minutes: 40, worked: 2_400, thread: thread, &problems)
            add(f, "Split", back: 6, hour: 10, minutes: 40, worked: 2_400, thread: thread, &problems)
            add(f, "Lunch", .breakTime, back: 7, hour: 12, minutes: 90, worked: 5_400, &problems)
            let category = WorkType.breakTime.displayName

            expect(names(hits(f, "last week")) == ["Drafting", "Long", "Split"], "last week lists \(names(hits(f, "last week")))", &problems)
            let over = hits(f, "last week over 1h")
            expect(names(over) == ["Long", "Split"], "over 1h lists \(names(over)); pauses or breaks counted, or a split session not summed", &problems)
            let under = hits(f, "last week under 1h")
            expect(names(under) == ["Drafting"], "under 1h lists \(names(under))", &problems)
            expect(hits(f, "last week \(category)").map(\.name) == ["Lunch"], "the Break category lists no break", &problems)
            expect(hits(f, "last week \(category) over 1h").isEmpty, "a break passed a length filter", &problems)
            expect(hits(f, "last week \(category) under 2h").isEmpty, "a break passed a maximum length", &problems)
            expect(names(hits(f, "Lunch last week")) == ["Lunch"], "words did not find the break", &problems)
            expect(hits(f, "Lunch last week over 1h").isEmpty, "a break found by words passed a length filter", &problems)

            // Exactly an hour is over an hour and under an hour: Thesis on Monday 13 Nov.
            expect(names(hits(f, "this week over 1h")).contains("Thesis"), "exactly 1h is not over 1h", &problems)
            expect(names(hits(f, "this week under 1h")) == ["Thesis"], "exactly 1h is not under 1h: \(names(hits(f, "this week under 1h")))", &problems)
            let between = hits(f, "last week between 45m and 90m")
            expect(names(between) == ["Split"], "between 45m and 90m lists \(names(between))", &problems)
        }
    }

    private static func typedVersusMenu() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.refreshReview()
            let other = "com.example.Other"
            f.store.setHistoryQuery("Safari")
            expect(f.store.historyFilter.appBundleID == safari && f.store.historyFilter.query.isEmpty,
                   "a typed Safari sets \(String(describing: f.store.historyFilter.appBundleID))", &problems)
            expect(f.store.historyMenuApp == nil, "typing set the menu's pick", &problems)

            f.store.setHistoryApp(other)
            expect(f.store.historySearchText == "", "the menu pick left “\(f.store.historySearchText)” in the text", &problems)
            expect(f.store.historyFilter.appBundleID == other && f.store.historyMenuApp == other,
                   "the menu pick is not the filter: \(String(describing: f.store.historyFilter.appBundleID))", &problems)

            // Typed beats the menu while it is typed, and the menu comes back when it goes.
            f.store.setHistoryQuery("Thesis Safari")
            expect(f.store.historyFilter.appBundleID == safari && f.store.historyFilter.query == "Thesis",
                   "typed beside a pick: \(f.store.historyFilter)", &problems)
            if let phrase = f.store.historyParsedSearch.phrases.first {
                f.store.removeHistoryPhrase(phrase)
                expect(f.store.historyFilter.appBundleID == other && f.store.historySearchText == "Thesis",
                       "after the chip, \(f.store.historyFilter) from “\(f.store.historySearchText)”", &problems)
            } else {
                problems.append("“Thesis Safari” read no phrase")
            }

            // Words around the name keep their single spacing; clearing the pick clears the name.
            f.store.setHistoryQuery("Thesis Safari notes")
            f.store.setHistoryApp(nil)
            expect(f.store.historySearchText == "Thesis notes" && f.store.historyFilter.appBundleID == nil,
                   "clearing the app left “\(f.store.historySearchText)”, \(String(describing: f.store.historyFilter.appBundleID))", &problems)

            // A second typed name would become the app once the first goes: the pick must still win.
            f.store.historyAppNames["com.apple.Notes"] = "Notes"
            f.store.setHistoryQuery("Safari Notes")
            f.store.setHistoryApp(other)
            expect(f.store.historyFilter.appBundleID == other && f.store.historySearchText == "",
                   "a second name outlived the menu pick: “\(f.store.historySearchText)”, \(String(describing: f.store.historyFilter.appBundleID))", &problems)

            // The same for a category.
            let deep = WorkType.deepWork
            f.store.setHistoryQuery("Parser \(deep.displayName)")
            expect(f.store.historyFilter.workType == deep && f.store.historyFilter.query == "Parser",
                   "a typed category sets \(String(describing: f.store.historyFilter.workType))", &problems)
            f.store.setHistoryWorkType(.breakTime)
            expect(f.store.historySearchText == "Parser" && f.store.historyFilter.workType == .breakTime
                   && f.store.historyMenuWorkType == .breakTime,
                   "the category menu left “\(f.store.historySearchText)”, \(String(describing: f.store.historyFilter.workType))", &problems)
        }
    }

    private static func removePhrase() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setHistoryQuery("Thesis last week over 1h")
            let phrases = f.store.historyParsedSearch.phrases
            expect(phrases.map(\.kind) == [.period, .length], "read \(phrases.map(\.kind))", &problems)
            if let period = phrases.first {
                f.store.removeHistoryPhrase(period)
                expect(f.store.historySearchText == "Thesis over 1h", "removing the period left “\(f.store.historySearchText)”", &problems)
                expect(f.store.historyFilter.span == nil && f.store.historyFilter.minLength == 3_600,
                       "the filter did not follow: \(f.store.historyFilter)", &problems)
                if let length = f.store.historyParsedSearch.phrases.first {
                    f.store.removeHistoryPhrase(length)
                    expect(f.store.historySearchText == "Thesis", "removing the length left “\(f.store.historySearchText)”", &problems)
                }
            }
            f.store.setHistoryQuery("last week Thesis")
            if let first = f.store.historyParsedSearch.phrases.first {
                f.store.removeHistoryPhrase(first)
                expect(f.store.historySearchText == "Thesis", "removing the first phrase left “\(f.store.historySearchText)”", &problems)
                // A chip drawn from older text names a range that is no longer there: nothing changes.
                f.store.removeHistoryPhrase(first)
                expect(f.store.historySearchText == "Thesis", "a stale chip changed the text to “\(f.store.historySearchText)”", &problems)
            }
        }
    }

    private static func noOverlapEmpty() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.refreshReview()
            let listing = hits(f, "last month today")
            let parsed = f.store.historyParsedSearch
            expect(parsed.noOverlap && f.store.historyFilter.noOverlap && f.store.historyFilter.isActive,
                   "disjoint periods did not read as no overlap: \(parsed)", &problems)
            expect(listing.isEmpty, "disjoint periods list \(names(listing))", &problems)
            expect(f.store.historySearchHits(matching: f.store.historyFilter, limit: .max, listingAll: true).isEmpty,
                   "listing everything ignored no overlap", &problems)
            expect(f.store.filteredHistoryDays.isEmpty, "the map keeps \(f.store.filteredHistoryDays.count) days", &problems)
            if let today = parsed.phrases.last {
                f.store.removeHistoryPhrase(today)
                expect(f.store.historySearchText == "last month", "removing today left “\(f.store.historySearchText)”", &problems)
                expect(names(f.store.historySearchHits(limit: .max)) == ["Thesis"], "last month alone lists nothing", &problems)
            }
        }
    }

    private static func clearsEverything() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setHistoryApp(safari)
            f.store.setHistoryWorkType(.deepWork)
            f.store.setHistoryQuery("Thesis last week over 1h")
            f.store.clearHistoryFilters()
            expect(f.store.historySearchText.isEmpty, "the text is “\(f.store.historySearchText)”", &problems)
            expect(f.store.historyParsedSearch == ParsedSearch(leftover: "", phrases: []), "the parse is \(f.store.historyParsedSearch)", &problems)
            expect(f.store.historyMenuApp == nil && f.store.historyMenuWorkType == nil, "a menu pick survived", &problems)
            expect(f.store.historyFilter == HistoryFilter(), "the filter is \(f.store.historyFilter)", &problems)
        }
    }

    private static func phrasesTurnLensOff() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.refreshReview()
            f.store.setHistoryApp(safari)
            expect(f.store.historyAppLens() != nil, "the app alone shows no app view", &problems)
            for text in ["this week", "over 1h", "Mondays"] {
                f.store.setHistoryQuery(text)
                expect(f.store.historyFilter.appBundleID == safari, "“\(text)” lost the menu's app", &problems)
                expect(f.store.historyAppLens() == nil, "“\(text)” beside an app still shows the app view", &problems)
            }
        }
    }
}
