import Foundation
import SwiftUI
import AppKit

/// Behavioural checks for user-defined categories: the catalogue's merge
/// rules, the wire format old records depend on, persistence through
/// Settings, the editor's validation, and that every hue and every offered
/// symbol resolves to something drawable.
enum CategoryChecks {
    static let tests: [(String, () -> [String])] = [
        ("Category catalogue merges built-ins, edits and additions in a fixed order", catalogueMerge),
        ("Work types keep the bare-string wire format old records were written in", wireFormat),
        ("Categories persist through Settings and resolve app-wide after reload", persistence),
        ("Retired categories leave the pickers but keep their recorded hours", retirement),
        ("Category editor validates name, uniqueness and symbol", editorValidation),
        ("Every hue and every offered symbol is drawable", huesAndSymbols),
        ("The floating category panel opens from a picker and selects what it makes", floatingPanel),
        ("Letters and numbers become glyph symbols, and the browse groups cover the grid", glyphs),
        ("Category goals and break rules travel with the definition", goalsAndReminders),
        ("Starting from an app teaches its category", learnedChoices),
        ("The category insight places each category in the day", categoryInsight)
    ]

    private static func fresh() -> (PersistenceStore, UserDefaults, String) {
        let suite = "com.prabesh.focuscontinuity.categories.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        return (store, defaults, suite)
    }

    private static func restore(_ defaults: UserDefaults, _ suite: String) {
        defaults.removePersistentDomain(forName: suite)
        // Later tests read the shared catalogue; leave it as shipped.
        WorkTypeCatalog.shared.apply(customisations: [])
    }

    private static func catalogueMerge() -> [String] {
        var failures: [String] = []
        let shipped = WorkTypeCatalog()
        if shipped.activeTypes != [.deepWork, .meetings, .admin, .learning, .breakTime] {
            failures.append("A catalogue with no customisations did not list the five built-ins in order")
        }
        if shipped.definition(for: .meetings).symbolName != "person.2.fill"
            || shipped.definition(for: .deepWork).name != "Deep work"
            || shipped.definition(for: .breakTime).hue != .grey {
            failures.append("Built-in defaults changed")
        }
        if !shipped.definition(for: .meetings).countsWhileWatching
            || !shipped.definition(for: .learning).countsWhileWatching
            || shipped.definition(for: .admin).countsWhileWatching {
            failures.append("Watching semantics no longer match the shipped meaning of each built-in")
        }
        let custom = WorkTypeDefinition(id: "custom.calls", name: "  Client   calls ",
                                        symbolName: "phone.fill", hue: .green, countsWhileWatching: true)
        let renamed = WorkTypeDefinition(id: WorkType.deepWork.rawValue, name: "Making",
                                         symbolName: "hammer.fill", hue: .purple)
        let blankEdit = WorkTypeDefinition(id: WorkType.admin.rawValue, name: "   ",
                                           symbolName: "", hue: .grey)
        let merged = WorkTypeCatalog(customisations: [custom, renamed, blankEdit])
        if merged.activeTypes != [.deepWork, .meetings, .admin, .learning, WorkType(rawValue: "custom.calls"), .breakTime] {
            failures.append("A made category did not land after the built-ins and before Break: \(merged.activeTypes.map(\.rawValue))")
        }
        let calls = merged.definition(for: WorkType(rawValue: "custom.calls"))
        if calls.name != "Client calls" || calls.symbolName != "phone.fill" || calls.hue != .green
            || !calls.countsWhileWatching {
            failures.append("A made category lost its normalised name, symbol, hue or watching flag")
        }
        let making = merged.definition(for: .deepWork)
        if making.name != "Making" || making.symbolName != "hammer.fill" || making.hue != .purple {
            failures.append("An edited built-in did not take its new name, symbol and hue")
        }
        let admin = merged.definition(for: .admin)
        if admin.name != "Admin" || admin.symbolName != "tray.full.fill" || admin.hue != .teal {
            failures.append("A blank edit to a built-in did not fall back to its defaults")
        }
        if merged.definition(for: .deepWork).countsWhileWatching {
            failures.append("Editing a built-in changed what it means")
        }
        let unknown = merged.definition(for: WorkType(rawValue: "custom.gone"))
        if unknown.name != "Other" || !unknown.isRetired || unknown.hue != .grey {
            failures.append("A category this build has never heard of did not resolve to a readable fallback")
        }
        let greyCustom = WorkTypeCatalog(customisations: [
            WorkTypeDefinition(id: "custom.grey", name: "Grey", symbolName: "tag.fill", hue: .grey)])
        if greyCustom.definition(for: WorkType(rawValue: "custom.grey")).hue == .grey {
            failures.append("A made category was allowed to wear rest's grey")
        }
        return failures
    }

