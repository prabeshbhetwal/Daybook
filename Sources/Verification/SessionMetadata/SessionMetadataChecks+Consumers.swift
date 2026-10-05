import Foundation
import SwiftUI
import AppKit
import IOKit.ps

extension SessionMetadataChecks {
    static func injectedPowerMonitor() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.power.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_598_000))
            let archive = SessionArchive(directory: folder, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: archive, ownBundleID: "com.example.metadata", schedulesDwell: false,
                now: { clock.value })
            let metadata = SessionMetadataArchive(directory: folder)
            let monitor = FakePowerMonitor(sample: PowerObservation(timestamp: clock.value,
                source: .battery, percentage: 78, charging: .notCharging))
            var store: SessionStore? = SessionStore(engine: engine, schedulesTicker: false,
                metadataArchive: metadata, powerMonitor: monitor, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Observed")
            store?.refresh()
            let recordID = engine.activeRecordID
            clock.advance(600)
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .battery,
                percentage: 64, charging: .notCharging, boundary: .sourceChanged))
            var problems: [String] = []
            expect(monitor.starts == 1, "injected monitor was not started exactly once", &problems)
            expect(metadata.metadata(for: recordID)?.power.map(\.percentage) == [78, 64],
                   "boundary and notification samples did not attach to the active stretch", &problems)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(1_200)
            engine.transition(on: .awayEnded)
            _ = engine.decide(.continueSession)
            store?.refresh()
            let successorID = engine.activeRecordID
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .external,
                percentage: 63, charging: .notCharging, boundary: .sourceChanged))
            expect(successorID != recordID,
                   "Away split did not rotate the stretch identity", &problems)
            expect(metadata.metadata(for: recordID)?.power.contains(where: {
                $0.boundary == .stretchEnded
            }) == false,
                   "Away split manufactured an old predecessor end sample", &problems)
            expect(metadata.metadata(for: successorID)?.power.first?.boundary == .stretchStarted,
                   "Away split did not start power evidence against its successor", &problems)
            expect(metadata.metadata(for: successorID)?.power.last?.percentage == 63,
                   "post-split notification attached to a stale predecessor identity", &problems)
            let fixtureStore = SessionStore(engine: engine, schedulesTicker: false,
                                            metadataArchive: metadata, now: { clock.value })
            expect(fixtureStore.powerMonitor == nil,
                   "a fixture-style store constructed a live power monitor", &problems)
            store = nil
            expect(monitor.stops == 1,
                   "store teardown did not stop the injected monitor exactly once", &problems)
            return problems
        }
    }

    static func groupedMetadataConsumers() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.grouped.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let start = Date(timeIntervalSince1970: 1_788_599_000)
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: SessionArchive(directory: folder, now: { start }), schedulesDwell: false,
                now: { start })
            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: engine, schedulesTicker: false,
                                     metadataArchive: metadata, now: { start })
            let first = UUID(), latest = UUID()
            _ = metadata.saveNote("Earlier stretch note", for: first)
            _ = metadata.saveNote("Latest stretch note", for: latest)
            _ = metadata.appendPower(PowerObservation(timestamp: start, source: .battery,
                percentage: 78, charging: .notCharging, boundary: .stretchStarted), for: first)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(300),
                source: .battery, percentage: 72, charging: .notCharging,
                boundary: .stretchEnded), for: first)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(600),
                source: .external, percentage: 70, charging: .charging,
                boundary: .stretchStarted), for: latest)
            _ = metadata.appendPower(PowerObservation(timestamp: start.addingTimeInterval(900),
                source: .external, percentage: 81, charging: .charging,
                boundary: .stretchEnded), for: latest)
            let summary = store.powerSummary(for: [first, latest],
                interval: DateInterval(start: start, duration: 900))
            var problems: [String] = []
            expect(store.sessionMetadata(for: first)?.note == "Earlier stretch note"
                   && store.sessionMetadata(for: latest)?.note == "Latest stretch note",
                   "grouped entry did not expose each exact record-scoped note", &problems)
            store.beginNoteEditing(for: first)
            expect(store.expandedNoteEditorIDs.contains(first)
                   && !store.expandedNoteEditorIDs.contains(latest),
                   "editing an earlier note targeted only the latest record", &problems)
            expect(summary?.headline == "Power changed"
                   && summary?.symbolName == "arrow.triangle.2.circlepath"
                   && summary?.detail?.contains("gaps between stretches are not power coverage") == true,
                   "grouped power implied one continuous span", &problems)
            expect(PowerContextSummary.make(observations: [PowerObservation(timestamp: start,
                source: .battery, percentage: 78, charging: .notCharging)],
                interval: DateInterval(start: start, duration: 1))?.symbolName == "battery.75percent",
                   "battery evidence used the wrong secondary symbol", &problems)
            expect(PowerContextSummary.make(observations: [PowerObservation(timestamp: start,
                source: .external, percentage: 70, charging: .notCharging)],
                interval: DateInterval(start: start, duration: 1))?.symbolName == "powerplug",
                   "external power used the battery symbol", &problems)
            return problems
        }
    }

    static func focusedEditorCommand() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.focus.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            let moment = Date(timeIntervalSince1970: 1_788_599_900)
            let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: SessionArchive(directory: folder, now: { moment }), schedulesDwell: false,
                now: { moment })
            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: engine, schedulesTicker: false,
                                     metadataArchive: metadata, now: { moment })
            let first = UUID(), second = UUID()
            store.beginNoteEditing(for: first); store.setNoteDraft("First\nnewline", for: first)
            store.beginNoteEditing(for: second); store.setNoteDraft("Second", for: second)
            store.setHistoryQuery("Xcode")
            let host = NSHostingView(rootView: VStack {
                SessionNoteEditor(store: store, recordID: first)
                SessionNoteEditor(store: store, recordID: second)
            })
            host.frame = NSRect(x: 0, y: 0, width: 480, height: 260)
            host.layoutSubtreeIfNeeded()
            store.focusedNoteEditorID = second
            var problems: [String] = []
            expect(store.saveFocusedNote(), "focused Command-Return route failed", &problems)
            expect(metadata.metadata(for: second)?.note == "Second"
                   && metadata.metadata(for: first)?.note == nil,
                   "focused save also saved the unfocused editor", &problems)
            expect(store.focusedNoteEditorID == nil,
                   "successful focused save retained a stale editor identity", &problems)
            expect(store.noteDraft(for: first) == "First\nnewline",
                   "ordinary Return/newline was not retained in the other draft", &problems)
            expect(store.historyFilter.query == "Xcode",
                   "note Command-Return changed History search", &problems)
            return problems
        }
    }

    static func identityAndDraftRetentionHardening() -> [String] {
        MainActor.assumeIsolated {
            let folder = directory(), suite = "com.prabesh.daybook.metadata.harden-id.\(UUID())"
            defer {
                try? FileManager.default.removeItem(at: folder)
                for name in [suite, suite + ".first", suite + ".second"] {
                    UserDefaults.standard.removePersistentDomain(forName: name)
                }
            }
            let moment = Date(timeIntervalSince1970: 1_788_601_000)
            guard let source = engine(at: moment, directory: folder, suite: suite) else {
                return ["could not create legacy rename fixture"]
            }
            source.start(workType: .deepWork, intent: "Before rename")
            var before = source.snapshot(); before.activeRecordID = nil
            var after = before; after.name = "After rename"
            let first = engine(at: moment, directory: folder, suite: suite + ".first")!
            let second = engine(at: moment, directory: folder, suite: suite + ".second")!
            first.restore(from: before); second.restore(from: after)
            var problems: [String] = []
            expect(first.activeRecordID == second.activeRecordID,
                   "legacy active identity changed after a rename", &problems)

            let metadata = SessionMetadataArchive(directory: folder)
            let store = SessionStore(engine: first, schedulesTicker: false,
                                     metadataArchive: metadata, now: { moment })
            let draftID = UUID()
            _ = metadata.saveNote("Durable before editing", for: draftID)
            store.beginNoteEditing(for: draftID)
            store.setNoteDraft("Unsaved revision", for: draftID)
            store.refreshSessionMetadataRetention()
            expect(metadata.metadata(for: draftID)?.note == "Durable before editing",
                   "retention removed durable metadata owned by a guarded open draft", &problems)
            return problems
        }
    }
}
