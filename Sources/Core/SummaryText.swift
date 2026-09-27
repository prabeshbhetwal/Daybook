import Foundation

/// The figures a day summary is written from. Plain values so the composer
/// is pure and the tests can hand it a day without an archive behind it.
struct DaySummaryInput {
    var day: Date
    var isToday: Bool
    /// Hands-on time at the Mac and the first and last moments of it.
    var tracked: TimeInterval
    var firstSeen: Date?
    var lastSeen: Date?
    /// Session work on the day, and the day's goal (0 means none).
    var focused: TimeInterval
    var goal: TimeInterval
    /// Goal credit can be stricter than the raw focused statistic. Nil preserves
    /// legacy callers that intentionally use the same value for both.
    var goalAchieved: TimeInterval? = nil
    /// The day's sessions and the rests between their stretches, as the
    /// Sessions card shows them.
    var sessions: [DaySession]
    var rests: [RestEntry]
    /// Apps by time, busiest first; the busiest hours, if there were any.
    var apps: [AppRank]
    var peak: String?
    /// Share of tracked time that fell inside a session; app switches per
    /// stretch; the work-type split of the session time.
    var insideSessionShare: Double
    var switchesPerStretch: Double
    var workTypes: [WorkTypeShare]
    /// The day before, for the comparison. Zero means nothing to compare.
    var previousTracked: TimeInterval
    var previousFocused: TimeInterval
}

/// The figures a week or month summary is written from.
struct PeriodSummaryInput {
    var period: TrackingPeriod
    var containsToday: Bool
    var tracked: TimeInterval
    var activeDays: Int
    var totalDays: Int
    var averagePerActiveDay: TimeInterval
    var previousTracked: TimeInterval
    var focused: TimeInterval
    var sessions: Int
    var goal: TimeInterval
    var goalMetDays: Int
    var busiestDay: Date?
    var busiestTracked: TimeInterval
    var longestSitting: (appName: String, attended: TimeInterval, day: Date)?
    var apps: [(name: String, total: TimeInterval, share: Double)]
    var appCount: Int
    var workTypes: [WorkTypeShare]
}

/// The dashboard in words. Every clause is gated on the figure behind it, the
/// way the insights are: nothing is said that the records do not support, and
/// no model is involved — the sentences *are* the figures, joined. `**` marks
/// the figures for the view to set in bold; `plain(_:)` strips the marks for
/// the pasteboard and the tests.
enum SummaryText {

    // MARK: - A day

    static func day(_ input: DaySummaryInput, calendar: Calendar = .current) -> [String] {
        guard input.tracked > 0 || input.focused > 0 || !input.sessions.isEmpty else {
            return [input.isToday ? "Nothing recorded yet today." : "Nothing was recorded on this day."]
        }
        return [presence(input), sessions(input), apps(input), quality(input),
                comparison(input, calendar: calendar)]
            .compactMap { $0 }
    }

    /// Observed Mac use, declared focus, and goal credit — separate measures.
    private static func presence(_ i: DaySummaryInput) -> String {
        let count = Set(i.sessions.map(\.threadID)).count
        let inSessions = count == 0 ? "" : count == 1 ? " in one session" : " in \(count) sessions"
        var text: String
        if i.tracked > 0 {
            text = i.isToday ? "So far today you've been at the Mac for **\(duration(i.tracked))**"
                             : "You were at the Mac for **\(duration(i.tracked))**"
            if let first = i.firstSeen, let last = i.lastSeen {
                text += i.isToday ? ", since \(clock(first))" : ", \(clock(first)) – \(clock(last))"
            }
            if i.focused > 0 {
                text += ", and focused for **\(duration(i.focused))**\(inSessions)"
                // Their quotient is not an overlap, even when below 100%.
                // The quality sentence uses the actual temporal intersection.
                if let goal = goalClause(i) { text += " — " + goal }
            } else {
                text += i.isToday ? ", with no focus session yet" : ", with no focus session"
            }
        } else {
            // Sessions with nothing hands-on behind them: the tracker was off,
            // or the work happened away from the keyboard.
            text = i.isToday ? "So far today you've focused for **\(duration(i.focused))**\(inSessions)"
                             : "You focused for **\(duration(i.focused))**\(inSessions)"
            if let goal = goalClause(i) { text += " — " + goal }
        }
        return text + "."
    }

