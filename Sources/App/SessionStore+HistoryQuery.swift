import Foundation

/// What History's search field holds, and the filter read out of it. The text
/// is the one source: `SearchQuery` reads its periods, weekdays, lengths and
/// names, and the filter is built from that on every change, so a chip, a
/// menu and the field cannot disagree.
extension SessionStore {
    func setHistoryQuery(_ text: String) {
        historySearchText = text
        foldHistorySearch()
    }

    /// The app menu's pick. A name typed for an app goes from the text, so the
    /// field and the menu never name two apps.
    func setHistoryApp(_ bundleID: String?) {
        historyMenuApp = bundleID
        removeTypedPhrases(of: .app)
    }

    func setHistoryWorkType(_ workType: WorkType?) {
        historyMenuWorkType = workType
        removeTypedPhrases(of: .category)
    }

    /// Takes a chip's words out of the field. A chip from text that has since
    /// changed names a range that is not there, and changes nothing.
    func removeHistoryPhrase(_ phrase: SearchPhrase) {
        guard historyParsedSearch.phrases.contains(phrase) else { return }
        historySearchText = Self.removing(phrase.range, from: historySearchText)
        foldHistorySearch()
    }

    func clearHistoryFilters() {
        historyMenuApp = nil
        historyMenuWorkType = nil
        setHistoryQuery("")
    }

    /// Reads the text and sets the filter: the unread words search; the typed
    /// app or category stands for the menu's while it is typed.
    private func foldHistorySearch() {
        let parsed = SearchQuery.parse(historySearchText, now: now(), calendar: periodCalendar,
                                       apps: historyAppNames, categories: WorkType.allCases)
        var filter = HistoryFilter()
        filter.query = parsed.leftover
        filter.span = parsed.span
        filter.noOverlap = parsed.noOverlap
        filter.weekdays = parsed.weekdays
        filter.minLength = parsed.minLength
        filter.maxLength = parsed.maxLength
        filter.appBundleID = parsed.appBundleID ?? historyMenuApp
        filter.workType = parsed.workType ?? historyMenuWorkType
        historyParsedSearch = parsed
        historyFilter = filter
    }

    /// Removes every typed name of a kind. The parser reads only the first, so
    /// the next one, once uncovered, goes too: otherwise it would stand in for
    /// the pick just made.
    private func removeTypedPhrases(of kind: SearchPhrase.Kind) {
        foldHistorySearch()
        while let phrase = historyParsedSearch.phrases.first(where: { $0.kind == kind }) {
            removeHistoryPhrase(phrase)
        }
    }

    /// `text` without `range` and one of the spaces beside it, so the words
    /// around it stay singly spaced.
    private static func removing(_ range: Range<String.Index>, from text: String) -> String {
        var lower = range.lowerBound, upper = range.upperBound
        if upper < text.endIndex, text[upper].isWhitespace {
            upper = text.index(after: upper)
        } else if lower > text.startIndex, text[text.index(before: lower)].isWhitespace {
            lower = text.index(before: lower)
        }
        return String(text[..<lower]) + String(text[upper...])
    }
}
