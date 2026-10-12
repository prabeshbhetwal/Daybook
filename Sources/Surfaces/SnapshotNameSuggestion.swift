import Foundation

extension Snapshotter {
    /// Scenes whose setup did not produce the offer they pin; `run` fails on any.
    static var setupFailures = 0

    /// The week fixture plus one unnamed hour from 7:10 am today. The fixture's
    /// clock is noon, so the hour has ended. The fresh scene works in Logic
    /// Pro, which no earlier name used, so the session has no candidate and
    /// the model words its own name. The earlier scene works in Figma and the
    /// store holds "Landing page", also in Figma two days ago, as the only
    /// candidate, so the ranking clearly leads.
    static func nameSuggestionStore(earlier: Bool) -> SessionStore {
        let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
        store.setDashboardVisible(true)
        let calendar = store.periodCalendar
        let today = calendar.startOfDay(for: store.now())
        func time(_ daysBack: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func work(_ name: String, from start: Date, to end: Date, app: (id: String, name: String)) {
            _ = store.engine.archive.append(SessionRecord(
                name: name, workType: .deepWork, start: start, end: end,
                workSeconds: end.timeIntervalSince(start), detectedApp: app.id))
            _ = store.usage?.record(AppUsageSession(bundleID: app.id, appName: app.name, start: start, end: end))
        }
        let app = earlier ? (id: "com.figma.Desktop", name: "Figma") : (id: "com.apple.logic10", name: "Logic Pro")
        if earlier { work("Landing page", from: time(2, 14, 0), to: time(2, 15, 0), app: app) }
        work("", from: time(0, 7, 10), to: time(0, 8, 10), app: app)
        store.refresh()
        return store
    }

    /// Has the suggester answer without the model, and waits for it, so the
    /// capture shows the offer and never the wait for one. A scene that ends
    /// with no offer, or one from the other source, would pin the wrong
    /// caption (or nothing), so it fails the render.
    static func presentNameSuggestion(on navigation: MainWindowModel, expecting source: NameSuggestion.Source) {
        guard let suggester = navigation.nameSuggester else { return reportMissingSuggestion("no suggester") }
        suggester.responder = { _ in source == .fresh ? .fresh("Podcast mix") : .earlier(1) }
        suggester.refresh()
        _ = InstalledAppCatalog.turnRunLoop(until: { !suggester.isAsking }, timeout: 5)
        guard let offer = suggester.current, offer.source == source else {
            return reportMissingSuggestion("offered \(String(describing: suggester.current)), not a \(source) name")
        }
    }

    private static func reportMissingSuggestion(_ what: String) {
        FileHandle.standardError.write(Data("name suggestion scene: \(what)\n".utf8))
        setupFailures += 1
    }
}