    private static func wireFormat() -> [String] {
        var failures: [String] = []
        do {
            let encoded = try JSONEncoder().encode([WorkType.deepWork, WorkType(rawValue: "custom.x")])
            if String(decoding: encoded, as: UTF8.self) != "[\"deepWork\",\"custom.x\"]" {
                failures.append("WorkType no longer encodes as the bare identifier string")
            }
            let legacy = Data("""
            {"id":"0BD1E4B2-4B7E-4A5E-9F9C-2E0D6A7C1F11","name":"Spec","workType":"learning",
             "start":1700000000,"end":1700003600,"workSeconds":3600}
            """.utf8)
            let record = try JSONDecoder().decode(SessionRecord.self, from: legacy)
            if record.workType != .learning || record.workType.displayName != "Learning" {
                failures.append("A record written by the enum-era app did not decode to the same category")
            }
            let futureRecord = try JSONDecoder().decode(
                SessionRecord.self,
                from: Data(legacy.map { $0 }).replacingFirst("\"learning\"", with: "\"custom.never\""))
            if futureRecord.workType.rawValue != "custom.never" || futureRecord.workType.displayName != "Other" {
                failures.append("A record filed under an unknown category did not survive decoding with a readable name")
            }
        } catch {
            failures.append("Category wire format round trip threw: \(error)")
        }
        return failures
    }

