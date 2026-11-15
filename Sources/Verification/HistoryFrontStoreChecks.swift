import Foundation

/// The store's read models behind History's front view: the day grid, each
/// root row's facts and each row's split. They are worked out once per
/// archive state and kept current for today while a session runs.
enum HistoryFrontStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The front view is worked out once, not on every redraw", workedOutOnce),
        ("A running session lifts today's cell, its month's split and its facts without a rebuild", sessionLiftsToday),
        ("At midnight the ring moves to the new day", midnightMovesRing),
        ("A month's split agrees with its figure", splitAgrees),
        ("A month's categories read from the cache equal a fresh walk of its days, today included", categoriesEqualFreshWalk),
    ]

    /// The fixture's History holds Mon 13 and Tue 14 Nov (9 000 s of deep
    /// work) and Tue 17 Oct (7 200 s, its longest day) of 2023, and today is
    /// Wed 15 Nov. These extra days, a minute each from 6 Oct back, bring the
    /// record to the fourteen focused days a longest day needs to be named.
    /// The root rows are then Nov, Oct and Sep.
    private static let extraDays = 12
    private typealias Kind = HistoryGridCell.Kind

    /// The store's History brought up to the fixture's clock, as `AskLookup`
    /// does before it answers.
    private static func refresh(_ f: AskLookupChecks.Fixture) {
        _ = f.store.askLookup(.focusTotals(.today, words: nil))
    }

    private static func cells(_ grid: HistoryDayGrid?) -> [HistoryGridCell] {
        grid?.blocks.flatMap(\.cells) ?? []
    }

    /// Everything the front view reads, once, as one redraw does.
    private static func readAll(_ f: AskLookupChecks.Fixture) {
        _ = f.store.historyDayGrid()
        _ = f.store.historyRowFacts()
        for row in f.store.historyRows(under: nil) { _ = f.store.historySplit(for: row.place) }
    }

    // MARK: - Checks

    private static func workedOutOnce() -> [String] {
        AskLookupChecks.withFixture(extraThesisDays: extraDays) { f, problems in
            refresh(f)
            let start = f.store.historyTreeComputeCount
            readAll(f)
            let built = f.store.historyTreeComputeCount
            expect(built > start, "the first reads built nothing (count \(start), then \(built))", &problems)
            expect(f.store.historyDayGrid() != nil, "the fixture has no day grid", &problems)
            expect(!f.store.historyRowFacts().isEmpty, "the fixture has no row facts", &problems)
            for _ in 0..<10 { readAll(f) }
            let raised = f.store.historyTreeComputeCount - built
            expect(raised == 0, "ten more rounds of the same reads raised the compute count by \(raised)", &problems)
        }
    }

    /// What one round of reads shows of the day today.
    private struct Reading {
        var cell: HistoryGridCell?
        var currentRow: HistoryRow?
        /// The split of the root row holding today.
        var split: [HistorySplitPart] = []
        /// The day each root row names as the record's longest, by place id.
        var longestDay: [String: Date] = [:]
    }

    private static func read(_ f: AskLookupChecks.Fixture, today: Date) -> Reading {
        var reading = Reading(cell: cells(f.store.historyDayGrid()).first(where: \.isToday))
        let facts = f.store.historyRowFacts()
        for row in f.store.historyRows(under: nil) {
            let split = f.store.historySplit(for: row.place)
            if row.place.span.holds(today) { reading.currentRow = row; reading.split = split }
            for case .recordDay(let day, _) in facts[row.id]?.facts ?? [] { reading.longestDay[row.id] = day }
        }
        return reading
    }

    private static func sessionLiftsToday() -> [String] {
        AskLookupChecks.withFixture(extraThesisDays: extraDays) { f, problems in
            let calendar = f.calendar
            let today = calendar.startOfDay(for: f.clock.value)
            let oldRecord = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: today) ?? today)
            f.engine.start(workType: .learning, intent: "Probe")
            f.clock.advance(10 * 60)
            refresh(f)
            let before = read(f, today: today)
            guard let current = before.currentRow,
                  let octoberRow = f.store.historyRows(under: nil).first(where: { $0.place.span.holds(oldRecord) })
            else { problems.append("the fixture has no root row for today or for 17 Oct"); return }
            expect(before.cell?.focused == 600 && before.cell?.kind == Kind.recorded(.under2h),
                   "ten minutes in, today's cell reads \(String(describing: before.cell))", &problems)
            expect(before.longestDay[octoberRow.id] == oldRecord && before.longestDay[current.id] == nil,
                   "ten minutes in, the longest day is \(before.longestDay), not 17 Oct alone", &problems)

            f.clock.advance(3 * 3_600)
            refresh(f)
            let built = f.store.historyTreeComputeCount
            let after = read(f, today: today)
            expect(f.store.historyTreeComputeCount == built, "the session running on rebuilt the front view "
                   + "\(f.store.historyTreeComputeCount - built) times", &problems)
            expect(after.cell?.focused == 11_400 && after.cell?.kind == Kind.recorded(.under5h),
                   "three hours later, today's cell reads \(String(describing: after.cell))", &problems)
            // Nov holds 9 000 s of deep work; the session adds the rest.
            func learning(_ parts: [HistorySplitPart]) -> Double? { parts.first { $0.workType == .learning }?.share }
            expect(learning(before.split).map { abs($0 - 600 / 9_600) < 1e-9 } == true,
                   "ten minutes in, this month's learning share is \(String(describing: learning(before.split)))",
                   &problems)
            expect(learning(after.split).map { abs($0 - 11_400 / 20_400) < 1e-9 } == true,
                   "three hours later, this month's learning share is \(String(describing: learning(after.split)))",
                   &problems)
            expect(after.longestDay[current.id] == today && after.longestDay[octoberRow.id] == nil,
                   "three hours later, the longest day is \(after.longestDay), not today alone", &problems)
        }
    }

    private static func midnightMovesRing() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let calendar = f.calendar
            refresh(f)
            let today = calendar.startOfDay(for: f.clock.value)
            expect(cells(f.store.historyDayGrid()).filter(\.isToday).map(\.day) == [today],
                   "before midnight the ring is not on today alone", &problems)

            let tomorrow = HistoryTreeBuilder.dayAfter(today, calendar: calendar)
            f.clock.value = tomorrow.addingTimeInterval(13 * 60)
            let after = cells(f.store.historyDayGrid())
            expect(after.filter(\.isToday).map(\.day) == [tomorrow],
                   "after midnight the ring is on \(after.filter(\.isToday).map(\.day)), not on \(tomorrow) alone",
                   &problems)
            let yesterday = after.first { $0.day == today }
            expect(yesterday?.kind == Kind.recorded(HistoryFocusStep.none),
                   "yesterday's cell is \(String(describing: yesterday?.kind)), not recorded", &problems)

            // A new month needs a block the old grid never had, so it is rebuilt, not patched.
            let blocks = f.store.historyDayGrid()?.blocks.count ?? 0
            let nextMonth = calendar.dateInterval(of: .month, for: today)?.end ?? tomorrow
            f.clock.value = nextMonth.addingTimeInterval(13 * 60)
            let first = calendar.startOfDay(for: f.clock.value)
            let rolled = f.store.historyDayGrid()
            expect(rolled?.blocks.count == blocks + 1 && rolled?.blocks.last?.cells.first?.day == first
                   && rolled?.blocks.last?.cells.first?.isToday == true,
                   "on the 1st the grid has \(String(describing: rolled?.blocks.count)) blocks, not \(blocks + 1), "
                   + "or no ring on the 1st", &problems)
        }
    }

    private static func splitAgrees() -> [String] {
        AskLookupChecks.withFixture(extraThesisDays: extraDays) { f, problems in
            refresh(f)
            let rows = f.store.historyRows(under: nil)
            expect(rows.count == 3, "the fixture has \(rows.count) root rows, not 3", &problems)
            for row in rows {
                let shares = f.store.historyCategories(for: row.place)
                let parts = f.store.historySplit(for: row.place)
                expect(abs(parts.reduce(0) { $0 + $1.share } - 1) < 1e-9,
                       "\(row.id) split shares sum to \(parts.reduce(0) { $0 + $1.share }), not 1", &problems)
                expect(parts == HistorySplit.parts(shares), "\(row.id) split is not the parts of its categories",
                       &problems)
                expect(abs(shares.reduce(0) { $0 + $1.seconds } - row.focused) < 1e-9,
                       "\(row.id) splits \(shares.reduce(0) { $0 + $1.seconds }) s, its figure is \(row.focused) s",
                       &problems)
            }
            let weeks = rows.first.map { f.store.historyRows(under: $0.place) } ?? []
            if let quiet = weeks.first(where: { $0.focused == 0 }) {
                expect(f.store.historySplit(for: quiet.place).isEmpty, "a row without focus has a split", &problems)
            } else {
                problems.append("the fixture's newest month has no row without focus")
            }
        }
    }

    private static func categoriesEqualFreshWalk() -> [String] {
        AskLookupChecks.withFixture(extraThesisDays: extraDays) { f, problems in
            let calendar = f.calendar
            let today = calendar.startOfDay(for: f.clock.value)
            f.engine.start(workType: .learning, intent: "Probe")
            f.clock.advance(10 * 60)
            refresh(f)
            /// The days of the place summed straight from the journal's days, with no cache.
            func fresh(_ place: HistoryPlace) -> [WorkTypeShare] {
                var seconds: [WorkType: TimeInterval] = [:]
                for day in f.store.historyDays where place.span.holds(day.date) {
                    for (type, value) in day.focusByWorkType { seconds[type, default: 0] += value }
                }
                return WorkTypeShare.shares(from: seconds)
            }
            // The root rows, today, and the whole month of today: Ask's "this month" runs past today.
            let places = f.store.historyRows(under: nil).map(\.place) + [
                HistoryPlace(level: .day, span: DateInterval(
                    start: today, end: HistoryTreeBuilder.dayAfter(today, calendar: calendar))),
                HistoryPlace(level: .month, span: HistoryTreeBuilder.period(.month, containing: today, calendar: calendar)),
            ]
            for (label, seconds) in [("ten minutes in", 0.0), ("three hours later", 3 * 3_600)] {
                f.clock.advance(seconds)
                refresh(f)
                for place in places {
                    let got = f.store.historyCategories(for: place)
                    expect(got == fresh(place), "\(label), \(place.level) \(place.id) reads \(got), "
                           + "a fresh walk reads \(fresh(place))", &problems)
                }
                expect(!(places.first.map(fresh) ?? []).isEmpty, "\(label), the fixture's month has no focus", &problems)
            }
        }
    }
}
