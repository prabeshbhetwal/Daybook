import Foundation
import SwiftUI
import AppKit

/// Four things a reader loses or cannot read: words typed while dictating, an
/// unsaved rule or category when Settings changes page, the day of a session
/// report, and orange category text on its own wash.
enum EditorAndReportChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Dictation never writes over a note typed into while listening", dictationKeepsTypedText),
        ("An unsaved activity rule survives Settings changing page", ruleDraftSurvivesPageSwitch),
        ("An unsaved category survives Settings changing page", categoryDraftSurvivesPageSwitch),
        ("The session report says which day it is, in its header and to VoiceOver", reportNamesItsDay),
        ("Orange category text reaches 4.6:1 on white, the canvas and its own wash", orangeInkContrast)
    ]

    // MARK: Dictation

    private static func dictationKeepsTypedText() -> [String] {
        var problems: [String] = []
        // The probe: a note dictated into, corrected by hand, then dictated
        // into again.
        var note = DictationNote(startingFrom: "Original")
        let first = note.applying("first", to: "Original")
        expect(first == "Original first", "words after an untouched note should follow it, got \(first ?? "nil")",
               &problems)
        let second = note.applying("first second", to: "Original first typed correction")
        expect(second == nil, "the next words replaced a typed correction with \(second ?? "nil")", &problems)

        var plain = DictationNote(startingFrom: "Hello \n")
        let opening = plain.applying("world", to: "Hello \n")
        let later = plain.applying("world again", to: opening ?? "")
        expect(opening == "Hello world" && later == "Hello world again",
               "an untouched note should keep following the transcript, got \(opening ?? "nil"), \(later ?? "nil")",
               &problems)

        var empty = DictationNote(startingFrom: "")
        expect(empty.applying("hi", to: "") == "hi", "an empty note should become the transcript", &problems)
        expect(empty.applying("hi there", to: "hi!") == nil,
               "an edit to the first words should be kept, not rewritten", &problems)
        return problems
    }

    // MARK: Settings drafts

    private static func ruleDraftSurvivesPageSwitch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (model, other, cleanUp) = settingsModels()
            defer { cleanUp() }
            let closed = drawn(ActivityRulesView(model: model))
            let drafts = SettingsDrafts.of(model)
            drafts.rule.beginNew()
            drafts.rule.name = "Half-written rule"
            let open = drawn(ActivityRulesView(model: model))
            // Settings replaces the page when the reader moves to another and
            // back: a new view over the same model.
            let returned = drawn(ActivityRulesView(model: model))
            expect(open.height > closed.height + 40,
                   "the rule form was not drawn from the draft: \(closed) closed, \(open) with a draft", &problems)
            expect(returned == open, "the rebuilt page lost the draft: \(open) before, \(returned) after", &problems)
            expect(drafts.rule.name == "Half-written rule" && drafts.rule.isNew,
                   "the draft's text changed: \(drafts.rule.name)", &problems)
            expect(SettingsDrafts.of(other).rule.selectedID == nil,
                   "a second settings model shared the first one's draft", &problems)
            return problems
        }
    }

    private static func categoryDraftSurvivesPageSwitch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (model, _, cleanUp) = settingsModels()
            defer { cleanUp() }
            let closed = drawn(CategoriesView(model: model))
            let drafts = SettingsDrafts.of(model)
            drafts.category.beginNew()
            drafts.category.name = "Half-made category"
            let open = drawn(CategoriesView(model: model))
            let returned = drawn(CategoriesView(model: model))
            expect(open.height > closed.height + 40,
                   "the category form was not drawn from the draft: \(closed) closed, \(open) with a draft",
                   &problems)
            expect(returned == open, "the rebuilt page lost the draft: \(open) before, \(returned) after", &problems)
            expect(drafts.category.name == "Half-made category",
                   "the draft's text changed: \(drafts.category.name)", &problems)
            return problems
        }
    }

    /// Two settings models over throwaway preferences, and the closure that
    /// removes them. Installed applications are injected, so nothing scans
    /// the Mac.
    @MainActor private static func settingsModels() -> (SettingsModel, SettingsModel, () -> Void) {
        let suite = "fc-selftest-drafts-\(UUID().uuidString)"
        let defaults = MemoryDefaults.suite(named: suite)!
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        func model() -> SettingsModel {
            let apps = InstalledAppCatalog(discoverStandard: {
                (0..<40).map { InstalledApplication(bundleID: "com.example.app\($0)",
                                                    name: "Application \($0)", url: nil) }
            }, discoverSpotlight: { [] }, observed: { [] })
            return SettingsModel(store: store, isTrackingEnabled: true, onChange: {},
                                 onTrackingChanged: { _ in }, installedAppCatalog: apps)
        }
        return (model(), model(), { defaults.removePersistentDomain(forName: suite) })
    }

    private struct Drawn: Equatable, CustomStringConvertible {
        let height: Int
        let scrollRegions: Int
        var description: String { "\(height)pt, \(scrollRegions) scroll regions" }
    }

    /// A page opened at a reading width and released, as Settings does: how
    /// tall it came out, and how many scroll regions it holds.
    @MainActor private static func drawn(_ page: some View) -> Drawn {
        let host = NSHostingView(rootView: page.frame(width: 680))
        host.frame = NSRect(x: 0, y: 0, width: 680, height: 900)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        return Drawn(height: Int(host.fittingSize.height),
                     scrollRegions: ActivityRuleChecks.descendantCount(NSScrollView.self, in: host))
    }

    // MARK: Session report

    private static func reportNamesItsDay() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let dayName = DateFormatter()
        dayName.dateFormat = "EEEE d MMMM y"
        let morning = SelfTest.base
        let evening = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: morning)!
        let afterMidnight = evening.addingTimeInterval(4_200)
        let firstDay = dayName.string(from: morning)
        let nextDay = dayName.string(from: afterMidnight)
        expect(firstDay != nextDay, "the fixture's two days are not different days", &problems)

        let sameDay = report(from: morning, to: morning.addingTimeInterval(4_020))
        expect(sameDay.whenText.contains(firstDay) && sameDay.whenText.contains("–"),
               "a one-day report's header should give its day and its times: \(sameDay.whenText)", &problems)
        expect(sameDay.whenSpoken.contains(firstDay) && sameDay.whenSpoken.contains(" to ")
               && !sameDay.whenSpoken.contains("–"),
               "VoiceOver should hear the day and 'to': \(sameDay.whenSpoken)", &problems)
        expect(!sameDay.whenText.contains(nextDay), "a one-day report named another day: \(sameDay.whenText)",
               &problems)
        let stretch = sameDay.stretches[0]
        expect(!sameDay.stretchWhen(stretch).contains(firstDay),
               "a stretch repeated the day its header already gave: \(sameDay.stretchWhen(stretch))", &problems)

        let overnight = report(from: evening, to: afterMidnight)
        for (label, text) in [("header", overnight.whenText), ("spoken", overnight.whenSpoken)] {
            expect(text.contains(firstDay) && text.contains(nextDay),
                   "a session across midnight should name both days in its \(label): \(text)", &problems)
        }
        let night = overnight.stretches[0]
        for text in [overnight.stretchWhen(night), overnight.stretchWhen(night, joiner: "to")] {
            expect(text.contains(firstDay) && text.contains(nextDay),
                   "a stretch across midnight should name both days: \(text)", &problems)
        }

        let running = report(from: evening, to: afterMidnight, running: true)
        expect(running.whenText.hasPrefix("Running since") && running.whenText.contains(firstDay)
               && running.whenSpoken == running.whenText,
               "a running session's header should say since when, with the day: \(running.whenText)", &problems)

        // A day's session is clipped to that day, its stretches are not: one
        // record that ran 11:30 pm to 12:40 am, reported from either day.
        let midnight = calendar.startOfDay(for: afterMidnight)
        let eveningHalf = report(from: evening, to: midnight, stretch: (evening, afterMidnight))
        let morningHalf = report(from: midnight, to: afterMidnight, stretch: (evening, afterMidnight))
        for (label, half) in [("first day", eveningHalf), ("second day", morningHalf)] {
            let text = half.stretchWhen(half.stretches[0])
            expect(text.contains(firstDay) && text.contains(nextDay),
                   "the \(label)'s stretch should name both days: \(text)", &problems)
        }
        let runningAcross = report(from: midnight, to: afterMidnight, running: true, stretch: (evening, afterMidnight))
        expect(runningAcross.whenText.contains(firstDay),
               "a running session clipped to today should say it began yesterday: \(runningAcross.whenText)",
               &problems)

        // The year appears only when it is not this year's.
        let thisYear = DateFormatter()
        thisYear.dateFormat = "EEEE d MMMM"
        expect(DateFormats.fullDay(morning, now: morning) == thisYear.string(from: morning),
               "a day in the current year should omit the year: \(DateFormats.fullDay(morning, now: morning))",
               &problems)
        return problems
    }

    /// A report over one stretch, by default spanning the whole session,
    /// built by hand: a report only needs a session, its stretches and an
    /// empty detail.
    private static func report(from start: Date, to end: Date, running: Bool = false,
                               stretch span: (start: Date, end: Date)? = nil) -> SessionReport {
        let session = DaySession(id: UUID(), threadID: UUID(), name: "Parser", workType: .deepWork,
                                 start: start, end: end, worked: end.timeIntervalSince(start), stretches: 1,
                                 spans: [DateInterval(start: start, end: end)], isRunning: running)
        let detail = StorySessionDetail(apps: [], text: nil, caption: nil, reportNote: nil,
                                        activity: RecordedActivity(segments: [], spans: []), bins: [])
        let stretch = SessionReport.Stretch(id: UUID(), start: span?.start ?? start, end: span?.end ?? end,
                                            worked: (span?.end ?? end).timeIntervalSince(span?.start ?? start),
                                            note: nil)
        return SessionReport(session: session, detail: detail, stretches: [stretch], power: nil,
                             powerChanges: [:], appColourIndices: [:])
    }

    // MARK: Orange ink

    private static func orangeInkContrast() -> [String] {
        var problems: [String] = []
        let ink = srgb(StoryStyle.ink(.orange))
        let wash = srgb(Tokens.Palette.hue(.orange))
        // The badge lays 14% of the hue over its surface, the active filter
        // chip 12%; both sit on white or on the canvas.
        for (surface, colour) in [("white", StoryStyle.card), ("the canvas", StoryStyle.canvas)] {
            for opacity in [0.0, 0.12, 0.14] {
                let background = blend(wash, over: srgb(colour), opacity: opacity)
                let ratio = contrast(ink, background)
                expect(ratio >= 4.6, "orange text on \(surface) with a \(Int(opacity * 100))% wash measured "
                       + "\(String(format: "%.3f", ratio)):1", &problems)
            }
        }
        // Still orange: red leads, green follows, blue is absent.
        expect(ink.r > ink.g && ink.g > ink.b && ink.b < 0.05,
               "the orange ink left its hue family: \(ink)", &problems)
        return problems
    }

    /// The light-appearance sRGB components of a colour token.
    private static func srgb(_ colour: Color) -> (r: Double, g: Double, b: Double) {
        var result = (r: 0.0, g: 0.0, b: 0.0)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            if let rgb = NSColor(colour).usingColorSpace(.sRGB) {
                result = (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
            }
        }
        return result
    }

    private static func blend(_ colour: (r: Double, g: Double, b: Double),
                              over background: (r: Double, g: Double, b: Double),
                              opacity: Double) -> (r: Double, g: Double, b: Double) {
        (colour.r * opacity + background.r * (1 - opacity),
         colour.g * opacity + background.g * (1 - opacity),
         colour.b * opacity + background.b * (1 - opacity))
    }

    /// WCAG 2.x contrast between two sRGB colours.
    private static func contrast(_ first: (r: Double, g: Double, b: Double),
                                 _ second: (r: Double, g: Double, b: Double)) -> Double {
        func luminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
            func channel(_ value: Double) -> Double {
                value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
        }
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}