    private static func persistence() -> [String] {
        var failures: [String] = []
        let (store, defaults, suite) = fresh()
        defer { restore(defaults, suite) }
        var changes = 0
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: { changes += 1 }, onTrackingChanged: { _ in })
        let calls = WorkTypeDefinition(id: "custom.calls", name: "Calls", symbolName: "phone.fill",
                                       hue: .green, countsWhileWatching: true)
        settings.saveCategory(calls)
        settings.saveCategory(WorkTypeDefinition(id: WorkType.meetings.rawValue, name: "Standups",
                                                 symbolName: "person.3.fill", hue: .orange))
        if changes != 2 {
            failures.append("Saving categories did not tell the coordinator to refresh each time")
        }
        let type = WorkType(rawValue: "custom.calls")
        if type.displayName != "Calls" || type.symbolName != "phone.fill" || type.hue != .green
            || !type.countsWhileWatching || !type.countsAsFocus {
            failures.append("A saved category did not resolve app-wide through WorkType")
        }
        if WorkType.meetings.displayName != "Standups" || WorkType.meetings.symbolName != "person.3.fill" {
            failures.append("An edited built-in did not resolve app-wide through WorkType")
        }
        if !WorkType.startable.contains(type) || WorkType.startable.contains(.breakTime) {
            failures.append("The startable list did not offer the made category, or offered Break")
        }
        // A second store on the same defaults is a relaunch.
        let reloaded = PersistenceStore(defaults: defaults)
        if reloaded.workTypeDefinitions.count != 2 || type.displayName != "Calls" {
            failures.append("Categories did not survive a relaunch")
        }
        settings.resetCategory(id: WorkType.meetings.rawValue)
        if WorkType.meetings.displayName != "Meetings" || settings.workTypeDefinitions.count != 1 {
            failures.append("Resetting a built-in did not drop its edit")
        }
        settings.resetCategory(id: "custom.calls")
        if settings.workTypeDefinitions.count != 1 {
            failures.append("Reset was allowed to delete a made category")
        }
        // Dynamic colours never compare equal, so the swatch is checked
        // through the hue it is drawn from.
        if type.hue != .green || type.definition.hue != .green {
            failures.append("A made category's swatch did not follow its hue")
        }
        // Quick starts remember the category with the name.
        store.rememberActivity(name: "Weekly call", workType: type)
        if store.recentActivities.first?.workType != type {
            failures.append("A recent activity did not keep its made category")
        }
        return failures
    }

    private static func retirement() -> [String] {
        var failures: [String] = []
        let (store, defaults, suite) = fresh()
        defer { restore(defaults, suite) }
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        let type = WorkType(rawValue: "custom.calls")
        settings.saveCategory(WorkTypeDefinition(id: type.rawValue, name: "Calls",
                                                 symbolName: "phone.fill", hue: .green))
        settings.setCategoryRetired(id: type.rawValue, true)
        if WorkType.allCases.contains(type) || WorkType.startable.contains(type) {
            failures.append("A retired category was still offered")
        }
        if type.displayName != "Calls" || type.symbolName != "phone.fill" {
            failures.append("A retired category forgot what it was called")
        }
        let ordered = WorkType.ordered([.breakTime, type, .admin, WorkType(rawValue: "zz.unknown")])
        if ordered != [.admin, type, .breakTime, WorkType(rawValue: "zz.unknown")] {
            failures.append("Totals ordering dropped a retired or unknown category: \(ordered.map(\.rawValue))")
        }
        settings.setCategoryRetired(id: WorkType.admin.rawValue, true)
        if !WorkType.allCases.contains(.admin) {
            failures.append("A built-in was allowed to retire")
        }
        settings.setCategoryRetired(id: type.rawValue, false)
        if !WorkType.startable.contains(type) {
            failures.append("A restored category did not return to the pickers")
        }
        return failures
    }

    private static func editorValidation() -> [String] {
        var failures: [String] = []
        let (_, defaults, suite) = fresh()
        defer { restore(defaults, suite) }
        let editor = CategoryEditorState()
        editor.beginNew()
        guard let id = editor.selectedID, id.hasPrefix("custom.") else {
            return ["A new category did not get a custom identifier"]
        }
        if editor.hue == .grey || editor.hue == .indigo {
            failures.append("A new category defaulted to a hue a built-in already wears")
        }
        let existing = WorkTypeCatalog.shared.allDefinitions
        if editor.definitionForSaving(existing: existing) != nil || editor.validationMessage == nil {
            failures.append("A nameless category was allowed to save")
        }
        editor.name = "deep   WORK"
        if editor.definitionForSaving(existing: existing) != nil
            || editor.validationMessage?.contains("already called") != true {
            failures.append("A name matching a built-in was allowed, or the reason was not given")
        }
        editor.name = String(repeating: "x", count: WorkTypeDefinition.nameLimit + 1)
        if editor.definitionForSaving(existing: existing) != nil {
            failures.append("An over-long name was allowed to save")
        }
        editor.name = "Calls"
        editor.symbolName = "not.a.real.symbol.name"
        if editor.definitionForSaving(existing: existing) != nil {
            failures.append("A category with an unknown symbol was allowed to save")
        }
        editor.typedSymbol = "cpu.fill"
        editor.acceptTypedSymbol()
        if editor.symbolName != "cpu.fill" || editor.validationMessage != nil {
            failures.append("A real typed symbol was not accepted")
        }
        editor.typedSymbol = "definitely.not.here"
        editor.acceptTypedSymbol()
        if editor.symbolName != "cpu.fill" || editor.validationMessage == nil {
            failures.append("A made-up typed symbol replaced the real one, or drew no message")
        }
        editor.countsWhileWatching = true
        guard let saved = editor.definitionForSaving(existing: existing) else {
            return failures + ["A valid category failed to save: \(editor.validationMessage ?? "")"]
        }
        if saved.name != "Calls" || saved.symbolName != "cpu.fill" || !saved.countsWhileWatching
            || saved.isRetired {
            failures.append("The saved category did not carry the form's values")
        }
        // Editing a built-in cannot change what it means.
        editor.edit(WorkTypeCatalog.shared.definition(for: .admin))
        editor.countsWhileWatching = true
        editor.name = "Paperwork"
        if editor.definitionForSaving(existing: existing)?.countsWhileWatching != false {
            failures.append("Editing a built-in was allowed to change its watching semantics")
        }
        editor.edit(WorkTypeCatalog.shared.definition(for: .breakTime))
        editor.hue = .red
        if editor.definitionForSaving(existing: existing)?.hue != .grey {
            failures.append("Break was allowed to stop being grey")
        }
        return failures
    }

    private static func floatingPanel() -> [String] {
        var failures: [String] = []
        let (store, defaults, suite) = fresh()
        defer { restore(defaults, suite) }
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        var adopted: [WorkType] = []
        // The panel is main-actor state; the self-test already runs on the
        // main thread, so this only tells the compiler what is true.
        let panelFailures: [String] = MainActor.assumeIsolated {
            var problems: [String] = []
            let panel = CategoryEditorPanel.shared
            panel.show(.new, model: settings) { definition, wasNew in
                if wasNew { adopted.append(definition.workType) }
            }
            if !panel.isVisible || panel.title != "New category" {
                problems.append("Add category… did not open the panel on a blank form")
            }
            panel.show(.edit(.meetings), model: settings)
            if panel.title != "Edit categories" {
                problems.append("Edit categories… did not retitle the already-open panel")
            }
            panel.close()
            if panel.isVisible {
                problems.append("The panel did not close")
            }
            return problems
        }
        failures += panelFailures
        // The form's save path: a new category is handed back as new, an edit is not.
        var saved: [(String, Bool)] = []
        let editor = CategoryEditorState()
        editor.beginNew()
        editor.name = "Reviews"
        editor.symbolName = "checklist"
        var form = CategoryEditorForm(model: settings, editor: editor, onFinished: {})
        form.onSaved = { definition, wasNew in saved.append((definition.name, wasNew)) }
        form.commitForTesting()
        editor.edit(WorkTypeCatalog.shared.definition(for: .admin))
        editor.name = "Paperwork"
        form.commitForTesting()
        if saved.map(\.0) != ["Reviews", "Paperwork"] || saved.map(\.1) != [true, false] {
            failures.append("The form did not report new and edited categories apart: \(saved)")
        }
        if !WorkType.startable.contains(where: { $0.displayName == "Reviews" })
            || WorkType.admin.displayName != "Paperwork" {
            failures.append("Saving through the form did not reach the catalogue")
        }
        _ = adopted
        return failures
    }

    private static func glyphs() -> [String] {
        var failures: [String] = []
        let cases: [(String, WorkTypeSymbols.GlyphStyle, String?)] = [
            ("B", .circle, "b.circle.fill"), (" c ", .square, "c.square.fill"),
            ("1", .circle, "1.circle.fill"), ("12", .square, "12.square.fill"),
            ("50", .circle, "50.circle.fill"), ("51", .circle, nil), ("ab", .circle, nil),
            ("é", .circle, nil), ("", .circle, nil), ("-1", .circle, nil)
        ]
        for (text, style, expected) in cases where WorkTypeSymbols.glyph(for: text, style: style) != expected {
            failures.append("glyph(\"\(text)\", \(style)) gave \(WorkTypeSymbols.glyph(for: text, style: style) ?? "nil"), expected \(expected ?? "nil")")
        }
        if WorkTypeSymbols.glyphText(of: "b.circle.fill")?.text != "B"
            || WorkTypeSymbols.glyphText(of: "12.square.fill")?.style != .square
            || WorkTypeSymbols.glyphText(of: "phone.fill") != nil
            || WorkTypeSymbols.glyphText(of: "person.circle.fill") != nil {
            failures.append("Reading a letter or number back out of a symbol name went wrong")
        }
        var undrawable: [String] = []
        for style in WorkTypeSymbols.GlyphStyle.allCases {
            for text in WorkTypeSymbols.glyphChoices + (10...WorkTypeSymbols.glyphNumberLimit).map(String.init) {
                guard let symbol = WorkTypeSymbols.glyph(for: text, style: style) else {
                    undrawable.append(text); continue
                }
                if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil { undrawable.append(symbol) }
            }
        }
        if !undrawable.isEmpty {
            failures.append("Glyphs this macOS cannot draw: \(undrawable)")
        }
        if WorkTypeSymbols.glyphChoices.count != 36 || WorkTypeSymbols.glyphChoices.first != "A"
            || WorkTypeSymbols.glyphChoices.last != "9" {
            failures.append("The glyph grid is not A–Z then 0–9")
        }
        if WorkTypeSymbols.groups.flatMap(\.symbols) != WorkTypeSymbols.curated {
            failures.append("The browse menu and the grid offer different symbols")
        }
        if WorkTypeSymbols.title(for: "chart.line.uptrend.xyaxis") != "Chart line uptrend xyaxis"
            || WorkTypeSymbols.title(for: "tag.fill") != "Tag" {
            failures.append("Symbol titles did not read as words")
        }
        // The editor round-trips a glyph icon.
        let editor = CategoryEditorState()
        editor.beginNew()
        editor.glyphText = "b"
        editor.glyphStyle = .square
        editor.acceptGlyph()
        if editor.symbolName != "b.square.fill" || editor.glyphText != "B" || editor.validationMessage != nil {
            failures.append("Accepting a letter did not set the glyph symbol")
        }
        editor.glyphText = "99"
        editor.acceptGlyph()
        if editor.symbolName != "b.square.fill" || editor.validationMessage == nil {
            failures.append("An out-of-range number replaced the icon, or drew no message")
        }
        editor.edit(WorkTypeDefinition(id: "custom.g", name: "Browsing", symbolName: "b.square.fill", hue: .blue))
        if editor.iconMode != .glyph || editor.glyphText != "B" || editor.glyphStyle != .square {
            failures.append("Editing a glyph-iconed category did not open on the letter pane")
        }
        editor.edit(WorkTypeCatalog.shared.definition(for: .admin))
        if editor.iconMode != .symbol || !editor.glyphText.isEmpty {
            failures.append("Editing a symbol-iconed category did not return to the symbol pane")
        }
        return failures
    }

    private static func goalsAndReminders() -> [String] {
        var failures: [String] = []
        let (store, defaults, suite) = fresh()
        defer { restore(defaults, suite) }
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        if WorkType.meetings.remindsBreaks || !WorkType.deepWork.remindsBreaks {
            failures.append("Shipped reminder rules changed: meetings off, deep work on")
        }
        if WorkType.deepWork.dailyGoal != nil { failures.append("A built-in shipped with a goal") }
        var edit = WorkTypeCatalog.shared.definition(for: .deepWork)
        edit.dailyGoal = 7_200
        edit.remindsBreaks = false
        settings.saveCategory(edit)
        if WorkType.deepWork.dailyGoal != 7_200 || WorkType.deepWork.remindsBreaks {
            failures.append("An edited built-in did not take its goal and reminder rule")
        }
        var rest = WorkTypeCatalog.shared.definition(for: .breakTime)
        rest.dailyGoal = 3_600
        rest.remindsBreaks = false
        settings.saveCategory(rest)
        if WorkType.breakTime.dailyGoal != nil || !WorkType.breakTime.remindsBreaks {
            failures.append("Rest was allowed a goal or a reminder rule")
        }
        _ = PersistenceStore(defaults: defaults)
        if WorkType.deepWork.dailyGoal != 7_200 {
            failures.append("The goal did not survive a relaunch")
        }
        let editor = CategoryEditorState()
        editor.beginNew()
        editor.name = "Calls"
        editor.symbolName = "phone.fill"
        editor.dailyGoal = 1_800
        editor.remindsBreaks = false
        guard let saved = editor.definitionForSaving(existing: WorkTypeCatalog.shared.allDefinitions) else {
            return failures + ["The editor refused a category with a goal"]
        }
        if saved.dailyGoal != 1_800 || saved.remindsBreaks {
            failures.append("The editor dropped the goal or the reminder rule")
        }
        editor.dailyGoal = 0
        if editor.definitionForSaving(existing: WorkTypeCatalog.shared.allDefinitions)?.dailyGoal != nil {
            failures.append("A goal of None did not clear the goal")
        }
        return failures
    }

    private static func learnedChoices() -> [String] {
        var failures: [String] = []
        let (store, defaults, suite) = fresh()
        defer { restore(defaults, suite) }
        let manager = CategoryManager(store: store)
        if manager.learnedWorkType(for: "com.example.app") != nil {
            failures.append("An app never started from had a learned category")
        }
        if manager.suggestedWorkType(for: "us.zoom.xos") != .meetings {
            failures.append("The fixed map no longer suggests Meetings for Zoom")
        }
        store.rememberCategoryChoice(.admin, for: "us.zoom.xos")
        store.rememberCategoryChoice(.admin, for: "us.zoom.xos")
        store.rememberCategoryChoice(.learning, for: "us.zoom.xos")
        if manager.suggestedWorkType(for: "us.zoom.xos") != .admin {
            failures.append("Two of the last three choices did not win")
        }
        store.rememberCategoryChoice(.learning, for: "us.zoom.xos")
        if manager.learnedWorkType(for: "us.zoom.xos") != .learning {
            failures.append("Only the last three choices should count")
        }
        store.rememberCategoryChoice(.deepWork, for: "us.zoom.xos")
        if manager.learnedWorkType(for: "us.zoom.xos") != .learning {
            failures.append("A single newer choice outranked a pair")
        }
        if CategoryManager.majority(of: [.admin, .learning]) != .learning {
            failures.append("A tie did not go to the most recent choice")
        }
        store.rememberCategoryChoice(.breakTime, for: "com.example.rest")
        if manager.learnedWorkType(for: "com.example.rest") != nil {
            failures.append("Rest was learned as a category to suggest")
        }
        if CategoryManager.majority(of: [WorkType(rawValue: "custom.gone")]) != nil {
            failures.append("A retired category was suggested")
        }
        return failures
    }

    private static func categoryInsight() -> [String] {
        var failures: [String] = []
        let calendar = Calendar.current
        var hours: [WorkType: [Int: TimeInterval]] = [:]
        hours[.deepWork] = [9: 3_000, 10: 3_600, 11: 600, 15: 900]
        hours[.meetings] = [14: 1_800, 15: 1_500]
        hours[.admin] = [8: 600]
        guard let insight = InsightSurface.categoryInsight(byHour: hours, days: 5, calendar: calendar) else {
            return ["No insight for two categories with evidence"]
        }
        if !insight.headline.hasPrefix("Deep work 9") || !insight.headline.contains("Meetings 2") {
            failures.append("The headline did not place the leaders in their windows: \(insight.headline)")
        }
        if insight.headline.contains("Admin") || insight.detail.contains("Admin") {
            failures.append("A category under half an hour was placed")
        }
        if !insight.detail.contains("5 days") {
            failures.append("The detail does not say how many days were read")
        }
        if InsightSurface.categoryInsight(byHour: [.admin: [8: 600]], days: 1, calendar: calendar) != nil {
            failures.append("Thin evidence produced an insight")
        }
        return failures
    }

    private static func huesAndSymbols() -> [String] {
        var failures: [String] = []
        for hue in WorkTypeHue.allCases {
            _ = Tokens.Palette.hue(hue)
            _ = StoryStyle.ink(hue)
        }
        if WorkTypeHue.selectable.contains(.grey) {
            failures.append("Grey was offered for a made category")
        }
        let missing = WorkTypeSymbols.curated.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        if !missing.isEmpty {
            failures.append("Offered symbols this macOS does not have: \(missing)")
        }
        if Set(WorkTypeSymbols.curated).count != WorkTypeSymbols.curated.count {
            failures.append("The symbol grid repeats a symbol")
        }
        for definition in WorkTypeCatalog.builtInDefinitions
            where NSImage(systemSymbolName: definition.symbolName, accessibilityDescription: nil) == nil {
            failures.append("Built-in \(definition.name) has an undrawable symbol")
        }
        return failures
    }
}

private extension Data {
    func replacingFirst(_ target: String, with replacement: String) -> Data {
        let text = String(decoding: self, as: UTF8.self)
        guard let range = text.range(of: target) else { return self }
        return Data(text.replacingCharacters(in: range, with: replacement).utf8)
    }
}
