import Foundation

/// The final fix wave of phase 2: the guard's Settings line says when it will
/// really come, Flow offers (and credits) its break in whole minutes, a system
/// time-zone change leaves the process-wide zone alone, and a stored work
/// length belongs only to the notice it was written with.
enum BreakFinalFixChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The guard's setting names the time it will really come", guardComesAfterIsTrue),
        ("Flow offers its break in whole minutes and credits a gap by the same figure", flowInWholeMinutes),
        ("A system time-zone change does not move the process-wide zone", zoneChangeLeavesCalendarAlone),
        ("A stored work length belongs only to the notice it was written with", workLengthTiedToNotice),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    /// A model over its own in-memory preferences, removed after `body`.
    private static func withModel(_ body: (SettingsModel, inout [String]) -> Void) -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-breakfinal-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        let model = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                  onChange: {}, onTrackingChanged: { _ in })
        body(model, &problems)
        return problems
    }

    // MARK: - The guard's setting

    private static func guardComesAfterIsTrue() -> [String] {
        withModel { model, problems in
            let base = "One clearer prompt after an unbroken stretch, whatever the rhythm."
            func set(_ preset: BreakPreset, custom: CustomRhythm = CustomRhythm(), guardMinutes: Int) {
                model.breakRhythm = preset
                model.customRhythm = custom
                model.breakGuardMinutes = guardMinutes
                model.breakGuardEnabled = true
            }
            /// What the row says, built the way the view builds it.
            var detail: String {
                SettingsGroups.guardDetail(pickedMinutes: model.breakGuardMinutes, comesAfter: model.guardComesAfter)
            }

            set(.steady, guardMinutes: 60)
            expect(model.guardComesAfter == 65 * 60,
                   "Steady with the guard at 60 comes at 65, got \(String(describing: model.guardComesAfter))",
                   &problems)
            expect(detail == base + " With your usual rhythm it comes after 1h 5m.",
                   "and says so, got \"\(detail)\"", &problems)

            set(.deepWork, guardMinutes: 90)
            expect(model.guardComesAfter == 105 * 60,
                   "Deep work with the guard at 90 comes at 105, got \(String(describing: model.guardComesAfter))",
                   &problems)
            expect(detail == base + " With your usual rhythm it comes after 1h 45m.",
                   "and says so, got \"\(detail)\"", &problems)

            set(.custom, custom: CustomRhythm(workMinutes: 120), guardMinutes: 90)
            expect(model.guardComesAfter == 90 * 60,
                   "a guard shorter than Custom's 120-minute block still comes first, at 90, got "
                   + "\(String(describing: model.guardComesAfter))", &problems)
            expect(detail == base, "and adds nothing, got \"\(detail)\"", &problems)

            set(.steady, guardMinutes: 90)
            expect(model.guardComesAfter == 90 * 60 && detail == base,
                   "the default guard under Steady is the 90 shown and adds nothing", &problems)
            set(.flow, guardMinutes: 60)
            expect(model.guardComesAfter == 60 * 60 && detail == base,
                   "Flow has no block to wait for, so the guard is the 60 shown", &problems)

            model.breakGuardEnabled = false
            expect(model.guardComesAfter == nil, "an off guard comes at no time", &problems)
            expect(detail == base, "and the row adds nothing, got \"\(detail)\"", &problems)
        }
    }

    // MARK: - Flow in whole minutes

    private static func flowInWholeMinutes() -> [String] {
        var problems: [String] = []
        expect(BreakRhythm.flowSuggestion(after: 1_502) == 300, "25m02s is a fifth of 5 minutes, got "
               + "\(BreakRhythm.flowSuggestion(after: 1_502))", &problems)
        expect(BreakRhythm.flowSuggestion(after: 2_833) == 540, "47m13s is 566.6 s, which offers 9 minutes, got "
               + "\(BreakRhythm.flowSuggestion(after: 2_833))", &problems)
        expect(BreakRhythm.flowSuggestion(after: 2_850) == 600, "47m30s is 570 s, a half, which rounds up to 10, got "
               + "\(BreakRhythm.flowSuggestion(after: 2_850))", &problems)
        expect(BreakRhythm.flowSuggestion(after: 1_800) == 360 && BreakRhythm.flowSuggestion(after: 3_600) == 720
               && BreakRhythm.flowSuggestion(after: 600) == 300 && BreakRhythm.flowSuggestion(after: 9_000) == 1_200,
               "figures that were whole already are unchanged", &problems)
        let fractional = stride(from: -100.0, through: 12_000.0, by: 7.3)
            .filter { BreakRhythm.flowSuggestion(after: $0).truncatingRemainder(dividingBy: 60) != 0 }
        expect(fractional.isEmpty, "every suggestion is whole minutes, not \(fractional.prefix(3))", &problems)

        // The credit for a gap is the same figure as the offer: after the
        // 47m13s that offers 9 minutes, a rest of 9 minutes counts.
        let worked = AppUsageSession(bundleID: "com.a", appName: "Alpha", start: SelfTest.base,
                                     end: SelfTest.base.addingTimeInterval(2_833))
        let credited = BreakCycles.flowRun([worked], now: worked.end.addingTimeInterval(540))
        expect(credited.seconds == 0 && credited.start == nil,
               "a rest of the 9 minutes offered ends the run, got \(credited.seconds) s", &problems)
        let short = BreakCycles.flowRun([worked], now: worked.end.addingTimeInterval(539))
        expect(short.seconds == 2_833, "a second short of it does not, got \(short.seconds) s", &problems)
        return problems
    }

    // MARK: - The process-wide zone

    /// `SessionArchive` keeps the calendar it captured at launch. A reset on a
    /// zone change moved every `Calendar.current` under it, so two "today"
    /// figures in one store disagreed. The new zone is staged in `TZ`, which
    /// the system re-reads only when something resets it.
    private static func zoneChangeLeavesCalendarAlone() -> [String] {
        withModel { model, problems in
            let before = TimeZone.current.identifier
            let original = getenv("TZ").map { String(cString: $0) }
            setenv("TZ", before == "Pacific/Kiritimati" ? "Pacific/Auckland" : "Pacific/Kiritimati", 1)
            defer {
                if let original { setenv("TZ", original, 1) } else { unsetenv("TZ") }
                NSTimeZone.resetSystemTimeZone()
            }
            var published = 0
            let token = model.objectWillChange.sink { published += 1 }
            defer { token.cancel() }
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
            expect(published == 1, "the model still republishes once, got \(published)", &problems)
            expect(TimeZone.current.identifier == before && Calendar.current.timeZone.identifier == before,
                   "the zone stays \(before), got \(TimeZone.current.identifier) and "
                   + "\(Calendar.current.timeZone.identifier)", &problems)
        }
    }

    // MARK: - The notice's work length

    private static func workLengthTiedToNotice() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-breakfinal-notice-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        let store = PersistenceStore(defaults: defaults)

        let phaseTwo = BreakNotice(tier: .cognitive, at: at(52), work: 3_000)
        store.lastBreakNotice = phaseTwo
        expect(PersistenceStore(defaults: defaults).lastBreakNotice == phaseTwo,
               "a phase 2 notice round-trips its work length", &problems)

        // A phase-1 build rewrites the notice and its tier and nothing else.
        defaults.set(at(131).timeIntervalSince1970, forKey: "fc.lastBreakNotice")
        defaults.set(BreakTier.ultradian.rawValue, forKey: "fc.lastBreakTier")
        let phaseOne = PersistenceStore(defaults: defaults).lastBreakNotice
        expect(phaseOne?.tier == .ultradian && phaseOne?.at == at(131),
               "the phase-1 notice itself is read", &problems)
        expect(phaseOne?.work == nil, "its work length is unknown, not the earlier notice's 3000, got "
               + "\(String(describing: phaseOne?.work))", &problems)

        let later = BreakNotice(tier: .ultradian, at: at(200), work: 7_200)
        store.lastBreakNotice = later
        expect(PersistenceStore(defaults: defaults).lastBreakNotice == later,
               "the next phase 2 notice carries its own length again", &problems)
        store.lastBreakNotice = BreakNotice(tier: .micro, at: at(220))
        expect(defaults.object(forKey: "fc.lastBreakWorkAt") == nil
               && PersistenceStore(defaults: defaults).lastBreakNotice?.work == nil,
               "a notice without a length leaves no stamp behind", &problems)
        store.lastBreakNotice = later
        store.removeAll()
        expect(defaults.object(forKey: "fc.lastBreakWork") == nil && defaults.object(forKey: "fc.lastBreakWorkAt") == nil,
               "erasing everything clears the length and its stamp", &problems)
        return problems
    }
}
