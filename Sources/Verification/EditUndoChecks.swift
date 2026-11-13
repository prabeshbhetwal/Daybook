import AppKit
import Foundation

/// Edit > Undo (⌘Z) reverses the newest correction, as the day story's Undo
/// banner does, and never takes ⌘Z from a text field being edited.
enum EditUndoChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Edit > Undo names the correction and its session, and is enabled only when it can act", menuFollowsState),
        ("Edit > Undo leaves a text field being edited to its own undo", textKeepsItsUndo),
        ("Edit > Undo reverses the newest correction once, never while typing or outside the main window", undoesNewestOnce),
        ("Edit > Undo takes back an away answer as its banner does", undoesAwayAnswer),
        ("Edit > Undo goes on to the earlier correction after an away answer is taken back", chainSurvivesAwayAnswer),
        ("Edit > Undo is not offered while a new away question waits", nothingWhileAwayQuestionWaits),
    ]

    private static let mainKey = EditUndo.Context(inMainWindow: true)

    private final class Rig {
        let clock: TestClock
        let engine: SessionEngine
        let store: SessionStore
        /// How many times ⌘Z was handed to the system's undo.
        var forwarded = 0
        let thread = UUID()

        init() {
            let clock = TestClock(SelfTest.anchoredNow())
            let engine = SelfTest.makeEngine(clock)
            self.clock = clock
            self.engine = engine
            store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        }

        /// One archived session, "Planning", from half an hour ago.
        func archivedSession() -> DaySession {
            let start = clock.value.addingTimeInterval(-1_800)
            let end = start.addingTimeInterval(600)
            engine.archive.append(SessionRecord(name: "Planning", workType: .deepWork, start: start,
                                                end: end, workSeconds: 600, threadID: thread))
            return DaySession(id: thread, threadID: thread, name: "Planning", workType: .deepWork,
                              start: start, end: end, worked: 600, stretches: 1,
                              spans: [DateInterval(start: start, end: end)], isRunning: false)
        }

        func record() -> SessionRecord? { engine.archive.records.first { $0.threadID == thread } }

        /// Ten minutes of work, then twenty away: the away question is waiting.
        func awayAndBack() {
            clock.advance(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(1_200)
            engine.transition(on: .awayEnded)
            store.catchUpWithEngine()
        }

        /// ⌘Z through the command path, with the system's undo counted.
        @MainActor func undo(_ context: EditUndo.Context = EditUndoChecks.mainKey) -> EditUndo.Route {
            EditUndo.performUndo(on: store, context: context) { self.forwarded += 1 }
        }
    }

    private static func menuFollowsState() -> [String] {
        var problems: [String] = []
        let limit = String(repeating: "x", count: EditUndoKind.nameLimit)
        let named: [(EditUndoKind, String)] = [
            (.rename("Final plan"), "Undo Rename “Final plan”"),
            (.category("Planning"), "Undo Change Category “Planning”"),
            (.removal("Planning"), "Undo Remove Session “Planning”"),
            (.rename(""), "Undo Rename"),
            (.removal(" \n "), "Undo Remove Session"),
            (.rename("  Final \n plan  "), "Undo Rename “Final plan”"),
            (.removal(limit), "Undo Remove Session “\(limit)”"),
            (.removal(limit + "x"), "Undo Remove Session “\(limit.dropLast())…”"),
            (.removal("A very long session name that keeps going"), "Undo Remove Session “A very long session nam…”"),
            (.awayAnswer(.tookBreak), "Undo Break"),
            (.awayAnswer(.mergeTime), "Undo Count as Focus"),
            (.awayAnswer(.continueSession), "Undo Leave Uncounted"),
        ]
        for (kind, title) in named {
            let items = EditUndo.items(kind, mainKey)
            expect(items.undoTitle == title && items.undoEnabled,
                   "\(kind) should read \(title) and be enabled, got \(items.undoTitle) \(items.undoEnabled)",
                   &problems)
            expect(!items.undoTitle.contains("\u{2014}"), "\(items.undoTitle) has an em dash", &problems)
        }
        let nothing = EditUndo.items(nil, mainKey)
        expect(nothing.undoTitle == "Undo" && !nothing.undoEnabled,
               "nothing to undo should leave a disabled \"Undo\", got \(nothing)", &problems)

        // Outside the main window the store is never reached: only the
        // window's own history can enable it.
        let settings = EditUndo.Context(inMainWindow: false)
        expect(!EditUndo.items(.rename("Final plan"), settings).undoEnabled,
               "a correction was offered outside the main window", &problems)
        let withHistory = EditUndo.Context(inMainWindow: false, systemUndo: "Undo Search")
        let system = EditUndo.items(.rename("Final plan"), withHistory)
        expect(system.undoEnabled && system.undoTitle == "Undo Search"
               && EditUndo.route(.rename("Final plan"), withHistory) == .system,
               "the window's own undo should stay reachable outside the main window, got \(system)", &problems)

        // In the main window the window's own history goes before a correction:
        // a search rescue may be newer. With none, the correction is next.
        let rescue = EditUndo.Context(inMainWindow: true, systemUndo: "Undo")
        expect(EditUndo.route(nil, rescue) == .system, "the window's history was hidden", &problems)
        expect(EditUndo.route(.rename("Final plan"), rescue) == .system,
               "a correction was undone before a newer search rescue", &problems)

        // Typing: always the system's, enabled, whatever the store holds.
        for typing in [EditUndo.Context(inMainWindow: true, isEditingText: true),
                       EditUndo.Context(inMainWindow: true, isEditingText: true, systemUndo: "Undo Typing")] {
            let whileTyping = EditUndo.items(.rename("Final plan"), typing)
            expect(whileTyping.undoTitle == (typing.systemUndo ?? "Undo") && whileTyping.undoEnabled
                   && whileTyping.redoEnabled && EditUndo.route(.rename("Final plan"), typing) == .system,
                   "typing should keep the system's Undo and Redo, got \(whileTyping)", &problems)
        }

        // Redo is only ever the system's.
        expect(!EditUndo.items(.rename("Final plan"), mainKey).redoEnabled,
               "Redo was offered with nothing to redo", &problems)
        let redo = EditUndo.items(nil, EditUndo.Context(inMainWindow: true, systemRedo: "Redo Typing"))
        expect(redo.redoEnabled && redo.redoTitle == "Redo Typing", "the system's redo was hidden, got \(redo)", &problems)
        return problems
    }

    private static func textKeepsItsUndo() -> [String] {
        var problems: [String] = []
        let readOnlyText = NSTextView(frame: .zero)
        readOnlyText.isEditable = false
        let label = NSTextField(frame: .zero)
        label.isEditable = false
        expect(EditUndo.isEditingText(NSTextView(frame: .zero)), "an editable text view was not text", &problems)
        expect(EditUndo.isEditingText(NSTextField(frame: .zero)), "an editable text field was not text", &problems)
        expect(!EditUndo.isEditingText(readOnlyText), "read-only text took ⌘Z from the corrections", &problems)
        expect(!EditUndo.isEditingText(label), "a label took ⌘Z from the corrections", &problems)
        expect(!EditUndo.isEditingText(NSView(frame: .zero)), "a plain view counted as text", &problems)
        expect(!EditUndo.isEditingText(NSButton(frame: .zero)), "a button counted as text", &problems)
        expect(!EditUndo.isEditingText(nil), "no responder counted as text", &problems)
        return problems
    }

    /// A rename then a category change on one archived session. ⌘Z while typing
    /// or outside the main window must not touch them, and a search rescue goes
    /// first; in the main window it then reverses the category change, then the
    /// rename, then nothing.
    private static func undoesNewestOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = Rig()
            let row = rig.archivedSession()

            expect(rig.store.editUndoKind == nil, "Undo was offered before any correction", &problems)
            expect(rig.undo() == .nothing && rig.forwarded == 0, "an empty history was handed to the system", &problems)

            guard rig.store.renameSession(row, to: "Final plan"),
                  rig.store.setWorkType(.admin, threadID: rig.thread) else {
                return problems + ["the fixture's corrections were refused"]
            }
            expect(rig.store.canUndoCorrection && rig.store.editUndoKind == .category("Final plan"),
                   "the newest correction should be the category change, got \(String(describing: rig.store.editUndoKind))",
                   &problems)

            // Typing, a search rescue and other windows: corrections untouched.
            expect(rig.undo(EditUndo.Context(inMainWindow: true, isEditingText: true)) == .system
                   && rig.forwarded == 1, "typing did not reach the system's undo", &problems)
            expect(rig.undo(EditUndo.Context(inMainWindow: true, systemUndo: "Undo")) == .system
                   && rig.forwarded == 2, "a newer search rescue was skipped for a correction", &problems)
            expect(rig.undo(EditUndo.Context(inMainWindow: false)) == .nothing && rig.forwarded == 2,
                   "another window reached the corrections or the system", &problems)
            expect(rig.record()?.name == "Final plan" && rig.record()?.workType == .admin,
                   "⌘Z outside the main window or while typing changed a correction", &problems)

            // The main window: one correction per press.
            expect(rig.undo() == .correction(.category("Final plan")),
                   "the first ⌘Z did not take the category change", &problems)
            expect(rig.record()?.workType == .deepWork && rig.record()?.name == "Final plan",
                   "the first ⌘Z should undo only the category, got \(String(describing: rig.record()))", &problems)
            expect(rig.store.editUndoKind == .rename("Final plan"), "the rename should be next", &problems)
            expect(rig.undo() == .correction(.rename("Final plan")) && rig.record()?.name == "Planning",
                   "the second ⌘Z did not undo the rename", &problems)
            expect(!rig.store.canUndoCorrection && rig.store.editUndoKind == nil,
                   "Undo stayed offered with no correction left", &problems)
            expect(rig.undo() == .nothing && rig.forwarded == 2 && rig.record()?.name == "Planning",
                   "a third ⌘Z did something", &problems)
            return problems
        }
    }

    private static func undoesAwayAnswer() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = Rig()
            rig.engine.start(workType: .deepWork, intent: "Parser")
            rig.awayAndBack()
            expect(rig.store.editUndoKind == nil, "Undo was offered while the away question waited", &problems)

            rig.store.resolve(.tookBreak, label: "Lunch")
            rig.clock.advance(300)
            rig.engine.stop()
            rig.store.catchUpWithEngine()
            let work = rig.engine.archive.records.filter { $0.workType.countsAsFocus }
            expect(rig.store.editUndoKind == .awayAnswer(.tookBreak)
                   && EditUndo.items(rig.store.editUndoKind, mainKey).undoTitle == "Undo Break",
                   "the break answer should read \"Undo Break\", got \(String(describing: rig.store.editUndoKind))",
                   &problems)
            let route = rig.undo()
            expect(route == .correction(.awayAnswer(.tookBreak)) && rig.forwarded == 0,
                   "⌘Z should take the break answer back itself, got \(route)", &problems)
            expect(rig.engine.archive.records == work, "Undo removed or rewrote work after the answer", &problems)
            expect(rig.store.editUndoKind == nil, "Undo stayed offered after the answer was taken back", &problems)
            return problems
        }
    }

    /// Rename a session, answer an away question with a break, then ⌘Z twice:
    /// the break, then the rename. Taking the break back must not end the chain.
    private static func chainSurvivesAwayAnswer() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = Rig()
            guard rig.store.renameSession(rig.archivedSession(), to: "Final plan") else {
                return ["the fixture's rename was refused"]
            }
            rig.engine.start(workType: .deepWork, intent: "Parser")
            rig.awayAndBack()
            rig.store.resolve(.tookBreak, label: "Lunch")
            rig.clock.advance(300)
            rig.engine.stop()
            rig.store.catchUpWithEngine()

            let first = rig.undo()
            expect(first == .correction(.awayAnswer(.tookBreak)) && !rig.engine.archive.records.contains { $0.workType == .breakTime },
                   "the first ⌘Z should take the break back, got \(first)", &problems)
            expect(rig.record()?.name == "Final plan", "the first ⌘Z touched the rename", &problems)
            expect(rig.store.canUndoCorrection, "taking the break back ended the ⌘Z chain", &problems)
            expect(rig.store.editUndoKind == .rename("Final plan"),
                   "the rename should be next, got \(String(describing: rig.store.editUndoKind))", &problems)

            let second = rig.undo()
            expect(second == .correction(.rename("Final plan")) && rig.record()?.name == "Planning",
                   "the second ⌘Z should undo the rename, got \(second)", &problems)
            expect(rig.forwarded == 0, "the system's undo was asked as well", &problems)
            return problems
        }
    }

    /// An earlier answer is not offered while a new question waits: the engine
    /// refuses it, and an older correction is not skipped to.
    private static func nothingWhileAwayQuestionWaits() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = Rig()
            guard rig.store.renameSession(rig.archivedSession(), to: "Final plan") else {
                return ["the fixture's rename was refused"]
            }
            rig.engine.start(workType: .deepWork, intent: "Parser")
            rig.awayAndBack()
            rig.store.resolve(.tookBreak, label: "Lunch")
            rig.awayAndBack()
            guard rig.store.hasUnresolvedAwayDecision else {
                return ["the fixture did not reach a waiting away question"]
            }
            let breaks = rig.engine.archive.records.filter { $0.workType == .breakTime }
            expect(rig.store.canUndoCorrection, "the earlier answer and rename should still be undoable later", &problems)
            expect(rig.store.editUndoKind == nil,
                   "Undo was offered while an away question waited, got \(String(describing: rig.store.editUndoKind))",
                   &problems)
            expect(rig.undo() == .nothing && rig.forwarded == 0, "⌘Z acted while an away question waited", &problems)
            expect(rig.engine.archive.records.filter { $0.workType == .breakTime } == breaks && rig.record()?.name == "Final plan",
                   "⌘Z changed history while an away question waited", &problems)
            return problems
        }
    }
}
