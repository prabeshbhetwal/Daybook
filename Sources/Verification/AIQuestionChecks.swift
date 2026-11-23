import Foundation
import AppKit

/// What the model is told about a session and how a label looks (Phase C, rulings C5, C16, C10 and C27): the
/// question's text is built from a plain facts value that cannot hold a name, note, title or address, and an
/// unkept label reaches the catalogue only as a hidden category.
enum AIQuestionChecks: CheckSuite {
    typealias Fixture = AIFixture

    static let tests: [(String, () -> [String])] = [
        ("Minutes are whole minutes rounded from seconds, and never negative", minutesRounding),
        ("The question lists the activities with minutes, the depth, up to two apps, the site kind when present, then at most 20 numbered categories",
         questionText),
        ("The question carries no session name, note, bundle identifier or address, and its minutes are the shape's seconds rounded",
         questionPrivacy),
        ("Every purpose has a look whose symbol exists and is in the category editor, and whose colour is never grey",
         looks),
        ("Unkept labels become hidden categories that resolve by id, count toward focus as made, and join no list",
         hiddenLabels),
    ]

    private static func minutesRounding() -> [String] {
        var problems: [String] = []
        let cases: [(TimeInterval, Int)] = [(0, 0), (29.9, 0), (30, 1), (89, 1), (90, 2), (330, 6), (1_500, 25),
                                            (3_600, 60), (-5, 0), (.nan, 0), (.infinity, 0), (1e30, 16_666_667)]
        for (seconds, minutes) in cases {
            expect(CategoryQuestion.minutes(fromSeconds: seconds) == minutes,
                   "\(seconds) s read as \(CategoryQuestion.minutes(fromSeconds: seconds)) min, not \(minutes)", &problems)
        }
        return problems
    }

    private static func facts(categories: Int = 3, apps: [String] = ["Xcode", "Safari", "Notes"], depth: String? = "deep",
                              site: String? = "video") -> CategoryQuestionFacts {
        CategoryQuestionFacts(
            activities: [(name: "Coding", minutes: 25), (name: "Media", minutes: 6)], depthWord: depth, appNames: apps,
            siteKind: site, categories: (1...categories).map { (id: "id.\($0)", name: "Category \($0)") })
    }

    private static func questionText() -> [String] {
        var problems: [String] = []
        let fingerprint = Fixture.fingerprint(4)
        let question = CategoryQuestion.make(facts: facts(), fingerprint: fingerprint)
        let text = question.text
        for line in ["- Coding: 25 min", "- Media: 6 min", "Depth: deep", "Apps: Xcode, Safari", "Site kind: video",
                     "1. Category 1", "2. Category 2", "3. Category 3"] {
            expect(text.contains(line), "the question lacked \"\(line)\": \(text)", &problems)
        }
        expect(!text.contains("Notes"), "a third app reached the question", &problems)
        let order = ["- Coding", "Depth:", "Apps:", "Site kind:", "1. Category 1"].map { text.range(of: $0)?.lowerBound }
        expect(order.allSatisfy { $0 != nil } && order.compactMap({ $0 }) == order.compactMap({ $0 }).sorted(),
               "the question's parts were out of order: \(text)", &problems)
        expect(question.offered == (1...3).map { WorkType(rawValue: "id.\($0)") } && question.fingerprint == fingerprint,
               "the question offered \(question.offered.map(\.rawValue))", &problems)

        let bare = CategoryQuestion.make(facts: facts(apps: [], depth: nil, site: nil), fingerprint: fingerprint).text
        for part in ["Depth", "Apps", "Site"] {
            expect(!bare.contains(part), "\(part) appeared with nothing to say: \(bare)", &problems)
        }
        let many = CategoryQuestion.make(facts: facts(categories: 25), fingerprint: fingerprint)
        expect(many.offered.count == 20 && many.offered.last?.rawValue == "id.20", "25 categories offered \(many.offered.count)", &problems)
        expect(many.text.contains("20. Category 20") && !many.text.contains("21.") && !many.text.contains("Category 21"),
               "the 21st category reached the question", &problems)
        return problems
    }

