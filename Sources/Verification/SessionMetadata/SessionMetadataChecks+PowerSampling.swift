import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func factualBoundarySampling() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []

            // Ordinary start/end are observed at the contemporaneous injected clock.
            do {
                let folder = directory(), suite = "com.prabesh.daybook.metadata.boundary.normal.\(UUID())"
                defer { try? FileManager.default.removeItem(at: folder); MemoryDefaults.remove(named: suite) }
                let clock = TestClock(Date(timeIntervalSince1970: 1_788_610_000))
                let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                    sample: PowerObservation(timestamp: clock.value, source: .battery,
                        percentage: 78, charging: .notCharging))
                fixture.1.start(workType: .deepWork, intent: "Normal")
                fixture.0.refresh()
                let id = fixture.1.activeRecordID
                clock.advance(600)
                fixture.0.stop()
                let power = fixture.2.metadata(for: id)?.power ?? []
                expect(power.first?.timestamp == Date(timeIntervalSince1970: 1_788_610_000)
                       && power.first?.boundary == .stretchStarted,
                       "contemporaneous start was not sampled at the injected clock", &problems)
                expect(power.last?.timestamp == clock.value && power.last?.boundary == .stretchEnded,
                       "contemporaneous end was not sampled at the injected clock", &problems)
            }

            // A restored old stretch begins coverage now; it does not fabricate its old start.
            do {
                let folder = directory(), sourceSuite = "com.prabesh.daybook.metadata.boundary.restore.source.\(UUID())"
                let reloadSuite = sourceSuite + ".reload"
                defer {
                    try? FileManager.default.removeItem(at: folder)
                    MemoryDefaults.remove(named: sourceSuite)
                    MemoryDefaults.remove(named: reloadSuite)
                }
                let old = Date(timeIntervalSince1970: 1_788_620_000)
                let sourceClock = TestClock(old)
                let source = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: sourceSuite)!),
                    archive: SessionArchive(directory: folder, now: { sourceClock.value }),
                    schedulesDwell: false, now: { sourceClock.value })
                source.start(workType: .deepWork, intent: "Restored")
                var snapshot = source.snapshot()
                let clock = TestClock(old.addingTimeInterval(3_600))
                snapshot.savedAt = clock.value
                let fixture = makePowerFixture(clock, folder: folder, suite: reloadSuite,
                    sample: PowerObservation(timestamp: clock.value, source: .battery,
                        percentage: 72, charging: .notCharging))
                fixture.1.restore(from: snapshot)
                fixture.0.refresh()
                let power = fixture.2.metadata(for: fixture.1.activeRecordID)?.power ?? []
                expect(power.count == 1 && power[0].timestamp == clock.value
                       && power[0].boundary == .coverageResumed,
                       "restored session backfilled a historical start observation", &problems)
            }

            // Automatic backdating samples now as partial coverage, never at backdatedTo.
            do {
                let folder = directory(), suite = "com.prabesh.daybook.metadata.boundary.auto.\(UUID())"
                defer { try? FileManager.default.removeItem(at: folder); MemoryDefaults.remove(named: suite) }
                let clock = TestClock(Date(timeIntervalSince1970: 1_788_630_000))
                let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                    sample: PowerObservation(timestamp: clock.value, source: .external,
                        percentage: 64, charging: .charging))
                let backdated = clock.value.addingTimeInterval(-900)
                fixture.0.startAutomatically(workType: .deepWork, name: "Automatic",
                                             backdatedTo: backdated, because: "Observed")
                let id = fixture.1.activeRecordID
                let power = fixture.2.metadata(for: id)?.power ?? []
                expect(power.count == 1 && power[0].timestamp == clock.value
                       && power[0].boundary == .coverageResumed,
                       "automatic backdate stamped current hardware at backdatedTo", &problems)

                // A detector ending late must not manufacture a sample at its old record end.
                clock.advance(600)
                let delayedEnd = clock.value.addingTimeInterval(-300)
                _ = fixture.1.stop(endingAt: delayedEnd)
                fixture.0.refresh()
                let ended = fixture.2.metadata(for: id)?.power ?? []
                expect(!ended.contains(where: { $0.boundary == .stretchEnded }),
                       "delayed automatic end manufactured a historical end sample", &problems)
                expect(ended.allSatisfy { $0.timestamp != delayedEnd },
                       "delayed automatic end stored the archived record timestamp as observation time", &problems)
            }
            return problems
        }
    }

    static func awayObservationReassignment() -> [String] {
        MainActor.assumeIsolated {
            var allProblems: [String] = []
            let decisions: [(UserDecision, String)] = [
                (.continueSession, "Continue"), (.tookBreak, "Break"), (.resetTimer, "Reset")
            ]
            for (decision, label) in decisions {
                let folder = directory()
                let suite = "com.prabesh.daybook.metadata.boundary.away.\(label).\(UUID())"
                defer {
                    try? FileManager.default.removeItem(at: folder)
                    MemoryDefaults.remove(named: suite)
                }
                let clock = TestClock(Date(timeIntervalSince1970: 1_788_640_000))
                let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                    sample: PowerObservation(timestamp: clock.value, source: .battery,
                        percentage: 78, charging: .notCharging))
                var problems: [String] = []
                fixture.1.start(workType: .deepWork, intent: "Away split")
                fixture.0.refresh()
                let predecessor = fixture.1.activeRecordID
                clock.advance(600)
                fixture.1.transition(on: .awayBegan(trigger: .screenLock))
                clock.advance(1_200)
                fixture.1.transition(on: .awayEnded)
                let returnedAt = clock.value
                fixture.3.handler?(PowerObservation(timestamp: returnedAt, source: .external,
                    percentage: 64, charging: .notCharging, boundary: .sourceChanged))
                expect(fixture.2.metadata(for: predecessor)?.power.contains(where: {
                    $0.timestamp == returnedAt && $0.boundary == .sourceChanged
                }) == true, "post-return event was not initially bound to the open predecessor", &problems)

                clock.advance(300)
                expect(fixture.0.resolve(decision), "Away split fixture could not save \(label)", &problems)
                let successor = fixture.1.activeRecordID
                let predecessorPower = fixture.2.metadata(for: predecessor)?.power ?? []
                let successorPower = fixture.2.metadata(for: successor)?.power ?? []
                expect(!predecessorPower.contains(where: { $0.timestamp >= returnedAt }),
                       "Away \(label) left post-return observations on the closed predecessor", &problems)
                expect(successorPower.contains(where: {
                    $0.timestamp == returnedAt && $0.boundary == .sourceChanged
                }), "Away \(label) did not atomically move post-return evidence", &problems)
                // The process sampled straight through the split — the moved
                // post-return event proves it — so the successor's first own
                // sample is a sample, not a resume.
                expect(successorPower.contains(where: {
                    $0.timestamp == clock.value && $0.boundary == nil
                }), "Away \(label) successor was not sampled at answer time", &problems)
                expect(!successorPower.contains(where: { $0.boundary == .coverageResumed }),
                       "Away \(label) successor claimed a coverage gap the process sampled through",
                       &problems)
                expect(!predecessorPower.contains(where: { $0.boundary == .stretchEnded })
                       && !successorPower.contains(where: { $0.boundary == .stretchStarted }),
                       "Away \(label) fabricated historical boundaries", &problems)
                fixture.3.handler?(PowerObservation(timestamp: clock.value.addingTimeInterval(1),
                    source: .external, percentage: 63, charging: .notCharging,
                    boundary: .sourceChanged))
                expect(fixture.2.metadata(for: successor)?.power.last?.percentage == 63,
                       "post-\(label) callback attached to the stale predecessor", &problems)
                allProblems.append(contentsOf: problems)
            }
            return allProblems
        }
    }

    /// The unpause branch wrote "coverage resumed" after every pause. The
    /// monitor keeps sampling through a pause; only sleep stops it, and the
    /// store hears about sleep from the coordinator's wake notice.
    static func pauseResumeCoverage() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.boundary.pause.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                MemoryDefaults.remove(named: suite)
            }
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_660_000))
            let fixture = makePowerFixture(clock, folder: folder, suite: suite,
                sample: PowerObservation(timestamp: clock.value, source: .battery,
                    percentage: 70, charging: .notCharging))
            var problems: [String] = []
            fixture.1.start(workType: .deepWork, intent: "Paused")
            fixture.0.refresh()
            let id = fixture.1.activeRecordID

            clock.advance(600)
            fixture.0.togglePause()
            fixture.0.refresh()
            clock.advance(300)
            fixture.0.togglePause()
            fixture.0.refresh()
            var power = fixture.2.metadata(for: id)?.power ?? []
            expect(power.last?.timestamp == clock.value && power.last?.boundary == nil,
                   "resuming a sampled-through pause did not take a plain sample: "
                   + "\(String(describing: power.last?.boundary))", &problems)
            expect(!power.contains(where: { $0.boundary == .coverageResumed }),
                   "a manual pause was written up as a coverage gap", &problems)

            clock.advance(600)
            fixture.0.togglePause()
            fixture.0.refresh()
            clock.advance(3_600)
            fixture.0.noteMachineWake()
            fixture.0.togglePause()
            fixture.0.refresh()
            power = fixture.2.metadata(for: id)?.power ?? []
            expect(power.last?.timestamp == clock.value && power.last?.boundary == .coverageResumed,
                   "resuming after the machine slept did not mark the resume", &problems)
            expect(power.filter { $0.boundary == .coverageResumed }.count == 1,
                   "the wake was consumed more than once", &problems)
            return problems
        }
    }
}