    private static func goalClause(_ i: DaySummaryInput) -> String? {
        guard i.goal > 0 else { return nil }
        let achieved = i.goalAchieved ?? i.focused
        if achieved >= i.goal { return "goal met" }
        let short = duration(i.goal - achieved)
        return i.isToday ? "**\(short)** to the \(duration(i.goal)) goal"
                         : "**\(short)** short of the \(duration(i.goal)) goal"
    }

    /// The longest session — its stretches and the breaks between them — and
    /// the one still running, if that is another.
    private static func sessions(_ i: DaySummaryInput) -> String? {
        guard let longest = i.sessions.max(by: { $0.worked < $1.worked }) else { return nil }
        let only = Set(i.sessions.map(\.threadID)).count == 1
        var text = only
            ? "That session, \(label(longest)), ran \(range(longest.start, longest.end))"
            : "The longest, \(label(longest)), ran \(range(longest.start, longest.end)) "
              + "for **\(duration(longest.worked))**"
        if longest.stretches > 1 {
            text += " in \(longest.stretches) stretches"
            let inside = i.rests.filter { longest.start < $0.start && $0.end <= longest.end }
            if !inside.isEmpty {
                text += inside.count == 1 ? " with one break" : " with \(inside.count) breaks"
                let named = inside.filter { $0.name != "Break" }.prefix(3)
                if !named.isEmpty {
                    text += " (" + named.map { "\($0.name) \(duration($0.length))" }
                        .joined(separator: ", ") + ")"
                }
            }
        }
        if longest.isRunning { text += ", and it's still running" }
        text += "."
        if let running = i.sessions.first(where: \.isRunning), running.id != longest.id {
            text += running.stretches > 1
                ? " \(label(running)) is still running — \(running.stretches) stretches "
                  + "since \(clock(running.start))."
                : " \(label(running)) is still running, since \(clock(running.start))."
        }
        return text
    }

    /// `**Deep work**`, or `**Deep work**, Refactor the parser` when the intent
    /// says more than the type.
    private static func label(_ session: DaySession) -> String {
        let type = session.workType.displayName
        let name = session.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name == type ? "**\(type)**" : "**\(type)**, \(name)"
    }

    private static func apps(_ i: DaySummaryInput) -> String? {
        guard let top = i.apps.first, top.total > 0 else { return nil }
        var text: String
        if i.apps.count == 1 {
            text = "All of the time was in **\(top.appName)**"
        } else {
            // "Most" is a claim about a share, so it is made only when the
            // share is one. A 38% leader is the busiest app, not most of
            // the time.
            let second = i.apps[1]
            let leads = "**\(top.appName)** (\(duration(top.total)), \(percent(top.share)))"
            if top.share > 0.5 {
                text = "Most of the time went to " + leads
                if second.total >= 60 {
                    text += ", then **\(second.appName)** (\(duration(second.total)), \(percent(second.share)))"
                }
            } else if second.total >= 60 {
                text = "The busiest apps were " + leads
                    + " and **\(second.appName)** (\(duration(second.total)), \(percent(second.share)))"
            } else {
                text = "The busiest app was " + leads
            }
            if i.apps.count > 2 { text += ", across \(i.apps.count) apps in all" }
        }
        if let peak = i.peak { text += "; the busiest hours were \(peak)" }
        return text + "."
    }

    private static func quality(_ i: DaySummaryInput) -> String? {
        var parts: [String] = []
        if !i.sessions.isEmpty, i.tracked > 0, i.insideSessionShare > 0 {
            var part = "**\(percent(i.insideSessionShare))** of the time at the Mac fell inside a session"
            if i.switchesPerStretch >= 1 {
                part += ", with about \(Int(i.switchesPerStretch.rounded())) app switches per stretch"
            }
            parts.append(part)
        }
        if i.workTypes.count > 1 {
            parts.append("by type, " + i.workTypes.prefix(3)
                .map { "\($0.workType.displayName) \(percent($0.share))" }
                .joined(separator: ", "))
        }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: "; ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    private static func comparison(_ i: DaySummaryInput, calendar: Calendar) -> String? {
        guard i.previousTracked > 0, i.tracked > 0 else { return nil }
        let against: String
        if i.isToday {
            against = "the whole of yesterday"
        } else if let previous = calendar.date(byAdding: .day, value: -1, to: i.day) {
            against = weekday(previous)
        } else {
            return nil
        }
        var clauses = [delta(i.tracked, i.previousTracked,
                             more: "more at the Mac", same: "the same time at the Mac")]
        if i.previousFocused > 0, i.focused > 0 {
            clauses.append(delta(i.focused, i.previousFocused,
                                 more: "more focused", same: "the same focused time"))
        }
        return "Against \(against): " + clauses.joined(separator: " and ") + "."
    }

