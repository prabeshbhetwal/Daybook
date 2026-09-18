import Foundation

/// The Awards read model. It composes facts the app already holds — the day
/// index History builds, the same goal credit Today shows, and the archive's
/// own streak walks — so an award can never claim more than the record proves.
extension SessionStore {

    /// Rebuilt from the History index rather than from a separate walk, so a
    /// day that counts here counts identically in Review and Today.
    var awardFacts: AwardFacts {
        let calendar = Calendar.current
        let snapshot = effectiveUsageSnapshot
        var credit: [Date: TimeInterval] = [:]
        var totalFocused: TimeInterval = 0
        for day in historyDays {
            let key = calendar.startOfDay(for: day.date)
            credit[key] = focusedActiveSeconds(on: key, usageSnapshot: snapshot)
            totalFocused += day.focused
        }

        // The longest single stretch on record. A record is one stretch; a
        // session resumed after a break is several, and this award is
        // deliberately about the unbroken one.
        var longest: (seconds: TimeInterval, day: Date)?
        for record in engine.archive.records where record.workType.countsAsFocus {
            let seconds = record.workSeconds
            if seconds > (longest?.seconds ?? 0) {
                longest = (seconds, calendar.startOfDay(for: record.start))
            }
        }

        return AwardFacts(
            goal: engine.store.dailyGoal,
            goalCreditByDay: credit,
            longestStretch: longest,
            activeDays: historyDays.filter { $0.tracked > 0 }.count,
            totalFocused: totalFocused,
            currentStreak: streak,
            bestStreak: engine.archive.bestStreak())
    }

    var awards: [Award] { Awards.all(from: awardFacts) }

    /// The recent run of days behind the streak figure, oldest first. Each day
    /// says whether it cleared the streak minimum, so the row of marks is
    /// evidence rather than decoration.
    func streakDays(limit: Int = 14) -> [(day: Date, met: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<max(1, limit)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let focused = engine.archive.workSeconds(on: day)
            return (day, focused >= engine.store.streakMinimum)
        }
    }
}
