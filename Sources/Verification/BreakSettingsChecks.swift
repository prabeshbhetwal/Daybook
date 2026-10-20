import Foundation

/// The rhythm settings in preferences: each reads through to the old reminder
/// switches until it is first written, then holds its own value.
enum BreakSettingsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Each old tier switch carries over on its own", eachTierMapsAlone),
        ("A carried-over setting stays once it is changed", writtenSettingWins),
        ("A Mac that never changed a tier gets the default rhythm", freshDefaults),
        ("An unreadable schedule is kept aside and reads as the default", unreadableScheduleKept),
        ("The guard stays between 60 and 180 minutes", guardMinutesClamped),
        ("End a paused automatic session after keeps its stored value", pauseLimitKeepsItsKey),
        ("Erasing everything clears the rhythm settings too", eraseClearsRhythm),
    ]

    private static let oldKey = "fc.breakTiersDisabled"

    /// Runs `body` on a store over its own in-memory preferences, removed after.
    private static func withStore(_ body: (PersistenceStore, UserDefaults, inout [String]) -> Void) -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-breaksettings-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        body(PersistenceStore(defaults: defaults), defaults, &problems)
        return problems
    }

    private static func eachTierMapsAlone() -> [String] {
        withStore { store, defaults, problems in
            let tiers: [BreakTier] = [.micro, .cognitive, .ultradian]
            for mask in 0..<(1 << tiers.count) {
                let off = Set(tiers.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
                defaults.set(off.map(\.rawValue).sorted(), forKey: oldKey)
                let label = "with \(off.map(\.rawValue).sorted()) off"
                expect(store.breakEyes == !off.contains(.micro), "Eyes \(label)", &problems)
                expect(store.breakGuardEnabled == !off.contains(.ultradian), "the guard \(label)", &problems)
                expect(store.breakSchedule.weekdays
                        == Array(repeating: off.contains(.cognitive) ? BreakDayPlan.off : .usual, count: 7),
                       "the weekdays \(label)", &problems)
                expect(store.breakSchedule.rhythm == .steady && store.breakGuardMinutes == 90,
                       "the rhythm stays Steady and the guard 90 \(label)", &problems)
            }
        }
    }

    private static func writtenSettingWins() -> [String] {
        withStore { store, defaults, problems in
            defaults.set([BreakTier.micro.rawValue], forKey: oldKey)
            expect(!store.breakEyes, "Eyes starts off with the micro tier", &problems)
            store.breakEyes = true
            defaults.set([0, 1, 2], forKey: oldKey)
            expect(store.breakEyes, "Eyes stays on once written", &problems)
            expect(!store.breakGuardEnabled, "the guard, not yet written, still follows the old key", &problems)
            expect(store.breakSchedule.weekdays == Array(repeating: BreakDayPlan.off, count: 7),
                   "the schedule, not yet written, still follows the old key", &problems)

            var schedule = BreakSchedule()
            schedule.rhythm = .pomodoro
            store.breakSchedule = schedule
            store.breakGuardEnabled = true
            expect(store.breakSchedule.rhythm == .pomodoro && store.breakSchedule.weekdays == schedule.weekdays,
                   "a written schedule reads back as written, not from the old key", &problems)
            expect(store.breakGuardEnabled, "the guard stays on once written", &problems)
            expect(defaults.array(forKey: oldKey) as? [Int] == [0, 1, 2],
                   "the old key is never written", &problems)
        }
    }

    private static func freshDefaults() -> [String] {
        withStore { store, _, problems in
            expect(store.breakSchedule == BreakSchedule(), "the default schedule", &problems)
            expect(store.breakEyes && store.breakGuardEnabled, "Eyes and the guard are on", &problems)
            expect(store.breakGuardMinutes == 90, "the guard waits 90 minutes", &problems)
            expect(store.legacyDisabledBreakTiers.isEmpty, "no tier was off", &problems)
        }
    }

    private static func unreadableScheduleKept() -> [String] {
        withStore { store, defaults, problems in
            let bytes = Data("not json".utf8)
            defaults.set(bytes, forKey: "fc.breakSchedule")
            expect(store.breakSchedule == BreakSchedule(), "an unreadable schedule reads as the default", &problems)
            let aside = defaults.dictionaryRepresentation()
                .first { $0.key.hasPrefix("fc.breakSchedule.unreadable.") }
            expect(aside?.value as? Data == bytes, "the unreadable bytes are kept aside", &problems)
        }
    }

    private static func guardMinutesClamped() -> [String] {
        withStore { store, defaults, problems in
            store.breakGuardMinutes = 30
            expect(store.breakGuardMinutes == 60, "30 is raised to 60", &problems)
            store.breakGuardMinutes = 500
            expect(store.breakGuardMinutes == 180, "500 is cut to 180", &problems)
            store.breakGuardMinutes = 120
            expect(store.breakGuardMinutes == 120, "120 is kept", &problems)
            defaults.set(45, forKey: "fc.breakGuardMinutes")
            expect(store.breakGuardMinutes == 60, "a hand-stored 45 reads as 60", &problems)
        }
    }

    private static func pauseLimitKeepsItsKey() -> [String] {
        withStore { store, defaults, problems in
            defaults.set(1_200.0, forKey: "fc.breakLength")
            expect(store.autoSessionPauseLimit == 1_200, "the stored value is read", &problems)
            store.autoSessionPauseLimit = 1_800
            expect(defaults.double(forKey: "fc.breakLength") == 1_800, "a write lands under the old key", &problems)
        }
    }

    private static func eraseClearsRhythm() -> [String] {
        withStore { store, defaults, problems in
            store.breakEyes = false
            store.breakGuardEnabled = false
            store.breakGuardMinutes = 120
            store.breakSchedule = BreakSchedule()
            defaults.set(Data("not json".utf8), forKey: "fc.breakSchedule")
            _ = store.breakSchedule
            store.removeAll()
            let left = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("fc.break") }
            expect(left.isEmpty, "nothing is left after erasing: \(left)", &problems)
        }
    }
}
