import SwiftUI

/// The phase strip for review: four sessions from the derivation traces (b, d, e and lunch), their
/// beats and app use written to a scratch folder, each shown as an open card, and case d's report.
/// The phases come the way the app reads them, from `storySessionDetail`, never hand-made shapes.
extension Snapshotter {
    static let phaseTraces = ["b. Coding with a tutorial playing", "d. Code, browse, code",
                              "e. A film inside a session", "Lunch"]

    static func phaseStrips() -> AnyView {
        let store = FixtureFactory.phaseStore()
        let sessions = store.daySessions.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }.sorted { $0.start < $1.start }
        let view = HStack(alignment: .top, spacing: Tokens.Space.xl) {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                ForEach(sessions) { session in
                    let detail = store.storySessionDetail(session, on: session.start)
                    SessionEntryCard(session: session, apps: detail.apps, shape: detail.text,
                                     shapeCaption: detail.caption, activity: detail.activity, phases: detail.phases,
                                     isOpen: true, clock: nil, metadataStore: store, onToggle: {})
                }
            }
            .frame(width: 620.zoomed)
            if let reported = sessions.dropFirst().first {
                SessionReportCard(store: store, session: reported, onClose: {})
                    .frame(width: 760.zoomed, height: 900.zoomed)
            }
        }
        .padding(Tokens.Space.xl)
        .background(Tokens.Colour.ground)
        return AnyView(view)
    }
}

extension FixtureFactory {
    /// The traces moved to the fixture day, an hour and a half apart from 7 am, as finished sessions
    /// with the trace's counted time as the record's work and the rest as its pauses.
    @MainActor static func phaseStore() -> SessionStore {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = today.addingTimeInterval(18 * 3_600)
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { now })
        let beats = BeatArchive(directory: directory.appendingPathComponent(BeatArchive.folderName), calendar: calendar)
        let envelope = UsageFixtureEnvelope(metadata: AppUsageMetadata(accurateFrom: today), sessions: [])
        if let bytes = try? JSONEncoder().encode(envelope) {
            try? bytes.write(to: directory.appendingPathComponent("app-usage.json"), options: .atomic)
        }
        let usage = AppUsageArchive(directory: directory, calendar: calendar, now: { now })
        let names = [ActivityTraces.editor: "Code", ActivityTraces.browser: "Chrome", ActivityTraces.mediaPlayer: "TV"]
        for (index, name) in Snapshotter.phaseTraces.enumerated() {
            guard let input = ActivityTraces.all.first(where: { $0.name == name })?.input else { continue }
            let start = today.addingTimeInterval(TimeInterval(7 * 3_600 + index * 150 * 60))
            let shift = start.timeIntervalSince(input.bounds.start)
            var used: (app: String, start: Date, end: Date)?
            func flush() {
                if let run = used {
                    usage.record(AppUsageSession(bundleID: run.app, appName: names[run.app] ?? run.app,
                                                 start: run.start, end: run.end))
                }
            }
            for beat in input.credit.beats {
                let moved = Beat(start: beat.start.addingTimeInterval(shift), offset: beat.offset, slices: beat.slices,
                                 presence: beat.presence, watchedApps: beat.watchedApps)
                try? beats.append(moved)
                var at = moved.start.addingTimeInterval(TimeInterval(moved.offset))
                for slice in moved.slices {
                    let end = at.addingTimeInterval(TimeInterval(slice.seconds))
                    if let run = used, run.app == slice.app, run.end == at { used?.end = end } else { flush(); used = (slice.app, at, end) }
                    at = end
                }
            }
            flush()
            let bounds = DateInterval(start: start, end: input.bounds.end.addingTimeInterval(shift))
            let counted = input.credit.counted.map { DateInterval(start: $0.start.addingTimeInterval(shift),
                                                                  end: $0.end.addingTimeInterval(shift)) }
            let paused = zip([bounds.start] + counted.map(\.end), counted.map(\.start) + [bounds.end])
                .filter { $0.0 < $0.1 }.map { DateInterval(start: $0.0, end: $0.1) }
            archive.append(SessionRecord(name: ["Follow a tutorial", "Refactor the importer", "Code, then a film",
                                                "Before and after lunch"][index],
                                         workType: .deepWork, start: bounds.start, end: bounds.end,
                                         workSeconds: counted.reduce(0) { $0 + $1.duration },
                                         detectedApp: ActivityTraces.editor, pausedSpans: paused.isEmpty ? nil : paused))
        }
        let engine = SessionEngine(store: PersistenceStore(defaults: fixtureDefaults("phases")), archive: archive,
                                   ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false, now: { now })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled, now: { now })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { now })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.refresh()
        return store
    }
}
