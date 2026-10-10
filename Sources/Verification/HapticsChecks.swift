import Foundation

/// Haptic pulses: which pulse each moment plays, and the HID++ bytes that ask
/// an MX Master 4 to play one. None of it needs the mouse.
enum HapticsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("HID++ requests are 20-byte long reports addressed to the mouse", requestBytes),
        ("HID++ replies are matched to their request and errors are told apart", replyMatching),
        ("The mouse's haptic switch is one bit of its configuration byte", configurationBit),
        ("The waveform mask says which pulses the mouse offers", capabilityMask),
        ("Each moment has its pulse, and the goal reward gets its own", momentTable),
        ("Haptic feedback is off until turned on, and the switch is saved", settingWritesThrough),
    ]

    private static func padded(_ bytes: [UInt8]) -> [UInt8] {
        bytes + [UInt8](repeating: 0, count: HIDPP.reportLength - bytes.count)
    }

    private static func requestBytes() -> [String] {
        var problems: [String] = []
        let getFeature = HIDPP.request(feature: 0, function: 0, softwareID: 0x0B,
                                       parameters: [0x19, 0xB0, 0])
        expect(getFeature == padded([0x11, 0xFF, 0x00, 0x0B, 0x19, 0xB0, 0x00]),
               "getFeature(0x19B0) bytes, got \(getFeature)", &problems)
        let play = HIDPP.request(feature: 0x0B, function: 4, softwareID: 0x0B, parameters: [7, 0, 0])
        expect(Array(play[2...3]) == [0x0B, 0x4B],
               "play addresses feature 0x0B function 4, got \(Array(play[2...3]))", &problems)
        for request in [getFeature, play, HIDPP.request(feature: 0x0B, function: 1, softwareID: 0x0B)] {
            expect(request.count == 20, "a long report is 20 bytes, got \(request.count)", &problems)
        }
        return problems
    }

    private static func replyMatching() -> [String] {
        var problems: [String] = []
        let request = HIDPP.request(feature: 0x0B, function: 1, softwareID: 0x0B)
        let answer = padded([0x11, 0xFF, 0x0B, 0x1B, 3, 25])
        let cases: [(String, [UInt8], HIDPP.Reply)] = [
            ("answer", answer, .answer(Array(answer[4...]))),
            ("0x8F error", padded([0x11, 0xFF, 0x8F, 0x0B, 0x1B, 0x05]), .error(0x05)),
            ("0xFF error", padded([0x11, 0xFF, 0xFF, 0x0B, 0x1B, 0x02]), .error(0x02)),
            ("another client's software id", padded([0x11, 0xFF, 0x0B, 0x1C, 3, 25]), .unrelated),
            ("a mouse movement report", [0x02, 0x00, 0x05, 0x00, 0xFE, 0xFF, 0x00], .unrelated),
            ("a short report", [0x11, 0xFF, 0x0B], .unrelated),
        ]
        for (label, report, expected) in cases {
            let reply = HIDPP.reply(report, to: request)
            expect(reply == expected, "\(label) should be \(expected), got \(reply)", &problems)
        }
        return problems
    }

    private static func configurationBit() -> [String] {
        var problems: [String] = []
        let caps = HapticCapabilities(payload: [0, 0, 0, 0, 0x08, 0x00, 0x7F, 0xFF])
        guard let on = HapticConfiguration(payload: [3, 25]),
              let off = HapticConfiguration(payload: [2, 25]),
              let silent = HapticConfiguration(payload: [1, 0]), let caps else {
            return ["configuration and capability payloads should parse"]
        }
        expect(on.isEnabled && on.intensity == 25,
               "byte 3 with intensity 25 is on at 25, got \(on)", &problems)
        expect(!off.isEnabled, "byte 2 has bit 0 clear, so haptics are off, got \(off)", &problems)
        expect(!MouseHaptics.playable(configuration: silent, capabilities: caps, waveform: 7),
               "intensity 0 is not playable", &problems)
        expect(HapticConfiguration(payload: [3]) == nil, "a one-byte payload is not a configuration",
               &problems)
        return problems
    }

    private static func capabilityMask() -> [String] {
        var problems: [String] = []
        guard let caps = HapticCapabilities(payload: [0, 0, 0, 0, 0x08, 0x00, 0x7F, 0xFF]),
              let on = HapticConfiguration(payload: [3, 25]) else {
            return ["the tested mouse's payloads should parse"]
        }
        expect(caps.waveformMask == 0x0800_7FFF, "mask is bytes 4–7 big-endian, got \(caps.waveformMask)",
               &problems)
        let offered = (0...14).filter { caps.supports(UInt8($0)) }
        expect(offered.count == 15, "waveforms 0–14 are offered, got \(offered)", &problems)
        expect(!caps.supports(15), "waveform 15 is not offered", &problems)
        expect(!caps.supports(40), "a waveform past the mask's 32 bits is not offered", &problems)
        expect(HapticCapabilities(payload: [0, 0, 0]) == nil, "a short payload has no mask", &problems)
        expect(MouseHaptics.playable(configuration: on, capabilities: caps, waveform: 7),
               "completed (7) plays on the tested mouse", &problems)
        expect(!MouseHaptics.playable(configuration: on, capabilities: caps, waveform: 15),
               "a waveform outside the mask does not play", &problems)
        return problems
    }

    private static func momentTable() -> [String] {
        var problems: [String] = []
        let expected: [(HapticMoment, UInt8, TrackpadPattern)] = [
            (.breakDue, 5, .generic), (.awayQuestion, 5, .generic), (.goalReached, 7, .generic),
            (.notice, 1, .generic), (.sessionToggled, 1, .generic),
            (.zoomStep, 4, .levelChange), (.tileDropped, 4, .alignment),
        ]
        expect(expected.count == HapticMoment.allCases.count, "every moment is in the table", &problems)
        for (moment, waveform, pattern) in expected {
            expect(moment.mouseWaveform == waveform,
                   "\(moment) plays waveform \(waveform), got \(moment.mouseWaveform)", &problems)
            expect(moment.trackpadPattern == pattern,
                   "\(moment) plays \(pattern) on the trackpad, got \(moment.trackpadPattern)", &problems)
        }
        for kind in RewardKind.allCases {
            let moment = HapticMoment(reward: kind)
            let wanted: HapticMoment = kind == .goalReached ? .goalReached : .notice
            expect(moment == wanted, "reward \(kind) is \(wanted), got \(moment)", &problems)
        }
        return problems
    }

    private static func settingWritesThrough() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let suite = "fc-selftest-haptics-\(UUID().uuidString)"
            defer { MemoryDefaults.remove(named: suite) }
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no memory suite"] }
            let store = PersistenceStore(defaults: defaults)
            expect(store.hapticsEnabled == false, "haptic feedback starts off", &problems)
            var changes = 0
            let apps = InstalledAppCatalog(discoverStandard: { [] }, discoverSpotlight: { [] },
                                           observed: { [] })
            let model = SettingsModel(store: store, isTrackingEnabled: true,
                                      onChange: { changes += 1 }, onTrackingChanged: { _ in },
                                      installedAppCatalog: apps)
            model.hapticsEnabled = true
            expect(store.hapticsEnabled, "turning it on is saved", &problems)
            expect(changes == 1, "one change notification for the write, got \(changes)", &problems)
            store.removeAll()
            expect(store.hapticsEnabled == false, "removeAll clears it back to off", &problems)
            expect(SettingsControlKey.haptics.modelKeyPath == \SettingsModel.hapticsEnabled,
                   "Settings search reaches the switch", &problems)
            return problems
        }
    }
}
