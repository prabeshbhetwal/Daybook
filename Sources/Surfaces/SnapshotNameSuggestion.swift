import Foundation

extension Snapshotter {
    /// The week fixture plus one unnamed hour from 7:10 am today, in Xcode then
    /// Terminal, so the model has apps to read and the Story has a session to
    /// offer a name for. The fixture's clock is noon, so the hour has ended.
    static func nameSuggestionStore() -> SessionStore {
        let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
        store.setDashboardVisible(true)
        let calendar = store.periodCalendar
        let today = calendar.startOfDay(for: store.now())
        func time(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        let (start, switchedAt, end) = (time(7, 10), time(7, 55), time(8, 10))
        _ = store.engine.archive.append(SessionRecord(
            name: "", workType: .deepWork, start: start, end: end,
            workSeconds: end.timeIntervalSince(start), detectedApp: "com.apple.dt.Xcode"))
        _ = store.usage?.record(AppUsageSession(
            bundleID: "com.apple.dt.Xcode", appName: "Xcode", start: start, end: switchedAt))
        _ = store.usage?.record(AppUsageSession(
            bundleID: "com.apple.Terminal", appName: "Terminal", start: switchedAt, end: end))
        store.refresh()
        return store
    }

    /// Has the suggester answer "Release notes" without the model, and waits
    /// for it, so the capture shows the offer and never the wait for one.
    static func presentNameSuggestion(on navigation: MainWindowModel) {
        guard let suggester = navigation.nameSuggester else { return }
        suggester.responder = { _ in .fresh("Release notes") }
        suggester.refresh()
        _ = InstalledAppCatalog.turnRunLoop(until: { !suggester.isAsking }, timeout: 5)
    }
}
