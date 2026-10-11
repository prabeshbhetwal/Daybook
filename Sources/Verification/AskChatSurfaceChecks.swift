import SwiftUI

/// What the Ask chat draws and says: how many sources show before "Show N
/// more", the links inside an answer, what VoiceOver reads, the sheet's size
/// and the render of a whole chat. `AskPanelChecks` carries these in its list.
enum AskChatSurfaceChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An answer's sources show five rows, then Show N more", sourcesShowFiveThenMore),
        ("Each place an answer names becomes a link to its source row", mentionsBecomeLinks),
        ("The spaces inside a linked date do not break, and the rest of the answer is as written", linkedSpacesDoNotBreak),
        ("Links never overlap: a mention inside one already placed gets none", overlappingMentionsKeepTheFirst),
        ("A mention is found by Character offsets, after an emoji or a decomposed accent", offsetsAreCharacters),
        ("A link in an answer opens its source, and any other URL opens nothing", linkURLsOnlyFollowSources),
        ("A source reads aloud as its full label, its role and Opens in History", longLabelKeepsFullTextForVoiceOver),
        ("A turn reads as what was asked and what Ask answered, and a finished answer counts its sources",
         turnsAndAnswersAreSpoken),
        ("The Ask sheet is 640 by 600 points, shrinking with the window", sheetSize),
        ("The chat draws its transcript and the sources of an answer, and none for a stopped or failed turn",
         chatRendersTurnsAndSources),
    ]

    /// Dates come from the calendar the picker is given, so the suite holds in any zone.
    private enum Fixture {
        static let calendar = Calendar.current.forPeriods

        static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }

        /// Saturday 10 October 2026.
        static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 17, minute: 30))!

        static func day(_ month: Int, _ day: Int, label: String, role: AskSourceRole = .bestDay) -> AskLink {
            AskLink(target: .day(date(2026, month, day)), label: label, role: role)
        }

        static let tue15 = day(9, 15, label: "Tue 15 Sep")
        static let september = AskLink(
            target: .period(HistoryPlace(level: .month, span: DateInterval(start: date(2026, 9, 1), end: date(2026, 10, 1)))),
            label: "September 2026", role: .totals)
    }

    /// The Character offsets of `words` in `answer`, as the picker reports a mention.
    private static func offsets(of words: String, in answer: String) -> Range<Int> {
        let found = answer.range(of: words)!
        return answer.distance(from: answer.startIndex, to: found.lowerBound)
            ..< answer.distance(from: answer.startIndex, to: found.upperBound)
    }

    private static func source(_ link: AskLink, _ words: String?, in answer: String) -> AskSource {
        AskSource(link: link, mention: words.map { offsets(of: $0, in: answer) })
    }

    /// The spaces inside a link do not break (`AskTurnView.attributed`); read as plain ones.
    private static func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{00A0}", with: " ") }

    /// The text and target of every link in `text`, in order.
    private static func links(in text: AttributedString) -> [String] {
        text.runs.compactMap { run in
            run.link.map { "\(plain(String(text[run.range].characters))) -> \($0.absoluteString)" }
        }
    }

    // MARK: - Sources

    private static func sourcesShowFiveThenMore() -> [String] {
        var problems: [String] = []
        let sources = (1...8).map { AskSource(link: Fixture.day(9, $0, label: "Day \($0)"), mention: nil) }
        let collapsed = AskSourcesView.visible(sources, expanded: false)
        expect(collapsed.shown == Array(sources.prefix(5)) && collapsed.hidden == 3,
               "eight sources show \(collapsed.shown.count), hiding \(collapsed.hidden)", &problems)
        let expanded = AskSourcesView.visible(sources, expanded: true)
        expect(expanded.shown == sources && expanded.hidden == 0,
               "expanded, eight sources show \(expanded.shown.count), hiding \(expanded.hidden)", &problems)
        let five = AskSourcesView.visible(Array(sources.prefix(5)), expanded: false)
        expect(five.shown.count == 5 && five.hidden == 0, "five sources hide \(five.hidden)", &problems)
        let none = AskSourcesView.visible([], expanded: false)
        expect(none.shown.isEmpty && none.hidden == 0, "no sources show \(none.shown.count), hiding \(none.hidden)", &problems)
        return problems
    }

    // MARK: - Links in the text

    private static func mentionsBecomeLinks() -> [String] {
        var problems: [String] = []
        let answer = "In September 2026, the best day was Tue 15 Sep."
        let sources = [source(Fixture.september, "September 2026", in: answer),
                       source(Fixture.tue15, "Tue 15 Sep", in: answer)]
        let text = AskTurnView.attributed(answer: answer, sources: sources)
        expect(plain(String(text.characters)) == answer, "the answer reads “\(String(text.characters))”", &problems)
        expect(links(in: text) == ["September 2026 -> daybook-ask://source/0", "Tue 15 Sep -> daybook-ask://source/1"],
               "the links are \(links(in: text))", &problems)

        // A source the answer does not name gets no link, and the others keep their rows' numbers.
        let withAnchor = [AskSource(link: Fixture.day(9, 1, label: "Tue 1 Sep"), mention: nil)] + sources
        expect(links(in: AskTurnView.attributed(answer: answer, sources: withAnchor))
                == ["September 2026 -> daybook-ask://source/1", "Tue 15 Sep -> daybook-ask://source/2"],
               "an unnamed source shifted the links to \(links(in: AskTurnView.attributed(answer: answer, sources: withAnchor)))",
               &problems)
        expect(links(in: AskTurnView.attributed(answer: answer, sources: [])).isEmpty, "no sources made a link", &problems)
        return problems
    }

    /// At 140% "Tue 15 Sep" was split across two lines. The spaces inside a link are
    /// non-breaking; the length, the words and every other space are as written.
    private static func linkedSpacesDoNotBreak() -> [String] {
        var problems: [String] = []
        let answer = "In September 2026, the best day was Tue 15 Sep, with 2h."
        let sources = [source(Fixture.september, "September 2026", in: answer),
                       source(Fixture.tue15, "Tue 15 Sep", in: answer)]
        let text = AskTurnView.attributed(answer: answer, sources: sources)
        let shown = String(text.characters)
        expect(shown.count == answer.count && plain(shown) == answer, "the answer reads “\(shown)”", &problems)
        for run in text.runs {
            let words = String(text[run.range].characters)
            if run.link != nil {
                expect(!words.contains(" ") && words.contains("\u{00A0}"), "the link “\(words)” can still break", &problems)
            } else {
                expect(!words.contains("\u{00A0}"), "“\(words)” outside a link cannot break", &problems)
            }
        }
        return problems
    }

    private static func overlappingMentionsKeepTheFirst() -> [String] {
        var problems: [String] = []
        let answer = "The best week was 5 Oct to 11 Oct."
        let week = AskLink(
            target: .period(HistoryPlace(level: .week, span: DateInterval(start: Fixture.date(2026, 10, 5),
                                                                          end: Fixture.date(2026, 10, 12)))),
            label: "5 Oct \u{2013} 11 Oct", role: .bestWeek)
        let sunday = Fixture.day(10, 11, label: "Sun 11 Oct")
        let weekMention = source(week, "5 Oct to 11 Oct", in: answer)
        let dayMention = source(sunday, "11 Oct", in: answer)

        expect(links(in: AskTurnView.attributed(answer: answer, sources: [weekMention, dayMention]))
                == ["5 Oct to 11 Oct -> daybook-ask://source/0"],
               "a week and its last day made \(links(in: AskTurnView.attributed(answer: answer, sources: [weekMention, dayMention])))",
               &problems)
        expect(links(in: AskTurnView.attributed(answer: answer, sources: [dayMention, weekMention]))
                == ["11 Oct -> daybook-ask://source/0"],
               "the list's order decides which link stays, got \(links(in: AskTurnView.attributed(answer: answer, sources: [dayMention, weekMention])))",
               &problems)

        // Two places the answer names with the same words: the first one links.
        let yearless = "Your best day was 15 September."
        let sameWords = [source(Fixture.tue15, "15 September", in: yearless),
                         source(Fixture.day(9, 15, label: "Tue 15 Sep", role: .totals), "15 September", in: yearless)]
        expect(links(in: AskTurnView.attributed(answer: yearless, sources: sameWords))
                == ["15 September -> daybook-ask://source/0"],
               "one set of words linked twice: \(links(in: AskTurnView.attributed(answer: yearless, sources: sameWords)))",
               &problems)

        // Touching is not overlapping, and a mention outside the answer is no link at all.
        let touching = [AskSource(link: Fixture.tue15, mention: 0..<2), AskSource(link: Fixture.september, mention: 2..<4)]
        expect(links(in: AskTurnView.attributed(answer: "ABCD", sources: touching))
                == ["AB -> daybook-ask://source/0", "CD -> daybook-ask://source/1"],
               "neighbouring mentions made \(links(in: AskTurnView.attributed(answer: "ABCD", sources: touching)))", &problems)
        let outside = [AskSource(link: Fixture.tue15, mention: -1..<2), AskSource(link: Fixture.september, mention: 3..<99),
                       AskSource(link: Fixture.tue15, mention: 2..<2)]
        expect(links(in: AskTurnView.attributed(answer: "ABCD", sources: outside)).isEmpty,
               "a mention outside the answer made \(links(in: AskTurnView.attributed(answer: "ABCD", sources: outside)))",
               &problems)
        return problems
    }

    /// Mentions are Character offsets. An emoji is two UTF-16 units and a decomposed
    /// accent is two scalars, so counting either would move the link along the text.
    private static func offsetsAreCharacters() -> [String] {
        var problems: [String] = []
        for lead in ["\u{1F389} ", "Cafe\u{0301} ", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} ", "\u{1F1E6}\u{1F1FA} "] {
            let answer = lead + "The best day was Tue 15 Sep, with 2h."
            let picked = AskSourcePicker.sources(answer: answer, lookups: [[Fixture.tue15]], calendar: Fixture.calendar,
                                                 now: Fixture.now)
            expect(picked.first?.mention == offsets(of: "Tue 15 Sep", in: answer),
                   "after “\(lead)” the mention is \(String(describing: picked.first?.mention)), "
                   + "not \(offsets(of: "Tue 15 Sep", in: answer))", &problems)
            expect(links(in: AskTurnView.attributed(answer: answer, sources: picked)) == ["Tue 15 Sep -> daybook-ask://source/0"],
                   "after “\(lead)” the link is \(links(in: AskTurnView.attributed(answer: answer, sources: picked)))",
                   &problems)
        }
        return problems
    }

    private static func linkURLsOnlyFollowSources() -> [String] {
        var problems: [String] = []
        let sources = [AskSource(link: Fixture.september, mention: nil), AskSource(link: Fixture.tue15, mention: nil)]
        func followed(_ url: String) -> AskLink? { URL(string: url).flatMap { AskTurnView.link(for: $0, in: sources) } }
        expect(followed("daybook-ask://source/0") == Fixture.september, "source/0 followed \(String(describing: followed("daybook-ask://source/0")))", &problems)
        expect(followed("daybook-ask://source/1") == Fixture.tue15, "source/1 followed \(String(describing: followed("daybook-ask://source/1")))", &problems)
        for other in ["daybook-ask://source/2", "daybook-ask://source/-1", "daybook-ask://source/x", "daybook-ask://other/0",
                      "https://example.com/source/0", "daybook://source/0", "x-apple.systempreferences:com.apple.Siri-Settings.extension"] {
            expect(followed(other) == nil, "\(other) followed \(String(describing: followed(other)))", &problems)
        }
        return problems
    }

    // MARK: - VoiceOver

    private static func longLabelKeepsFullTextForVoiceOver() -> [String] {
        var problems: [String] = []
        let name = "Thesis chapter " + String(repeating: "four and its long appendix ", count: 4) + "· Mon 3 Aug"
        let long = AskSource(link: AskLink(target: .session(thread: UUID(), day: Fixture.date(2026, 8, 3)), label: name,
                                           role: .longestSession), mention: nil)
        expect(name.count > 100, "the label is only \(name.count) characters", &problems)
        expect(AskSourcesView.accessibilityLabel(for: long) == "\(name), longest session. Opens in History.",
               "a long label reads “\(AskSourcesView.accessibilityLabel(for: long))”", &problems)
        let day = AskSource(link: Fixture.day(8, 3, label: "Mon 3 Aug"), mention: nil)
        expect(AskSourcesView.accessibilityLabel(for: day) == "Mon 3 Aug, most focused day. Opens in History.",
               "a day reads “\(AskSourcesView.accessibilityLabel(for: day))”", &problems)
        return problems
    }

    private static func turnsAndAnswersAreSpoken() -> [String] {
        var problems: [String] = []
        let sources = [AskSource(link: Fixture.september, mention: nil), AskSource(link: Fixture.tue15, mention: nil)]
        let answered = AskTurn(question: "When did I focus most?", answer: "Tue 15 Sep, 4h 30m.", state: .answered,
                               sources: sources)
        expect(AskTurnView.spokenLabel(for: answered)
                == "You asked When did I focus most? Ask answered Tue 15 Sep, 4 hours 30 minutes.",
               "the turn reads “\(AskTurnView.spokenLabel(for: answered))”", &problems)
        expect(AskChatView.announcement(for: answered) == "Tue 15 Sep, 4 hours 30 minutes. 2 sources.",
               "the answer is announced as “\(AskChatView.announcement(for: answered))”", &problems)
        var one = answered
        one.sources = [sources[0]]
        expect(AskChatView.announcement(for: one) == "Tue 15 Sep, 4 hours 30 minutes. 1 source.",
               "one source is announced as “\(AskChatView.announcement(for: one))”", &problems)
        one.sources = []
        expect(AskChatView.announcement(for: one) == "Tue 15 Sep, 4 hours 30 minutes.",
               "no sources are announced as “\(AskChatView.announcement(for: one))”", &problems)
        let stopped = AskTurn(question: "And in August?", answer: "In August", state: .stopped)
        expect(AskTurnView.spokenLabel(for: stopped) == "You asked And in August? Ask answered In August. Stopped.",
               "a stopped turn reads “\(AskTurnView.spokenLabel(for: stopped))”", &problems)
        let failed = AskTurn(question: "Why", state: .failed(AskNotice(text: "Can't answer that one.", opensSettings: false)))
        expect(AskTurnView.spokenLabel(for: failed) == "You asked Why. Can't answer that one.",
               "a failed turn reads “\(AskTurnView.spokenLabel(for: failed))”", &problems)
        return problems
    }

    // MARK: - Size and render

    private static func sheetSize() -> [String] {
        var problems: [String] = []
        let roomy = SettingsLayout.sheetSize(for: .ask, within: nil)
        expect(roomy == CGSize(width: 640.zoomed, height: 600.zoomed), "the Ask sheet is \(roomy), not 640 × 600", &problems)
        let fits = SettingsLayout.sheetSize(for: .ask, within: CGSize(width: 1_000.zoomed, height: 680.zoomed))
        expect(abs(fits.height - 600.zoomed) < 0.001,
               "in a 1000 × 680 window the Ask sheet is \(fits.height) tall, not 600", &problems)
        let short = SettingsLayout.sheetSize(for: .ask, within: CGSize(width: 980.zoomed, height: 600.zoomed))
        expect(abs(short.height - 520.zoomed) < 0.001,
               "in a 980 × 600 window the Ask sheet is \(short.height) tall, not 520", &problems)
        return problems
    }

    private static func chatRendersTurnsAndSources() -> [String] {
        AskThreadChecks.withModel { _, model, problems in
            @MainActor func evidence(_ turns: [AskTurn]) -> Set<StoryRenderEvidence> {
                model.present(turns: turns)
                return StoryWorkspaceChecks.renderFrame(AskChatView(model: model, onFollow: { _ in }),
                                                        width: 640, height: 600).evidence
            }
            let answer = "In September 2026, the best day was Tue 15 Sep."
            let answered = AskTurn(question: "When did I focus most?", answer: answer, state: .answered,
                                   sources: [source(Fixture.september, "September 2026", in: answer),
                                             source(Fixture.tue15, "Tue 15 Sep", in: answer)])
            let shown = evidence([answered, AskTurn(question: "And in August?", answer: "In Au", state: .answering)])
            expect(shown.contains(.askTranscript) && shown.contains(.askSources),
                   "a chat with an answer and its sources drew \(shown.map(\.rawValue).sorted())", &problems)

            let stopped = evidence([AskTurn(question: "And in August?", answer: "In August", state: .stopped)])
            expect(stopped.contains(.askTranscript) && !stopped.contains(.askSources),
                   "a stopped turn drew \(stopped.map(\.rawValue).sorted())", &problems)
            let failed = evidence([AskTurn(question: "Why", state: .failed(AskNotice(text: "Can't answer that one.",
                                                                                    opensSettings: false)))])
            expect(failed.contains(.askTranscript) && !failed.contains(.askSources),
                   "a failed turn drew \(failed.map(\.rawValue).sorted())", &problems)
            let empty = evidence([])
            expect(!empty.contains(.askTranscript) && !empty.contains(.askSources),
                   "an empty chat drew \(empty.map(\.rawValue).sorted())", &problems)
        }
    }
}