    private static func questionPrivacy() -> [String] {
        var problems: [String] = []
        let name = "Zebra Quartz Ledger", note = "Quartz invoice note", bundle = "com.distinct.bundle"
        let address = "ledger.distinct.example"
        let record = Fixture.record(name: name)
        let shape = Fixture.shape([.coding: 1_500, .media: 330, .writingAI: 61], depth: .deep,
                                  fingerprint: ActivityFingerprint(shares: [4, 0, 0, 0, 0, 1, 0], topApps: [bundle, ""], siteKind: "video"))
        // What the app does with a shape: purposes by name, minutes by the helper, apps by display name.
        let appNames = [bundle: "Xcode"]
        let credited = shape.credited.sorted { $0.value > $1.value }
        let made = CategoryQuestionFacts(
            activities: credited.map { (name: AppPurpose(rawValue: $0.key)?.modelName ?? "", minutes: CategoryQuestion.minutes(fromSeconds: $0.value)) },
            depthWord: shape.depth?.rawValue, appNames: (shape.fingerprint?.topApps ?? []).compactMap { appNames[$0] },
            siteKind: shape.fingerprint?.siteKind, categories: [(id: "deepWork", name: "Deep work")])
        guard let fingerprint = shape.fingerprint else { return ["no fingerprint"] }
        let text = CategoryQuestion.make(facts: made, fingerprint: fingerprint).text
        for secret in [name, note, bundle, address, record.id.uuidString, "Zebra", "Quartz"] {
            expect(!text.contains(secret), "the question carried \"\(secret)\": \(text)", &problems)
        }
        for line in ["- Coding: 25 min", "- Media: 6 min", "- Writing & AI: 1 min", "Apps: Xcode", "Depth: deep", "Site kind: video"] {
            expect(text.contains(line), "the question lacked \"\(line)\": \(text)", &problems)
        }
        return problems
    }

    private static func looks() -> [String] {
        var problems: [String] = []
        var symbols: [String] = []
        for purpose in AppPurpose.allCases {
            let look = LabelLook.look(for: purpose)
            symbols.append(look.symbolName)
            expect(NSImage(systemSymbolName: look.symbolName, accessibilityDescription: nil) != nil,
                   "\(purpose.rawValue)'s symbol \(look.symbolName) does not exist", &problems)
            expect(WorkTypeSymbols.curated.contains(look.symbolName),
                   "\(purpose.rawValue)'s symbol \(look.symbolName) is not in the category editor", &problems)
            expect(WorkTypeHue.selectable.contains(look.hue), "\(purpose.rawValue) was \(look.hue.displayName)", &problems)
        }
        expect(Set(symbols).count == AppPurpose.allCases.count, "two purposes shared a symbol: \(symbols)", &problems)
        return problems
    }

    private static func hiddenLabels() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        let coding = book.addUnkeptLabel(id: "ai.code", name: "Cad", dominant: .coding, fingerprint: Fixture.fingerprint(1), now: Fixture.base)
        book.labels.append(Fixture.label("ai.media", "Films", seed: 2, archived: true))
        let calls = WorkTypeDefinition(id: "custom.calls", name: "Calls", symbolName: "phone.fill", hue: .green)
        let catalogue = WorkTypeCatalog()
        catalogue.install(aiLabels: book.labels)
        catalogue.apply(customisations: [calls])
        let code = catalogue.definition(for: WorkType(rawValue: "ai.code"))
        let media = catalogue.definition(for: WorkType(rawValue: "ai.media"))
        expect(code.name == "Cad" && code.symbolName == coding?.symbolName && code.hue == coding?.hue && code.isUnkeptAILabel,
               "an unkept label resolved as \(code)", &problems)
        expect(media.name == "Films" && media.symbolName == "film.fill" && media.hue == .red && media.isUnkeptAILabel,
               "an archived label did not resolve by id: \(media)", &problems)
        expect(code.countsAsFocus && !media.countsAsFocus, "a label's focus was \(code.countsAsFocus) and \(media.countsAsFocus)", &problems)
        expect(!catalogue.activeTypes.contains { $0.rawValue.hasPrefix("ai.") } && catalogue.activeTypes.contains(calls.workType),
               "an unkept label was offered: \(catalogue.activeTypes.map(\.rawValue))", &problems)
        expect(!catalogue.allDefinitions.contains { $0.id.hasPrefix("ai.") } && catalogue.allDefinitions.contains(calls),
               "an unkept label was listed in Settings", &problems)
        // Kept: the same id in the person's categories is theirs, shown and listed.
        let kept = WorkTypeDefinition(id: "ai.media", name: "Movies", symbolName: "film.fill", hue: .pink)
        catalogue.install(aiLabels: book.labels)
        catalogue.apply(customisations: [calls, kept])
        expect(catalogue.definition(for: WorkType(rawValue: "ai.media")) == kept && catalogue.allDefinitions.contains(kept),
               "a kept label did not take the person's definition", &problems)
        // Gone from the book: the records that carry it read "Other", as any category this build does not know.
        catalogue.install(aiLabels: [])
        catalogue.apply(customisations: [calls])
        expect(catalogue.definition(for: WorkType(rawValue: "ai.code")).name == "Other", "a label left the book and still resolved", &problems)
        return problems
    }
}
