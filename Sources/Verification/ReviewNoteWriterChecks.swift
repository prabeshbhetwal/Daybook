import Foundation

/// The note writer without a model: a responder stands in for Apple's, so
/// these checks cover what the writer does around it (the cache, the audit,
/// the off switch, a newer request winning). Uses the Ask fixture: Parser on
/// Tue 14 Nov, Thesis on Mon 13 Nov, the clock on Wed 15 Nov at 9:13.
enum ReviewNoteWriterChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A note for unchanged facts is written once and then served from memory", cacheHit),
        ("A note stating a figure the facts lack is never shown", failedAuditHidden),
        ("Nothing is written when Apple Intelligence is switched off", switchOff),
        ("Switching off mid-write publishes nothing when the answer returns", switchOffMidWrite),
        ("Opening another period cancels the note being written", newerWins),
        ("A note the person asks for while it is being written shows its failure", askedWhileWriting),
        ("Leaving a period cancels its note being written", leavingCancels),
        ("A week's note never carries a tip", weekHasNoTip),
        ("A day's note keeps its tip unless the tip is blank", dayTip),
        ("A day with no sessions fails quietly without asking the model", noFacts),
        ("Renaming a session writes the day's note again", renameRewrites),
    ]

    typealias Fixture = AskLookupChecks.Fixture

    /// Free of digits, so it passes the audit against any facts.
    static let plain = WrittenNote(story: "You worked on Parser.", pattern: "Focus began after lunch.", tip: nil)

    /// What a stand-in model records, and the calls it can be holding.
    final class Model {
        var calls = 0
        var facts: [NoteFacts] = []
        /// Calls held so far, and calls that have come back from being held.
        var entered = 0
        var returned = 0
        private var held: [CheckedContinuation<Void, Never>] = []

        /// Returns `note` at once.
        func answer(_ note: WrittenNote) -> @MainActor (NoteFacts) async throws -> WrittenNote {
            { [self] facts in
                calls += 1
                self.facts.append(facts)
                return note
            }
        }

        /// Holds each call until `release()`, when its facts contain `only` (always when nil); other calls answer at once.
        func hold(_ note: WrittenNote, only: String? = nil) -> @MainActor (NoteFacts) async throws -> WrittenNote {
            { [self] facts in
                calls += 1
                self.facts.append(facts)
                if only.map({ facts.text.contains($0) }) ?? true {
                    entered += 1
                    await withCheckedContinuation { held.append($0) }
                    returned += 1
                }
                return note
            }
        }

        /// Lets the call held longest return.
        func release() {
            if !held.isEmpty { held.removeFirst().resume() }
        }
    }

    /// The Ask fixture with a writer whose responder is `model`'s, on the main actor.
    static func withWriter(_ body: @MainActor (Fixture, NoteWriter, Model, inout [String]) -> Void) -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated { body(f, NoteWriter(store: f.store), Model(), &problems) }
        }
    }

    /// A day in the fixture's calendar, `back` days before the clock's day (after it when negative).
    static func day(_ f: Fixture, back: Int) -> HistoryPlace {
        let start = f.calendar.date(byAdding: .day, value: -back, to: f.calendar.startOfDay(for: f.clock.value))!
        return f.store.notePlace(forDayContaining: f.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start)!)
    }

    /// The one session on the day, as the Story lists it.
    static func session(on place: HistoryPlace, _ f: Fixture) -> DaySession? {
        f.store.storyDayProjection(on: place.start, calendar: f.calendar).sessions.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }.first
    }

    @MainActor static func settle(_ writer: NoteWriter, _ place: HistoryPlace) -> Bool {
        InstalledAppCatalog.turnRunLoop(until: { writer.state(for: place) != .writing }, timeout: 5)
    }

    // MARK: - Checks

    private static func cacheHit() -> [String] {
        withWriter { f, writer, model, problems in
            let note = WrittenNote(story: "You worked on Parser.", pattern: "Focus began after lunch.",
                                   tip: "Start with the hard part.")
            writer.responder = model.answer(note)
            let tuesday = day(f, back: 1)
            writer.request(tuesday, requested: false)
            expect(writer.state(for: tuesday) == .writing, "a request shows \(String(describing: writer.state(for: tuesday))), not writing", &problems)
            expect(settle(writer, tuesday), "the first note was not written in time", &problems)
            writer.request(tuesday, requested: false)
            expect(writer.state(for: tuesday) == .written(note), "the cached note was not served at once", &problems)
            expect(settle(writer, tuesday), "the second request never settled", &problems)
            expect(model.calls == 1, "the model was asked \(model.calls) times, not once", &problems)
            expect(writer.state(for: tuesday) == .written(note),
                   "Tuesday's note is \(String(describing: writer.state(for: tuesday)))", &problems)
            expect(model.facts.first == f.store.noteFacts(for: tuesday), "the model was not given Tuesday's facts", &problems)
        }
    }

    private static func failedAuditHidden() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.answer(WrittenNote(story: "You focused 9h 59m.", pattern: "Nothing else.", tip: nil))
            let tuesday = day(f, back: 1)
            writer.request(tuesday, requested: false)
            expect(settle(writer, tuesday), "the note never settled", &problems)
            expect(writer.state(for: tuesday) == .failed(requested: false),
                   "an invented figure left \(String(describing: writer.state(for: tuesday)))", &problems)
            // No retry: the same facts would fail the same way, so a request for them
            // shows the failure again without asking the model, as the person's.
            writer.request(tuesday, requested: true)
            expect(writer.state(for: tuesday) == .failed(requested: true) && model.calls == 1,
                   "the second request left \(String(describing: writer.state(for: tuesday))) after \(model.calls) calls", &problems)
        }
    }

    private static func switchOff() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.answer(plain)
            expect(writer.isUsable, "a responder and the switch on should be usable", &problems)
            f.store.engine.store.useAppleIntelligence = false
            expect(!writer.isUsable, "the switch off should not be usable", &problems)
            let tuesday = day(f, back: 1)
            writer.request(tuesday, requested: true)
            InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.1)
            expect(writer.states.isEmpty, "a switched-off writer published \(writer.states)", &problems)
            expect(model.calls == 0, "a switched-off writer asked the model \(model.calls) times", &problems)
        }
    }

    private static func switchOffMidWrite() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = day(f, back: 1)
            writer.request(tuesday, requested: true)
            expect(InstalledAppCatalog.turnRunLoop(until: { model.entered > 0 }, timeout: 5), "the model was never asked", &problems)
            f.store.engine.store.useAppleIntelligence = false
            model.release()
            expect(InstalledAppCatalog.turnRunLoop(until: { model.returned > 0 }, timeout: 5), "the model never returned", &problems)
            expect(settle(writer, tuesday), "the writing state was left behind", &problems)
            expect(writer.state(for: tuesday) == nil,
                   "the answer after the switch went off left \(String(describing: writer.state(for: tuesday)))", &problems)
        }
    }

    private static func newerWins() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = day(f, back: 1)
            let monday = day(f, back: 2)
            writer.request(tuesday, requested: true)
            expect(InstalledAppCatalog.turnRunLoop(until: { model.entered == 1 }, timeout: 5), "Tuesday's note was never asked for", &problems)
            writer.request(monday, requested: true)
            expect(writer.state(for: tuesday) == nil,
                   "Tuesday still shows \(String(describing: writer.state(for: tuesday))) after Monday was opened", &problems)
            expect(InstalledAppCatalog.turnRunLoop(until: { model.entered == 2 }, timeout: 5), "Monday's note was never asked for", &problems)
            // Tuesday's call comes back first, while Monday's is still being written.
            model.release()
            expect(InstalledAppCatalog.turnRunLoop(until: { model.returned == 1 }, timeout: 5), "Tuesday's call never returned", &problems)
            InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.1)
            expect(writer.state(for: tuesday) == nil && writer.state(for: monday) == .writing,
                   "Tuesday's late answer left Tuesday \(String(describing: writer.state(for: tuesday))) and Monday \(String(describing: writer.state(for: monday)))", &problems)
            model.release()
            expect(settle(writer, monday) && writer.state(for: monday) == .written(plain),
                   "Monday's note is \(String(describing: writer.state(for: monday)))", &problems)
            expect(writer.state(for: tuesday) == nil, "Tuesday shows \(String(describing: writer.state(for: tuesday)))", &problems)
        }
    }

    /// The Yesterday notice asks on its own; the person's button is the same
    /// note, and its failure is one they are owed.
    private static func askedWhileWriting() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.hold(WrittenNote(story: "You focused 9h 59m.", pattern: "Nothing else.", tip: nil))
            let tuesday = day(f, back: 1)
            writer.request(tuesday, requested: false)
            expect(InstalledAppCatalog.turnRunLoop(until: { model.entered > 0 }, timeout: 5), "the model was never asked", &problems)
            writer.request(tuesday, requested: true)
            model.release()
            expect(settle(writer, tuesday), "the note never settled", &problems)
            expect(writer.state(for: tuesday) == .failed(requested: true) && model.calls == 1,
                   "after \(model.calls) calls the note shows \(String(describing: writer.state(for: tuesday)))", &problems)
        }
    }

    private static func leavingCancels() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.hold(plain)
            let tuesday = day(f, back: 1)
            writer.request(tuesday, requested: true)
            expect(InstalledAppCatalog.turnRunLoop(until: { model.entered > 0 }, timeout: 5), "the model was never asked", &problems)
            writer.cancel(day(f, back: 2))
            expect(writer.state(for: tuesday) == .writing, "cancelling another day stopped Tuesday's note", &problems)
            writer.cancel(tuesday)
            expect(writer.state(for: tuesday) == nil,
                   "a cancelled note shows \(String(describing: writer.state(for: tuesday)))", &problems)
            model.release()
            expect(InstalledAppCatalog.turnRunLoop(until: { model.returned > 0 }, timeout: 5), "the call never returned", &problems)
            InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.1)
            expect(writer.state(for: tuesday) == nil,
                   "the late answer to a cancelled note left \(String(describing: writer.state(for: tuesday)))", &problems)
            // Asking again after a cancel writes it: the old call is not what answers.
            writer.responder = model.answer(plain)
            writer.request(tuesday, requested: true)
            expect(settle(writer, tuesday) && writer.state(for: tuesday) == .written(plain),
                   "the note asked for again is \(String(describing: writer.state(for: tuesday)))", &problems)
        }
    }

    private static func weekHasNoTip() -> [String] {
        withWriter { f, writer, model, problems in
            f.store.setReviewVisible(true)
            writer.responder = model.answer(WrittenNote(story: plain.story, pattern: plain.pattern, tip: "Plan the week."))
            let week = HistoryPlace(level: .week, span: HistoryTreeBuilder.period(.week, containing: f.clock.value,
                                                                                 calendar: f.calendar))
            writer.request(week, requested: true)
            expect(settle(writer, week), "the week's note never settled", &problems)
            expect(writer.state(for: week) == .written(plain),
                   "the week's note is \(String(describing: writer.state(for: week)))", &problems)
        }
    }

    private static func dayTip() -> [String] {
        withWriter { f, _, model, problems in
            let tuesday = day(f, back: 1)
            let tips: [(String?, String?)] = [("  Start with the hard part.\n", "Start with the hard part."),
                                              ("  \n", nil), (nil, nil)]
            for (given, want) in tips {
                // The same facts hit the cache, so each tip gets a fresh writer.
                let writer = NoteWriter(store: f.store)
                writer.responder = model.answer(WrittenNote(story: plain.story, pattern: plain.pattern, tip: given))
                writer.request(tuesday, requested: true)
                expect(settle(writer, tuesday), "the note for tip \(String(describing: given)) never settled", &problems)
                expect(writer.state(for: tuesday) == .written(WrittenNote(story: plain.story, pattern: plain.pattern, tip: want)),
                       "the tip \(String(describing: given)) came out as \(String(describing: writer.state(for: tuesday)))", &problems)
            }
        }
    }

    private static func noFacts() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.answer(plain)
            let empty = day(f, back: -4)
            writer.request(empty, requested: false)
            expect(writer.state(for: empty) == .failed(requested: false),
                   "a day with no sessions shows \(String(describing: writer.state(for: empty)))", &problems)
            writer.request(empty, requested: true)
            expect(writer.state(for: empty) == .failed(requested: true), "a requested note for it did not fail as requested", &problems)
            expect(model.calls == 0, "the model was asked \(model.calls) times for a day with no sessions", &problems)
        }
    }

    private static func renameRewrites() -> [String] {
        withWriter { f, writer, model, problems in
            writer.responder = model.answer(plain)
            let tuesday = day(f, back: 1)
            writer.request(tuesday, requested: true)
            expect(settle(writer, tuesday) && model.calls == 1, "the first note was not written once", &problems)
            guard let parser = session(on: tuesday, f) else { problems.append("Tuesday has no session to rename"); return }
            expect(f.store.renameSession(parser, to: "Lexer"), "the rename was refused", &problems)
            writer.request(tuesday, requested: true)
            expect(settle(writer, tuesday), "the second note never settled", &problems)
            expect(model.calls == 2, "the renamed day asked the model \(model.calls) times, not twice", &problems)
            expect(model.facts.last?.text.contains("Lexer") == true,
                   "the second request was written from “\(model.facts.last?.text ?? "nothing")”", &problems)
            expect(writer.state(for: tuesday) == .written(plain),
                   "the renamed day's note is \(String(describing: writer.state(for: tuesday)))", &problems)
        }
    }
}