    private static func delta(_ value: TimeInterval, _ baseline: TimeInterval,
                              more: String, same: String) -> String {
        let difference = value - baseline
        guard abs(difference) >= 60 else { return same }
        let phrase = difference > 0 ? more : more.replacingOccurrences(of: "more", with: "less")
        return "**\(duration(abs(difference)))** \(phrase)"
    }

    // MARK: - A week or a month

    static func period(_ i: PeriodSummaryInput, calendar: Calendar = .current) -> [String] {
        let unit = i.period == .week ? "week" : "month"
        guard i.tracked > 0 || i.focused > 0 else {
            return [i.containsToday ? "Nothing recorded yet this \(unit)."
                                    : "Nothing was recorded that \(unit)."]
        }
        var out: [String] = []
        var first = "\(i.containsToday ? "This" : "That") \(unit) you were at the Mac for "
            + "**\(duration(i.tracked))** across \(i.activeDays) of \(i.totalDays) days"
        if i.activeDays > 0 { first += " — **\(duration(i.averagePerActiveDay))** per active day" }
        if i.previousTracked > 0 {
            let difference = i.tracked - i.previousTracked
            first += abs(difference) >= 60
                ? ", **\(duration(abs(difference)))** \(difference > 0 ? "more" : "less") than the \(unit) before"
                : ", the same as the \(unit) before"
        }
        out.append(first + ".")

        if i.focused > 0 {
            var text = "You focused for **\(duration(i.focused))**"
            if i.sessions > 0 { text += i.sessions == 1 ? " in one session" : " in \(i.sessions) sessions" }
            if i.goal > 0 {
                text += i.goalMetDays > 0
                    ? ", meeting the \(duration(i.goal)) goal on \(i.goalMetDays == 1 ? "one day" : "\(i.goalMetDays) days")"
                    : ", without meeting the \(duration(i.goal)) goal on any day"
            }
            out.append(text + ".")
        }

        if let busiest = i.busiestDay, i.busiestTracked > 0 {
            var text = "The busiest day was **\(longDate(busiest))** (\(duration(i.busiestTracked)))"
            if let sitting = i.longestSitting, sitting.attended > 0 {
                text += "; the longest single sitting was **\(duration(sitting.attended))** "
                    + "in \(sitting.appName) on \(weekday(sitting.day))"
            }
            out.append(text + ".")
        }

        if let top = i.apps.first, top.total > 0 {
            let leads = "**\(top.name)** (\(duration(top.total)), \(percent(top.share)))"
            var text: String
            if i.apps.count == 1 {
                text = "All of the time was in **\(top.name)**"
            } else if top.share > 0.5 {
                text = "Most of the time went to " + leads
            } else {
                text = "The busiest app was " + leads
            }
            if i.apps.count > 1 {
                let second = i.apps[1]
                text += (top.share > 0.5 ? ", then " : " and ")
                    + "**\(second.name)** (\(duration(second.total)), \(percent(second.share)))"
            }
            if i.appCount > 2 { text += ", across \(i.appCount) apps in all" }
            if i.workTypes.count > 1 {
                text += "; session time by type, " + i.workTypes.prefix(3)
                    .map { "\($0.workType.displayName) \(percent($0.share))" }
                    .joined(separator: ", ")
            }
            out.append(text + ".")
        }
        return out
    }

    // MARK: - Plain text and phrasing

    /// The sentences as one paragraph without the bold marks.
    static func plain(_ sentences: [String]) -> String {
        sentences.joined(separator: " ").replacingOccurrences(of: "**", with: "")
    }

    /// `Core` cannot import the Design layer, so it carries the same phrasing
    /// as `Tokens.duration`: `2h 15m`, `4h`, `15m`.
    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        guard hours > 0 else { return "\(minutes)m" }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }

    private static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// A clock time whose one space is unbreakable, so a wrap can never leave
    /// "8:44" on one line and "am – 3:56 pm" on the next.
    private static func clock(_ date: Date) -> String {
        DateFormats.local("h:mm a").string(from: date).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    private static func range(_ start: Date, _ end: Date) -> String {
        "\(clock(start)) – \(clock(end))"
    }

    private static func weekday(_ date: Date) -> String { DateFormats.local("EEEE").string(from: date) }
    private static func longDate(_ date: Date) -> String { DateFormats.local("EEEE d MMMM").string(from: date) }
}
