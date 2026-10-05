import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func powerSummaries() -> [String] {
        let start = Date(timeIntervalSince1970: 1_788_600_000)
        let battery = [
            PowerObservation(timestamp: start, source: .battery, percentage: 78,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .battery,
                             percentage: 64, charging: .notCharging, boundary: .stretchEnded)
        ]
        let charging = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .charging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 81, charging: .charging, boundary: .stretchEnded)
        ]
        let pluggedIn = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 64, charging: .notCharging, boundary: .stretchEnded)
        ]
        let chargingTransition = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: start.addingTimeInterval(900), source: .external,
                             percentage: 64, charging: .charging, boundary: .sourceChanged),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 81, charging: .charging, boundary: .stretchEnded)
        ]
        let interval = DateInterval(start: start, duration: 1_800)
        var problems: [String] = []
        expect(PowerContextSummary.make(observations: battery, interval: interval)?.headline
               == "Using battery · 78% → 64%", "battery sequence was not rendered literally", &problems)
        expect(PowerContextSummary.make(observations: charging, interval: interval)?.headline
               == "Plugged in, charging · 64% → 81%",
               "actively charging evidence was not stated", &problems)
        expect(PowerContextSummary.make(observations: pluggedIn, interval: interval)?.headline
               == "Plugged in · 64% → 64%",
               "external power without charging was labelled as actively charging", &problems)
        let transition = PowerContextSummary.make(observations: chargingTransition, interval: interval)
        expect(transition?.headline == "Power changed",
               "a charging-state transition was flattened into one state", &problems)
        expect(transition?.detail?.contains("Charging started or stopped") == true,
               "a charging transition was not qualified beneath its headline", &problems)
        expect(transition?.detail?.contains("15m —") == false,
               "power detail enumerated observations instead of summarising them", &problems)
        expect((transition?.detail ?? "").contains("session energy") == false,
               "power detail implied session energy attribution", &problems)

        // The charger sits beside the plugged-in state; a change is a sentence.
        let chargingWatts = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .charging, boundary: .stretchStarted, adapterWatts: 96),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 81, charging: .charging, boundary: .stretchEnded, adapterWatts: 96)
        ]
        let watted = PowerContextSummary.make(observations: chargingWatts, interval: interval)
        expect(watted?.headline == "Plugged in, charging · 96 W · 64% → 81%",
               "the charger rating was not shown beside the charging state: \(watted?.headline ?? "nil")",
               &problems)
        expect(watted?.detail == nil, "one charger throughout was qualified: \(watted?.detail ?? "")", &problems)
        let swapped = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .charging, boundary: .stretchStarted, adapterWatts: 30),
            PowerObservation(timestamp: start.addingTimeInterval(900), source: .external,
                             percentage: 70, charging: .charging, adapterWatts: 96),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .external,
                             percentage: 81, charging: .charging, boundary: .stretchEnded, adapterWatts: 96)
        ]
        let swap = PowerContextSummary.make(observations: swapped, interval: interval)
        expect(swap?.headline == "Plugged in, charging · 96 W · 64% → 81%",
               "the headline did not name the charger in use now", &problems)
        expect(swap?.detail == "Charger changed during this session: 30 W, then 96 W.",
               "a charger change was not qualified: \(swap?.detail ?? "nil")", &problems)
        let unpluggedLater = [
            PowerObservation(timestamp: start, source: .external, percentage: 64,
                             charging: .charging, boundary: .stretchStarted, adapterWatts: 96),
            PowerObservation(timestamp: start.addingTimeInterval(1_800), source: .battery,
                             percentage: 81, charging: .notCharging, boundary: .stretchEnded)
        ]
        let mixed = PowerContextSummary.make(observations: unpluggedLater, interval: interval)
        expect(mixed?.headline == "Power changed"
               && mixed?.detail == "Power source changed during this session: mains power, battery. "
               + "Plugged into a 96 W charger for part of this session.",
               "a session that unplugged lost its charger: \(mixed?.detail ?? "nil")", &problems)
        let postCommitBoundary = PowerContextSummary.make(observations: [
            PowerObservation(timestamp: start, source: .battery, percentage: 78,
                             charging: .notCharging, boundary: .stretchStarted),
            PowerObservation(timestamp: interval.end.addingTimeInterval(1), source: .battery,
                             percentage: 64, charging: .notCharging, boundary: .stretchEnded),
            PowerObservation(timestamp: interval.end.addingTimeInterval(1), source: .external,
                             percentage: 64, charging: .notCharging, boundary: .sourceChanged)
        ], interval: interval)
        expect(postCommitBoundary?.headline == "Using battery · 78% → 64%",
               "summary grace admitted a post-interval source change", &problems)
        // Each report row shows the state it ended on: the latest reading at
        // or before its end, never one taken after it.
        expect(PowerReading.at(start.addingTimeInterval(-1), in: chargingTransition) == nil,
               "a row before any reading claimed a power state", &problems)
        let early = PowerReading.at(start.addingTimeInterval(600), in: chargingTransition)
        expect(early?.symbolName == "powerplug" && early?.level == "64%",
               "a row before charging began did not read plugged in: \(early?.spoken ?? "nil")", &problems)
        let late = PowerReading.at(start.addingTimeInterval(1_000), in: chargingTransition)
        expect(late?.symbolName == "bolt.fill" && late?.spoken == "Charging, 64%",
               "a row after charging began did not read charging: \(late?.spoken ?? "nil")", &problems)
        let onBattery = PowerReading.at(start.addingTimeInterval(1_800), in: battery)
        expect(onBattery?.symbolName == "battery.75percent" && onBattery?.spoken == "On battery, 64%",
               "a battery row did not show its level: \(onBattery?.spoken ?? "nil")", &problems)

        // A run of visits at one level says it once; a change, up or down,
        // says it again. A gap between visits neither shows nor resets it.
        func visit(_ from: TimeInterval, _ to: TimeInterval, app: String? = "com.example.app") -> RecordedActivity.Interval {
            RecordedActivity.Interval(start: start.addingTimeInterval(from), end: start.addingTimeInterval(to),
                                      bundleID: app, appName: app, colourIndex: nil)
        }
        let levels = [92, 91, 91, 92].enumerated().map { index, level in
            PowerObservation(timestamp: start.addingTimeInterval(Double(index) * 600), source: .battery,
                             percentage: Double(level), charging: .notCharging)
        }
        let visits = [visit(0, 300), visit(600, 700), visit(700, 750, app: nil),
                      visit(1_300, 1_400), visit(1_800, 1_900)]
        let shown = PowerReading.changes(across: visits.shuffled(), in: levels)
        let shownLevels = visits.map { shown[$0.id]?.level ?? "-" }
        expect(shownLevels == ["92%", "91%", "-", "-", "92%"],
               "power marks did not show only the changes: \(shownLevels)", &problems)
        return problems
    }

    static func partialPowerEvidence() -> [String] {
        let start = Date(timeIntervalSince1970: 1_788_700_000)
        let invalid = PowerObservation.normalised(timestamp: start, source: .battery,
            currentCapacity: 64, maximumCapacity: 0, charging: .unknown,
            boundary: .stretchStarted)
        let nonFinite = PowerObservation.normalised(timestamp: start, source: .battery,
            currentCapacity: .infinity, maximumCapacity: 100, charging: .unknown)
        let observations = [
            invalid,
            PowerObservation(timestamp: start.addingTimeInterval(300), source: .unknown,
                             percentage: nil, charging: .unknown, boundary: .coverageResumed),
            PowerObservation(timestamp: start.addingTimeInterval(600), source: .ups,
                             percentage: nil, charging: .notCharging, boundary: .sourceChanged)
        ]
        let summary = PowerContextSummary.make(
            observations: observations, interval: DateInterval(start: start, duration: 900))
        var problems: [String] = []
        expect(invalid.percentage == nil && nonFinite.percentage == nil,
               "invalid capacity produced an invented percentage", &problems)
        expect(summary?.headline == "Power changed",
               "mixed or partial sources claimed one continuous source", &problems)
        expect(summary?.detail == "Power source changed during this session: "
               + "battery, an unrecorded source, UPS.",
               "the sources behind a changed headline were not named in order", &problems)
        // A stretch begun after an Away answer is tagged "coverage resumed" at
        // 0m; a sentence built on that tag claimed a gap that did not exist.
        let resumedAtStart = PowerContextSummary.make(observations: [
            PowerObservation(timestamp: start, source: .battery, percentage: 64,
                             charging: .notCharging, boundary: .coverageResumed),
            PowerObservation(timestamp: start.addingTimeInterval(5), source: .battery,
                             percentage: 64, charging: .notCharging, boundary: .sourceChanged),
            PowerObservation(timestamp: start.addingTimeInterval(90), source: .battery,
                             percentage: 64, charging: .notCharging, boundary: .sourceChanged)
        ], interval: DateInterval(start: start, duration: 93))
        expect(resumedAtStart?.headline == "Using battery · 64% → 64%" && resumedAtStart?.detail == nil,
               "an uninterrupted battery stretch carried a qualification: "
               + "\(resumedAtStart?.detail ?? "nil")", &problems)
        return problems
    }

    static func oldSessionHasNoPowerFallback() -> [String] {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_600_000_000), duration: 600)
        return PowerContextSummary.make(observations: [], interval: interval) == nil
            ? [] : ["an old session without metadata displayed a current-system power fallback"]
    }
}
